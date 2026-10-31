# frozen_string_literal: true

require "cgi"
require "erb"
require "json"

module Agent
  module Evals
    # Builds a self-contained HTML report for completed eval runs.
    # Only contenders with full, error-free coverage can lead the report.
    class HtmlReport
      # Directory containing the report template and its embedded assets.
      TEMPLATE_DIRECTORY = File.expand_path("templates", __dir__)

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

      # Renders the template with report data and embedded assets.
      #
      # @return [String]
      def render
        health = health_summary
        standings = global_standings
        datasets = dataset_reports
        ERB.new(File.read(template_path), trim_mode: "-").result(binding)
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

      # @return [Hash{Symbol => Object}] health counts and cost for the template
      def health_summary
        failed = results.count { !it.score || it.failed? || it.reply&.error? }
        {
          successful: successful_results.size,
          total:      results.size,
          failed:,
          cost:       money(total_usage.cost_usd)
        }
      end

      # @return [Hash{Symbol => Object}] report entries and ranking after coverage checks
      def global_standings
        expected_keys = results.map { it.case.key }.uniq
        entries = configuration_groups.map { |group| contender(group, expected_keys) }
        complete = entries.select { it[:complete] }
        assign_weighted_scores(complete)
        ranked = complete.sort_by { ranking_value(it) || -1 }

        {
          entries:,
          expected_count: expected_keys.length,
          ranked:,
          leader: ranked.last,
          best_coverage: entries.max_by { it[:successful] }
        }
      end

      # @return [Array<Hash{Symbol => Object}>] data for each dataset section
      def dataset_reports
        summaries.group_by(&:dataset).sort.map do |dataset, group|
          case_keys = group.flat_map { it.results.map { it.case.key } }.uniq
          entries = group.map { contender([it], case_keys) }
          complete = entries.select { it[:complete] }
          assign_weighted_scores(complete)

          {
            name:      dataset,
            summaries: group,
            case_keys:,
            winner:    complete.max_by { ranking_value(it) || -1 },
            entries:   entries.sort_by { ranking_value(it) || -1 }.reverse,
            cases:     group.flat_map(&:results).group_by { it.case.key }.values.map(&:first)
                            .sort_by { [it.case.variant, it.case.number || 0, it.case.id] }
          }
        end
      end

      # @param kase [Case]
      # @param group [Array<Experiment::Summary>]
      # @return [Array<Hash{Symbol => Object}]] runs and display values for one case
      def case_results(kase, group)
        group.flat_map(&:results).select { it.case.key == kase.key }.map do |run|
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
          { run:, status:, details: details || {} }
        end
      end

      # @param group [Array<Experiment::Summary>]
      # @param expected_keys [Array<String>]
      # @return [Hash{Symbol => Object}] model coverage and score inputs
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
        successful_keys = successful.map { it.case.key }.uniq

        {
          model:      group.first.model,
          successful: successful_keys.length,
          total:      expected_keys.length,
          errors:,
          cost:,
          row:,
          complete:   expected_keys.length.positive? && successful_keys.sort == expected_keys.uniq.sort && errors.zero?
        }
      end

      # @return [Array<Array<Experiment::Summary>>]
      def configuration_groups
        summaries.group_by { [it.model.key, it.model.effort, it.model.temperature] }.values
      end

      # @param entries [Array<Hash{Symbol => Object}>]
      # @return [void]
      def assign_weighted_scores(entries)
        scores = if weighted_score
                   weighted_score.call(entries.map { it[:row] })
                 else
                   entries.map { it[:row][primary_metric] }
                 end
        entries.zip(scores).each { |entry, score| entry[:ranking] = score }
      end

      # @param entry [Hash{Symbol => Object}]
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
      # @return [Array<String>] HTML-escaped provider and model names
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
      # @return [String] HTML-escaped text
      def escape(value) = CGI.escapeHTML(value.to_s)

      # @return [String]
      def stylesheet = asset("html_report.css")

      # @return [String]
      def sorting_script = asset("html_report.js")

      # Reads one packaged asset for embedding in the standalone report.
      #
      # @param name [String] report asset filename
      # @return [String]
      def asset(name) = File.read(File.join(TEMPLATE_DIRECTORY, name))

      # @return [String]
      def template_path = File.join(TEMPLATE_DIRECTORY, "html_report.html.erb")
    end
  end
end
