# frozen_string_literal: true

require "fileutils"
require "pathname"

module Agent
  module Evals
    module CLI
      # The options shared by the commands that call a model. Settings resolve
      # flag first, then the config entry, then .agent-eval.config.yml's defaults.
      #
      # Every column that is not a metric is the gem's; the metric columns,
      # their glossary and the ranking come from the suite's {Scorer#metrics}.
      class ModelCommand < Command
        # How close to the best primary metric a model must come to compete on
        # price: 0.02 is two percentage points.
        VALUE_MARGIN = 0.02

        # What the gem's own leaderboard columns mean, printed under it with the metrics'.
        GLOSSARY = {
          "effort"  => "Reasoning effort sent to the model. \"default\" sends none, and the model decides; " \
                       "a provider that takes none shows \"default\" too.",
          "temp"    => "Sampling temperature sent to the model. \"default\" sends none.",
          "errors"  => "Cases whose call failed outright (an API or network error), so they have no scores at all. " \
                       "A reply the model got wrong is not an error; it scores 0.",
          "time"    => "Wall-clock time for the experiment. Experiments run side by side and share the network, " \
                       "so compare times within one run only.",
          "tok_in"  => "Input tokens sent, summed over the cases, as the provider counted them.",
          "tok_out" => "Output tokens received, summed over the cases; reasoning tokens are included where the " \
                       "provider bills them as output.",
          "cost"    => "US dollars, as the provider reported them, summed over the cases.",
          "score"   => "The mean of each case's overall score, as the scorer computed it. With --scores, a table " \
                       "ranks every experiment by it."
        }.freeze

        def self.inherited(subclass)
          super
          subclass.extend(Dry::CLI::UI::Flags)
          subclass.flags(:dry_run, :output)
          subclass.option :models,
            type:    :array,
            aliases: ["-m"],
            default: [],
            desc:    "Model ids, comma-separated, instead of the config file's vendors"
          subclass.option :dataset,
            type:    :array,
            aliases: ["-d"],
            default: [],
            desc:    "Datasets, comma-separated; every dataset when omitted. Each model runs on each"
          subclass.option :config, aliases: ["-C"], desc: "The lineup file (default: the suite's .agent-eval.config.yml)"
          subclass.option :effort, aliases: ["-e"], desc: "Reasoning effort: default, or one the provider accepts (overrides the config file)"
          subclass.option :temperature, aliases: ["-t"], desc: "Sampling temperature, or 'default' to send none (overrides the config file)"
          subclass.option :max_tokens, desc: "Output token cap, reasoning included (overrides the config file)"
          subclass.option :case,
            type:    :array,
            aliases: ["-c"],
            default: [],
            desc:    "Only these cases, by id prefix: -c clear or -c clear/003,vague/001"
          subclass.option :parallelism, aliases: ["-p"], desc: "Cases in flight at once, per model (default: the config's defaults.parallelism)"
          subclass.option :concurrency,
            aliases: ["-j"],
            desc:    "Experiments running at once; 0 runs them all together (default: the number of CPUs)"
          subclass.option :project,
            desc: "Braintrust project name; default is the BRAINTRUST_PROJECT_ID project, else the config file's project"
          subclass.option :open,
            type:    :boolean,
            default: true,
            desc:    "Open the best experiment in the browser when done (no effect with --local)"
          subclass.option :scores,
            type:    :boolean,
            default: false,
            desc:    "Also print every experiment by score, with its cost and its tracker's link"
          subclass.option :format,
            default: "tui",
            values:  %w[tui html json],
            desc:    "Report format: tui for the terminal, html or json for a saved report"
          subclass.option :local,
            type:    :boolean,
            default: false,
            desc:    "No remote tracker: results go to log/ only (still calls the models)"
          subclass.option :tracker,
            desc: "The remote tracker: braintrust, logfire, none, or one the suite registers " \
                  "(default: the config's tracker:, else the one whose key is in the environment)"
        end

        private

        # @return [Config] the lineup: --config, else the suite's
        def lineup(options) = options[:config] ? Config.new(File.expand_path(options[:config])) : configuration.lineup

        # @return [Providers::Registry]
        def providers = configuration.providers

        # @return [Scorer]
        def scorer = configuration.scorer

        # @return [Array<Metric>]
        def metrics = scorer.metrics

        # Reads the file's weights before anything is spent, so a bad one fails
        # the run rather than the report at its end.
        #
        # @return [WeightedScore, nil] nil when the file sets none
        # @raise [Error] on a bad weight
        def weigh(config)
          weights = config.score_weights
          @weighted = weights.empty? ? nil : WeightedScore.new(weights, metrics: metrics.map(&:name))
        end

        # @return [Hash{String => Object}] the setting flags that were given
        def overrides(options)
          { "effort" => options[:effort], "temperature" => options[:temperature], "max_tokens" => options[:max_tokens] }
        end

        def experiment(contender, config, options, dataset:)
          Experiment.new(
            model:       providers.model_for(contender),
            cases:       cases_for(options[:case], dataset: dataset),
            adapter:     configuration.adapter,
            scorer:      scorer,
            parallelism: Integer(options[:parallelism] || config.defaults["parallelism"]),
            trackers:    trackers_for(config, options)
          )
        end

        # The local JSON log, always, then the one remote tracker if any,
        # each experiment getting instances of its own.
        #
        # @return [Array<Tracker>]
        def trackers_for(config, options)
          context = { suite:      configuration.name,
                      project:    options[:project] || config.project || configuration.project || configuration.name,
                      project_id: options[:project] ? nil : ENV["BRAINTRUST_PROJECT_ID"].to_s[/\S+/] }
          local = Trackers::Local.new(dir: File.join(Dry::CLI::UI::Invocation.root(Dir.pwd), "log", "agent-evals"), **context)
          klass = remote_tracker(config, options)
          remote = klass&.new(**context, options: config.tracker_options(klass.tracker_name))
          [local, remote].compact
        end

        # The remote tracker class this run uses, chosen once: --tracker,
        # then tracker: in the config, then the environment. --local is none.
        #
        # @return [Class<Tracker>, nil]
        def remote_tracker(config, options)
          return @remote_tracker if defined?(@remote_tracker)

          chosen = configuration.trackers.choose(flag: options[:tracker], config: config.tracker, env: ENV, local: options[:local])
          @remote_tracker = chosen&.first
          err.puts "tracker: #{chosen ? "#{chosen.first.tracker_name}, because #{chosen.last}" : "none"}" if options[:verbose]
          @remote_tracker
        end

        # The contenders a command runs: the models named on the command line,
        # or every model .agent-eval.config.yml lists.
        #
        # @param models [Array<String>] as given to -m, possibly comma-separated
        # @return [Array<Contender>]
        # @raise [Error] when neither names any model
        def contenders(config, models, options)
          models = models.flat_map { it.split(",") }
          found = models.empty? ? config.contenders(overrides(options)) : config.contenders_for(models, overrides(options))
          raise Error, "no models: list some under vendors in #{config.path}, or pass -m" if found.empty?

          admit(found, config)
        end

        # Keeps the contenders whose provider produces what the suite declares
        # in `request_types`, and records each refusal in {#warnings} by name,
        # so a refused model is reported rather than run, failed and billed.
        #
        # @return [Array<Contender>] the admitted contenders
        # @raise [Error] when none is admitted, naming every refusal
        def admit(found, config)
          found.each { providers.for(it) } # an unserved id fails here, before anything is spent
          admitted, refusals = providers.admit(found, request_types: config.request_types)
          refusals.each { warnings.record(it.to_s) }
          raise Error, "no admitted models: #{refusals.join("; ")}" if admitted.empty?

          admitted
        end

        # Env, the tracker's gems and key, hooks, provider clients, then the catalogs.
        def setup!(contenders, options)
          configuration.runtime.setup!(providers: providers.used_by(contenders), tracker: remote_tracker(lineup(options), options))
          providers.verify!(contenders)
        end

        # What -n prints: every experiment that would run, and where the
        # refusals went, if there were any.
        def matrix(datasets, contenders)
          rows = datasets.product(contenders).map { |name, c| [name, c.model, c.effort, c.temperature, c.max_tokens] }
          table(rows, header: %w[dataset model effort temp max_tokens])
          save_warnings
        end

        # Runs the experiments side by side, a progress bar each. What would
        # print as a warning meanwhile, failed cases included, goes to
        # {#warnings} instead.
        #
        # @param runs [Array<Experiment>]
        # @param concurrency [Integer] experiments at once; 0 runs them all together
        # @return [Array<Experiment::Summary>]
        def execute(runs, concurrency:)
          summaries = Array.new(runs.size)
          warnings.capture { bars(runs, summaries, concurrency) }
          summaries.compact.each { |s| s.errors.each { warnings.record("[#{s.name}] #{it}") } }
          summaries.compact
        end

        # -j, else one experiment per CPU. Uncapped, a full lineup started
        # every model x dataset pair at once: 140 experiments, each with its
        # own pool of case threads, all fighting for the network and the screen.
        #
        # @return [Integer] experiments at once; 0 means all of them
        # @raise [Error] on a negative or non-numeric -j
        def concurrency(options)
          value = options[:concurrency] || Etc.nprocessors
          Integer(value).tap { raise Error, "--concurrency must be 0 or more, got #{value}" if it.negative? }
        rescue ArgumentError, TypeError
          raise Error, "--concurrency must be a whole number, got #{value.inspect}"
        end

        # @return [Warnings] what this command has held back from the screen
        def warnings = @warnings ||= Warnings.new

        def bars(runs, summaries, concurrency)
          ProgressBars.for(ui, colors: model_colors).run("Running #{runs.size} experiment#{"s" unless runs.size == 1}",
            concurrent: concurrency.zero? || concurrency) do |multi|
            labels = ProgressBars.labels(runs)
            runs.each_with_index do |run, index|
              multi.progress(labels[index], total: run.cases.size) do |bar|
                summaries[index] = run.run(on_case: -> { bar.advance })
              end
            end
          end
        end

        # @param names [Array<String>] as given to -d, possibly comma-separated; empty means every dataset
        # @return [Array<String>]
        # @raise [Error] on an unknown dataset, before anything is spent
        def datasets(names)
          names = names.flat_map { it.split(",") }.uniq
          return discovery.datasets.tap { raise Error, "no datasets under #{discovery.root}" if it.empty? } if names.empty?

          names.each { discovery.cases(dataset: it) }
        end

        # Prints what the block writes, then the leaderboard, its glossary and
        # the scores; then says where the warnings went, if any, and opens the
        # best-scoring experiment.
        #
        # TUI reports keep their existing terminal and -o behavior. HTML and
        # JSON reports are saved artifacts, defaulting under log/.
        #
        # @param summaries [Array<Experiment::Summary>]
        # @param output [String, nil] what -o was given: nil, "-", "" for the default file, or a path
        # @param open [Boolean]
        # @param scores [Boolean] also print every experiment by score
        # @param format [String] `tui`, `html` or `json`
        # @return [void]
        def report(summaries, output:, open:, scores: false, format: "tui", &details)
          return html_report(summaries, output:, open:) if format == "html"
          return json_report(summaries, output:) if format == "json"

          path = invocation.report_path(output)
          if path
            File.open(path, "w") do |file|
              report = Dry::CLI::UI::Report.new(file)
              writing_to(report) do
                details&.call
                leaderboard(summaries, scores: scores)
              end
              report.puts "Closed at #{Time.now.strftime("%Y-%m-%d %H:%M:%S %z")}"
            end
          else
            details&.call
          end
          leaderboard(summaries, scores: scores)
          status_box(:info, "Report written to #{relative(path)}", stream: err) if path
          save_warnings
          url = summaries.max_by { it.score || -1 }&.permalink
          status_box(:warning, "could not open #{url}", stream: err) if open && url && !configuration.runtime.browse(url)
        end

        # Saves a reusable, self-contained JSON snapshot of the completed run.
        # A later `agent-evals render` turns it into HTML without model calls.
        #
        # @param summaries [Array<Experiment::Summary>]
        # @param output [String, nil]
        # @return [void]
        def json_report(summaries, output:)
          path = if output == "-"
                   nil
                 elsif output.nil? || output.empty?
                   invocation.report_path("").sub(/\.log\z/, ".json")
                 else
                   invocation.report_path(output)
                 end
          document = ReportJson.dump(summaries, metrics:, weighted_score: @weighted)
          path ? File.write(path, document) : out.write(document)
          status_box(:success, "JSON report written to #{relative(path)}", stream: err) if path
          save_warnings
        end

        # Writes the standalone HTML report without printing a terminal table.
        # A dash writes the HTML document to stdout; omitted -o picks a timestamped
        # file under log/.
        #
        # @param summaries [Array<Experiment::Summary>]
        # @param output [String, nil]
        # @param open [Boolean]
        # @return [void]
        def html_report(summaries, output:, open:)
          path = if output == "-"
                   nil
                 elsif output.nil? || output.empty?
                   invocation.report_path("").sub(/\.log\z/, ".html")
                 else
                   invocation.report_path(output)
                 end
          document = HtmlReport.render(summaries, metrics:, weighted_score: @weighted)
          path ? File.write(path, document) : out.write(document)
          status_box(:success, "HTML report written to #{relative(path)}", stream: err) if path
          save_warnings
          url = summaries.max_by { it.score || -1 }&.permalink
          status_box(:warning, "could not open #{url}", stream: err) if open && url && !configuration.runtime.browse(url)
        end

        # Saves {#warnings}, if there are any, to
        # log/<command>.warnings.<YYYY-MM-DD>.<HHMMSS>.log at the repository
        # root, stamped with the time the process started, and says how many.
        #
        # @return [void]
        def save_warnings
          return if warnings.none?

          stamp = Dry::CLI::UI.started_at.strftime("%Y-%m-%d.%H%M%S")
          path = File.join(Dry::CLI::UI::Invocation.root(Dir.pwd), "log", "#{invocation.action}.warnings.#{stamp}.log")
          FileUtils.mkdir_p(File.dirname(path))
          warnings.save(path)
          count = warnings.count
          status_box(:warning, "#{count} #{count == 1 ? "Warning was" : "Warnings were"} recorded in #{relative(path)}", stream: err)
        end

        # @return [Dry::CLI::UI::Invocation] how the command was run, which names its files
        def invocation = ui.send(:invocation)

        def relative(path) = Pathname(path).relative_path_from(Dir.pwd).to_s

        # Points the tables and boxes at another stream while the block runs.
        # They keep the screen's width.
        #
        # @param io [IO, nil] nil to leave them on the screen
        def writing_to(io)
          return yield if io.nil?

          screen = out
          @screen = screen
          @out = io
          @pastel = nil
          yield
        ensure
          if io
            @out = screen
            @screen = nil
            @pastel = nil
          end
        end

        def percent(value) = value.nil? ? "-" : format("%.1f%%", value * 100)

        def dollars(value) = format("$%.4f", value.to_f)

        def primary = scorer.primary

        # The best value: the cheapest entry within {VALUE_MARGIN} of the best
        # primary metric. Entries with errors, or no score, do not compete. A
        # plain score-per-dollar ratio would crown whatever is nearly free,
        # however wrong it is.
        #
        # @param entries [Array<Array(Float, Float, Integer)>] primary metric, cost, errors
        # @return [Integer, nil] the winner's index
        def best_value(entries)
          eligible = entries.each_index.select { entries[it][0] && entries[it][2].zero? }
          return nil if eligible.empty?

          floor = eligible.map { entries[it][0] }.max - VALUE_MARGIN
          eligible.select { entries[it][0] >= floor - 1e-9 }.min_by { entries[it][1] }
        end

        def value_line(label, value, cost)
          out.puts "best value#{label}: #{format("%.1f%%", value * 100)} at #{dollars(cost)}, " \
                   "the cheapest within #{(VALUE_MARGIN * 100).round} points of the best #{primary.name}"
        end

        def contender_label(summary) = "#{summary.model.id} effort=#{summary.model.effort || "default"}"

        def temperature_cell(summary) = summary.model.temperature.nil? ? "default" : summary.model.temperature

        # One table per case variant, over every dataset, of tokens, cost and the
        # mean primary metric per contender, so the variants can be compared.
        #
        # @return [Proc, nil] prints the conclusions over every dataset, for after
        #   everything else; nil over a single dataset
        def totals(summaries)
          variants = summaries.flat_map { |summary| summary.results.map { it.case.variant } }.uniq.sort
          several_datasets = summaries.map(&:dataset).uniq.size > 1
          if several_datasets || variants.size > 1
            variants.each do |variant|
              out.puts "[#{variant}]"
              contender_table(contender_groups(summaries.map { it.for_variant(variant, metrics) }))
            end
          end
          return unless several_datasets

          groups = contender_groups(summaries)
          best = best_contender(groups)
          winner = groups.find { it[:weighted] && it[:errors].zero? }
          lambda do
            value_line(" overall (#{contender_label(groups[best][:first])})", groups[best][:value], groups[best][:usage].cost_usd) if best
            weighted_line(" overall (#{contender_label(winner[:first])})", winner[:weighted]) if @weighted && winner
          end
        end

        # Each contender's numbers over the given experiments, best first.
        #
        # @param summaries [Array<Experiment::Summary>]
        # @return [Array<Hash>]
        def contender_groups(summaries)
          groups = summaries.group_by { [it.model.key, it.model.effort, it.model.temperature] }.values.map do |group|
            values = group.filter_map { it.mean(primary) }
            { first: group.first, errors: group.sum { it.errors.size },
              value: values.size == group.size ? values.sum / values.size : nil,
              usage: group.map(&:usage).reduce(Usage.zero, :+),
              row:   overall_row(group) }
          end
          weighted = weighted_by(groups.map { it[:row] })
          groups.each_with_index { |g, index| g[:weighted] = weighted[index] }
          groups.sort_by { -((@weighted ? it[:weighted] : it[:value]) || -1) }
        end

        # @param groups [Array<Hash>] from {#contender_groups}
        # @return [Integer, nil] the index of the best value
        def best_contender(groups) = best_value(groups.map { [it[:value], it[:usage].cost_usd, it[:errors]] })

        # @param groups [Array<Hash>] from {#contender_groups}
        # @return [void]
        def contender_table(groups)
          rows = groups.map do |g|
            s = g[:first]
            [s.model.id, s.model.effort || "default", temperature_cell(s), *(percent(g[:weighted]) if @weighted), percent(g[:value]),
             g[:errors], g[:usage].input_tokens, g[:usage].output_tokens, dollars(g[:usage].cost_usd)]
          end
          table(rows,
            header:    ["model", "effort", "temp", *("wscore" if @weighted), primary.name, "errors", "tok_in", "tok_out", "cost"],
            highlight: [best_contender(groups)].compact,
            fill:      0)
        end

        # What {WeightedScore} reads from one experiment.
        #
        # @param summary [Experiment::Summary]
        # @return [Hash{String => Numeric, nil}]
        def weighted_row(summary)
          metrics.to_h { [it.name, summary.mean(it)] }.merge(
            "score"  => summary.score,
            "errors" => summary.errors.size,
            "time"   => summary.duration,
            "cost"   => summary.usage.cost_usd.to_f
          )
        end

        # One contender over every dataset: errors and magnitudes add up, the rest average.
        #
        # @param group [Array<Experiment::Summary>]
        # @return [Hash{String => Numeric, nil}]
        def overall_row(group)
          rows = group.map { weighted_row(it) }
          rows.first.keys.to_h do |name|
            values = rows.map { it[name] }
            total = values.sum(&:to_f)
            next [name, nil] if values.any?(&:nil?)

            [name, ["errors", *WeightedScore::MAGNITUDES].include?(name) ? total : total / values.size]
          end
        end

        # @param rows [Array<Hash>]
        # @return [Array<Float, nil>] nils when the file sets no weights
        def weighted_by(rows) = @weighted ? @weighted.call(rows) : Array.new(rows.size)

        # @param summaries [Array<Experiment::Summary>]
        # @return [Hash{Experiment::Summary => Float, nil}] by identity, each compared within its dataset
        def weighted_scores(summaries)
          summaries.group_by(&:dataset).values.each_with_object({}.compare_by_identity) do |group, scores|
            group.zip(weighted_by(group.map { weighted_row(it) })).each { |summary, value| scores[summary] = value }
          end
        end

        def weighted_line(label, value)
          out.puts "best wscore#{label}: #{format("%.1f%%", value * 100)}, by the weights in weighted_score"
        end

        # Every experiment by its mean score, best first, with its cost and its
        # Braintrust page. URLs are never wrapped, so they stay clickable.
        def scores(summaries)
          weighted = weighted_scores(summaries)
          rows = summaries.sort_by { -(it.score || -1) }.map do |s|
            [s.model.id, s.model.effort || "default", s.dataset, percent(s.score), *(percent(weighted[s]) if @weighted), dollars(s.usage.cost_usd), s.permalink || "-"]
          end
          table(rows, header: ["model", "effort", "dataset", "score", *("wscore" if @weighted), "cost", "url"], fill: 0)
        end

        # The best value in each dataset's block of the leaderboard.
        #
        # @param ranked [Array<Experiment::Summary>]
        # @return [Array<Integer>] indices into ranked
        def best_per_dataset(ranked)
          ranked.each_index.group_by { ranked[it].dataset }.values.filter_map do |indices|
            winner = best_value(indices.map { [ranked[it].mean(primary), ranked[it].usage.cost_usd, ranked[it].errors.size] })
            winner && indices[winner]
          end
        end

        # One line per dataset's winner, each column aligned, with its model last in
        # the color of its progress bars.
        #
        # @param title [String]
        # @param summaries [Array<Experiment::Summary>]
        # @param label [String] the name of what the block reads
        # @yieldparam summary [Experiment::Summary]
        # @yieldreturn [Float]
        def winners(title, summaries, label)
          return if summaries.empty?

          rows = summaries.map { ["[#{it.dataset}]", "effort=#{it.model.effort || "default"}", "#{label}=#{percent(yield(it))}", dollars(it.usage.cost_usd)] }
          widths = rows.transpose.map { |column| column.map(&:length).max }
          out.puts title
          rows.zip(summaries).each do |(dataset, effort, value, cost), summary|
            model = summary.model.id
            out.puts "  #{dataset.ljust(widths[0])}  #{effort.ljust(widths[1])}  #{value.rjust(widths[2])}  #{cost.rjust(widths[3])}  " \
                     "#{pastel.public_send(model_colors[model], model)}"
          end
        end

        def model_colors = @model_colors ||= ModelColors.new

        # One row per experiment, best primary metric first, or best wscore when the
        # file sets weights; the glossary; the totals per case variant; with
        # scores, every experiment by score; and, last, the winners.
        def leaderboard(summaries, scores: false)
          weighted = weighted_scores(summaries)
          ranked = summaries.sort_by { [it.dataset, -((@weighted ? weighted[it] : it.mean(primary)) || -1)] }
          rows = ranked.map do |s|
            [s.dataset, s.model.id, s.model.effort || "default", temperature_cell(s),
             *(percent(weighted[s]) if @weighted),
             *metrics.map { percent(s.mean(it)) },
             s.errors.size, format("%.1fs", s.duration), s.usage.input_tokens, s.usage.output_tokens, dollars(s.usage.cost_usd)]
          end
          best = best_per_dataset(ranked)
          table(rows,
            header:    ["dataset", "model", "effort", "temp", *("wscore" if @weighted), *metrics.map(&:name),
                        "errors", "time", "tok_in", "tok_out", "cost"],
            highlight: best)
          table(glossary, header: %w[Term Description], fill: 1, wrap: true)
          overall = totals(summaries)
          scores(summaries) if scores
          winners("Best value: the cheapest within #{(VALUE_MARGIN * 100).round} points of the best #{primary.name}",
            best.map { ranked[it] },
            primary.name) { it.mean(primary) }
          if @weighted
            leaders = ranked.group_by(&:dataset).values.filter_map { |group| group.find { weighted[it] && it.errors.empty? } }
            winners("Best wscore: by the weights in weighted_score", leaders, "wscore") { weighted[it] }
          end
          overall&.call
        end

        # @return [Array<Array(String, String)>] the metrics' descriptions, then the gem's columns, less any a metric took the name of
        def glossary
          described = metrics.map { [it.name, it.description.to_s.empty? ? "(no description)" : it.description] } + GLOSSARY.reject { |term, _| metrics.any? { it.name == term } }.to_a
          @weighted ? [["wscore", @weighted.description], *described] : described
        end
      end
    end
  end
end
