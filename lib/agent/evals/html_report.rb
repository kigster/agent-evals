# frozen_string_literal: true

require "cgi"
require "json"

module Agent
  module Evals
    # Builds a self-contained HTML report for one or more completed eval runs.
    # The report ranks only contenders that answered every case in the run.
    class HtmlReport
      # @param summaries [Array<Experiment::Summary>]
      # @param metrics [Array<Metric>]
      # @param weighted_score [WeightedScore, nil]
      # @return [String]
      def self.render(summaries, metrics:, weighted_score: nil)
        new(summaries, metrics:, weighted_score:).render
      end

      # @return [Array<Experiment::Summary>]
      attr_reader :summaries

      # @return [Array<Metric>]
      attr_reader :metrics

      # @return [WeightedScore, nil]
      attr_reader :weighted_score

      # @param summaries [Array<Experiment::Summary>]
      # @param metrics [Array<Metric>]
      # @param weighted_score [WeightedScore, nil]
      def initialize(summaries, metrics:, weighted_score: nil)
        @summaries = summaries
        @metrics = metrics
        @weighted_score = weighted_score
      end

      # Renders the complete, standalone report.
      #
      # @return [String]
      def render
        <<~HTML
          <!doctype html>
          <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
          <title>#{escape(report_title)}</title><style>#{styles}#{responsive_styles}</style></head>
          <body><main>
          <h1>#{escape(report_title)}</h1><p class="muted">#{escape(configuration_name)} · generated #{Time.now.strftime("%Y-%m-%d %H:%M %Z")}</p>
          #{health_section}
          #{global_section}
          #{dataset_sections}
          </main><script>#{sorting_script}</script></body></html>
        HTML
      end

      private

      # @return [String]
      def report_title = "#{configuration_name} evaluation report"

      # @return [String]
      def configuration_name = Agent::Evals.configuration.name

      # @return [Array<RunResult>]
      def results = summaries.flat_map(&:results)

      # @return [Array<RunResult>]
      def successful_results = results.select { it.score && !it.failed? && !it.reply&.error? }

      # @return [String]
      def health_section
        failed_count = results.count { !it.score || it.failed? || it.reply&.error? }
        <<~HTML
          <section class="health" aria-label="Run health">
            #{stat("#{successful_results.size}/#{results.size}", "model calls scored")}
            #{stat(failed_count.to_s, "failed calls")}
            #{stat(money(total_usage.cost_usd), "recorded cost")}
          </section>
          #{'<p class="notice">This run has failed or unscored cases. A global leader requires full, error-free coverage.</p>' if failed_count.positive?}
        HTML
      end

      # @return [String]
      def global_section
        groups = configuration_groups
        expected_keys = results.map { it.case.key }.uniq
        entries = groups.map { |group| contender(group, expected_keys) }
        complete = entries.select { it[:complete] }
        assign_weighted_scores(complete)
        ranked = complete.sort_by { ranking_value(it) || -1 }
        leader = ranked.last
        <<~HTML
          <section>
            <h2>Global standings across all cases in this run</h2>
            <p class="muted">#{escape(weight_description)}</p>
            #{global_leader(leader, entries, expected_keys.length)}
            #{global_chart(ranked)}
            #{coverage_table(entries)}
          </section>
        HTML
      end

      # @param leader [Hash, nil]
      # @param entries [Array<Hash>]
      # @param expected_count [Integer]
      # @return [String]
      def global_leader(leader, entries, expected_count)
        if leader
          %(<div class="leader"><span class="eyebrow">ALL-CASE LEADER</span><strong>#{model_label(leader[:model])}</strong><span>#{percent(ranking_value(leader))} · Effort #{effort_label(leader[:model])} · Temperature #{temperature_label(leader[:model])} · #{leader[:successful]}/#{expected_count} cases · #{money(leader[:cost])}</span></div>)
        else
          best_coverage = entries.max_by { it[:successful] }
          message = if best_coverage
                      "No contender covered all #{expected_count} cases without failures. Best coverage: #{best_coverage[:successful]}/#{expected_count} from #{model_label(best_coverage[:model])} (effort #{effort_label(best_coverage[:model])}, temperature #{temperature_label(best_coverage[:model])})."
                    else
                      "No model results are available for ranking."
                    end
          %(<div class="leader none"><span class="eyebrow">ALL-CASE LEADER</span><strong>No leader established</strong><span>#{message}</span></div>)
        end
      end

      # @param ranked [Array<Hash>]
      # @return [String]
      def global_chart(ranked)
        return '<p class="muted">No fully covered contenders to plot.</p>' if ranked.empty?

        rows = ranked.map do |entry|
          score = ranking_value(entry).to_f
          %(<div class="bar-row"><span>#{model_label(entry[:model])}<small class="settings">Effort #{effort_label(entry[:model])} · Temperature #{temperature_label(entry[:model])}</small></span><div class="track" role="meter" aria-valuemin="0" aria-valuemax="100" aria-valuenow="#{(score * 100).round(1)}"><i style="width:#{(score * 100).clamp(0, 100)}%"></i></div><b>#{percent(score)}</b></div>)
        end.join
        %(<div class="chart" aria-label="Model standings, worst to best">#{rows}</div>)
      end

      # @param entries [Array<Hash>]
      # @return [String]
      def coverage_table(entries)
        rows = entries.sort_by { [it[:successful], ranking_value(it) || -1] }.map do |entry|
          score = entry[:complete] ? percent(ranking_value(entry)) : "Not rankable"
          %(<tr>#{model_cells(entry[:model])}<td>#{effort_label(entry[:model])}</td><td>#{temperature_label(entry[:model])}</td><td>#{entry[:successful]}/#{entry[:total]}</td><td>#{score}</td><td>#{entry[:errors]}</td><td>#{money(entry[:cost])}</td></tr>)
        end.join
        %(<h3>Coverage by model</h3><div class="scroll"><table class="sortable"><thead><tr><th>Provider</th><th>Model</th><th>Effort</th><th>Temperature</th><th>Scored</th><th>Weighted score</th><th>Errors</th><th>Cost</th></tr></thead><tbody>#{rows}</tbody></table></div>)
      end

      # @return [String]
      def dataset_sections
        summaries.group_by(&:dataset).sort.map do |dataset, group|
          dataset_section(dataset, group)
        end.join
      end

      # @param dataset [String]
      # @param group [Array<Experiment::Summary>]
      # @return [String]
      def dataset_section(dataset, group)
        case_keys = group.flat_map { it.results.map { it.case.key } }.uniq
        entries = group.map { contender([it], case_keys) }
        complete = entries.select { it[:complete] }
        assign_weighted_scores(complete)
        winner = complete.max_by { ranking_value(it) || -1 }
        summary = winner ? "Leader: #{model_label(winner[:model])} · effort #{effort_label(winner[:model])} · temperature #{temperature_label(winner[:model])} · #{percent(ranking_value(winner))}" : "No complete contender"
        models = entries.sort_by { ranking_value(it) || -1 }.reverse.map { model_row(it) }.join
        cases = group.flat_map(&:results).group_by { it.case.key }.values.map(&:first).sort_by { [it.case.variant, it.case.number || 0, it.case.id] }
        <<~HTML
          <details class="dataset">
            <summary><strong>#{escape(dataset)}</strong><span>#{summary} · #{case_keys.length} cases</span></summary>
            <div class="dataset-content">
              <h3>Model scores</h3><div class="scroll"><table class="sortable"><thead><tr><th>Provider</th><th>Model</th><th>Effort</th><th>Temperature</th><th>Weighted score</th><th>Scored</th><th>Errors</th><th>Cost</th></tr></thead><tbody>#{models}</tbody></table></div>
              <h3>Cases</h3>
              #{cases.map { case_detail(it, group) }.join}
            </div>
          </details>
        HTML
      end

      # @param entry [Hash]
      # @return [String]
      def model_row(entry)
        score = entry[:complete] ? percent(ranking_value(entry)) : "Not rankable"
        %(<tr>#{model_cells(entry[:model])}<td>#{effort_label(entry[:model])}</td><td>#{temperature_label(entry[:model])}</td><td>#{score}</td><td>#{entry[:successful]}/#{entry[:total]}</td><td>#{entry[:errors]}</td><td>#{money(entry[:cost])}</td></tr>)
      end

      # @param result [RunResult]
      # @param group [Array<Experiment::Summary>]
      # @return [String]
      def case_detail(result, group)
        kase = result.case
        output_rows = group.flat_map(&:results).select { it.case.key == kase.key }.map do |run|
          status = if run.failed?
                     run.error
                   elsif run.reply&.error?
                     run.reply.error
                   elsif run.score
                     percent(run.score.value)
                   else
                     "No score"
                   end
          details = run.score&.diagnostics
          details = { "error" => run.error } if run.failed?
          %(<tr>#{model_cells(run.experiment.model)}<td>#{effort_label(run.experiment.model)}</td><td>#{temperature_label(run.experiment.model)}</td><td>#{escape(status)}</td><td><pre>#{escape(pretty(details || {}))}</pre></td></tr>)
        end.join
        expected = kase.expected.nil? ? "No expected answer" : pretty(kase.expected)
        <<~HTML
          <details class="case">
            <summary><strong>#{escape(kase.id)}</strong><span>#{escape(kase.variant)} · difficulty #{kase.difficulty}</span></summary>
            <div class="case-content">
              <details><summary>Input and expected answer</summary><h4>Input</h4><pre>#{escape(kase.input)}</pre><h4>Expected</h4><pre>#{escape(expected)}</pre></details>
              <div class="scroll"><table class="sortable"><thead><tr><th>Provider</th><th>Model</th><th>Effort</th><th>Temperature</th><th>Score / status</th><th>Diagnostics</th></tr></thead><tbody>#{output_rows}</tbody></table></div>
            </div>
          </details>
        HTML
      end

      # @param group [Array<Experiment::Summary>]
      # @param expected_keys [Array<String>]
      # @return [Hash]
      def contender(group, expected_keys)
        group_results = group.flat_map(&:results).uniq { it.case.key }
        successful = group_results.select { it.score && !it.failed? && !it.reply&.error? }
        errors = group_results.count { !it.score || it.failed? || it.reply&.error? }
        metric_values = metrics.to_h do |metric|
          values = group_results.filter_map { it.score&.metrics&.fetch(metric.name, nil) }
          [metric.name, mean(values)]
        end
        score_values = group_results.filter_map { it.score&.value unless it.failed? || it.reply&.error? }
        cost = group.sum { it.usage.cost_usd }
        row = metric_values.merge(
          "score"  => mean(score_values),
          "errors" => errors,
          "time"   => group.sum(&:duration),
          "cost"   => cost
        )
        {
          model:      group.first.model,
          successful: successful.map { it.case.key }.uniq.length,
          total:      expected_keys.length,
          errors:,
          cost:,
          row:,
          complete:   expected_keys.length.positive? && successful.map { it.case.key }.uniq.sort == expected_keys.uniq.sort && errors.zero?
        }
      end

      # @param groups [Array<Array<Experiment::Summary>>]
      # @return [Array<Hash>]
      def configuration_groups
        summaries.group_by { [it.model.key, it.model.effort, it.model.temperature] }.values
      end

      # @param entries [Array<Hash>]
      # @return [void]
      def assign_weighted_scores(entries)
        scores = if weighted_score
                   weighted_score.call(entries.map { it[:row] })
                 else
                   entries.map { it[:row][primary_metric] }
                 end
        entries.zip(scores).each { |entry, score| entry[:ranking] = score }
      end

      # @param entry [Hash]
      # @return [Float, nil]
      def ranking_value(entry) = entry[:ranking]

      # @return [String]
      def primary_metric = metrics.find(&:primary)&.name || "score"

      # @return [String]
      def weight_description
        weighted_score ? "Weighted score from the lineup; chart order runs worst to best." : "Ranked by #{primary_metric}; chart order runs worst to best."
      end

      # @return [Usage]
      def total_usage = summaries.map(&:usage).reduce(Usage.zero, :+)

      # @param model [Model]
      # @param model [Model]
      # @return [String] escaped, color-coded provider and model name
      def model_label(model)
        provider, name = model_parts(model)
        %(<span class="provider">#{provider}</span>/<span class="model-id">#{name}</span>)
      end

      # @param model [Model]
      # @return [String] provider and model cells for sortable tables
      def model_cells(model)
        provider, name = model_parts(model)
        %(<td><span class="provider">#{provider}</span></td><td><span class="model-id">#{name}</span></td>)
      end

      # @param model [Model]
      # @return [Array<String>] escaped provider and model names
      def model_parts(model)
        provider, name = model.id.to_s.split("/", 2)
        [escape(provider), escape(name || provider)]
      end

      # @param model [Model]
      # @return [String] escaped effort setting, or `default`
      def effort_label(model) = escape(model.effort || "default")

      # @param model [Model]
      # @return [String] escaped temperature setting, or `default`
      def temperature_label(model) = escape(model.temperature.nil? ? "default" : model.temperature)

      # @param value [String]
      # @param label [String]
      # @return [String]
      def stat(value, label) = %(<div class="stat"><b>#{escape(value)}</b><span>#{escape(label)}</span></div>)

      # @param values [Array<Numeric>]
      # @return [Float, nil]
      def mean(values) = values.empty? ? nil : values.sum.fdiv(values.size)

      # @param value [Numeric, nil]
      # @return [String]
      def percent(value) = value.nil? ? "—" : format("%.1f%%", value * 100)

      # @param value [Numeric]
      # @return [String]
      def money(value) = format("$%.4f", value.to_f)

      # @param value [Object]
      # @return [String]
      def pretty(value) = JSON.pretty_generate(value)

      # @param value [Object]
      # @return [String]
      def escape(value) = CGI.escapeHTML(value.to_s)

      # @return [String]
      def styles
        <<~CSS.gsub(/\s+/, " ")
          :root{color-scheme:light dark;--bg:#0d1117;--panel:#161b22;--text:#e6edf3;--muted:#8b949e;--line:#30363d;--blue:#58a6ff;--green:#3fb950;--orange:#ff9f43;--red:#f85149}
          *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 system-ui,sans-serif}main{max-width:1120px;margin:auto;padding:36px 22px 80px}h1{font-size:28px;margin:0}h2{font-size:20px;margin:0 0 8px}h3{font-size:15px;margin:22px 0 10px}.muted{color:var(--muted)}section,.dataset{background:var(--panel);border:1px solid var(--line);border-radius:10px;margin:16px 0;padding:18px}.health{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px;padding:0;border:0;background:none}.stat{border:1px solid var(--line);border-radius:9px;padding:14px;background:var(--panel)}.stat b{display:block;font-size:23px}.stat span,.eyebrow{color:var(--muted)}.notice{border-left:4px solid var(--red);padding:12px;background:#f8514918}.leader{display:grid;gap:5px;padding:15px;border:1px solid var(--green);border-radius:8px;background:#3fb95012;margin:16px 0}.leader.none{border-color:var(--red);background:#f8514912}.leader strong{font-size:20px}.eyebrow{font-size:11px;letter-spacing:.08em}.provider{color:var(--green);font-weight:600}.model-id{color:var(--orange);font-weight:700}.settings{display:block;color:var(--muted);font-size:12px}.bar-row{display:grid;grid-template-columns:minmax(190px,2fr) 4fr 70px;gap:12px;align-items:center;margin:10px 0}.track{height:12px;background:var(--line);border-radius:99px;overflow:hidden}.track i{display:block;height:100%;background:linear-gradient(90deg,var(--blue),var(--green))}table{border-collapse:collapse;width:100%;min-width:700px}th,td{text-align:left;vertical-align:top;padding:9px;border-top:1px solid var(--line)}th{color:var(--muted);font-weight:500}.sortable th{cursor:pointer;user-select:none}.sortable th::after{content:" ↕";color:var(--muted);font-size:11px}.sortable th[aria-sort="ascending"]::after{content:" ↑"}.sortable th[aria-sort="descending"]::after{content:" ↓"}.sortable th:focus-visible{outline:2px solid var(--blue);outline-offset:-2px}.scroll{overflow-x:auto}.dataset{padding:0;overflow:hidden}.dataset>summary,.case>summary{display:flex;justify-content:space-between;gap:16px;cursor:pointer;list-style:none;padding:15px}.dataset>summary::-webkit-details-marker,.case>summary::-webkit-details-marker{display:none}.dataset>summary span,.case>summary span{color:var(--muted)}.dataset-content{padding:0 16px 18px}.case{border:1px solid var(--line);border-radius:8px;margin:8px 0;overflow:hidden}.case>summary{padding:10px 12px}.case-content{padding:0 12px 12px}.case-content pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#0d1117;padding:10px;border-radius:6px;max-height:360px;overflow:auto}pre{font:12px/1.5 ui-monospace,monospace}.case-content details{margin:8px 0}.case-content details>summary{cursor:pointer;color:var(--blue)}@media(max-width:700px){main{padding:22px 14px 50px}.health{grid-template-columns:1fr}.bar-row{grid-template-columns:1fr 2fr 60px}.dataset>summary{display:block}.dataset>summary span{display:block}}
        CSS
      end

      # Makes every result table sortable by clicking or focusing a column heading.
      #
      # @return [String]
      def sorting_script
        <<~JS.gsub(/\s+/, " ")
          document.querySelectorAll("table.sortable").forEach((table) => {
            const headers = Array.from(table.querySelectorAll("thead th"));
            const body = table.tBodies[0];
            headers.forEach((header, index) => {
              header.tabIndex = 0;
              header.setAttribute("aria-sort", "none");
              const sort = () => {
                const ascending = header.dataset.direction !== "ascending";
                headers.forEach((item) => {
                  item.dataset.direction = "";
                  item.setAttribute("aria-sort", "none");
                });
                header.dataset.direction = ascending ? "ascending" : "descending";
                header.setAttribute("aria-sort", header.dataset.direction);
                const rows = Array.from(body.rows);
                rows.sort((left, right) => {
                  const first = left.cells[index]?.textContent.trim() ?? "";
                  const second = right.cells[index]?.textContent.trim() ?? "";
                  const number = (value) => {
                    const normalized = value.replace(/[,$%]/g, "");
                    return /^-?\\d+(?:\\.\\d+)?$/.test(normalized) ? Number(normalized) : null;
                  };
                  const firstNumber = number(first);
                  const secondNumber = number(second);
                  const comparison = firstNumber !== null && secondNumber !== null
                    ? firstNumber - secondNumber
                    : first.localeCompare(second, undefined, { numeric: true, sensitivity: "base" });
                  return ascending ? comparison : -comparison;
                });
                rows.forEach((row) => body.append(row));
              };
              header.addEventListener("click", sort);
              header.addEventListener("keydown", (event) => {
                if (event.key === "Enter" || event.key === " ") {
                  event.preventDefault();
                  sort();
                }
              });
            });
          });
        JS
      end

      # Lets wide result tables use desktop space and scroll within their own
      # containers on smaller screens.
      #
      # @return [String]
      def responsive_styles
        <<~CSS.gsub(/\s+/, " ")
          main{max-width:1520px;padding:36px 28px 80px}
          table{width:100%;min-width:980px}
          .scroll{max-width:100%;overflow-x:auto;overscroll-behavior-inline:contain;-webkit-overflow-scrolling:touch}
          th:first-child,td:first-child{white-space:nowrap}
          @media(max-width:900px){main{padding:24px 16px 60px}.scroll{margin-inline:0}}
          @media(max-width:700px){main{padding:18px 10px 40px}section{padding:14px}.dataset-content{padding:0 10px 12px}.health{grid-template-columns:1fr}table{min-width:900px}}
        CSS
      end
    end
  end
end
