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
          "score"   => "The mean of each case's overall score, as the scorer computed it. The last table ranks " \
                       "every experiment by it."
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
          subclass.option :config, desc: "The lineup file (default: the suite's .agent-eval..agent-eval.config.yml)"
          subclass.option :effort, aliases: ["-e"], desc: "Reasoning effort: default, or one the provider accepts (overrides the config file)"
          subclass.option :temperature, aliases: ["-t"], desc: "Sampling temperature, or 'default' to send none (overrides the config file)"
          subclass.option :max_tokens, desc: "Output token cap, reasoning included (overrides the config file)"
          subclass.option :case,
            type:    :array,
            aliases: ["-c"],
            default: [],
            desc:    "Only these cases, by id prefix: -c clear or -c clear/003,vague/001"
          subclass.option :parallelism, aliases: ["-p"], desc: "Cases in flight at once, per model (default: the config's defaults.parallelism)"
          subclass.option :project,
            desc: "Braintrust project name; default is the BRAINTRUST_PROJECT_ID project, else the config file's project"
          subclass.option :open,
            type:    :boolean,
            default: true,
            desc:    "Open the best experiment in the browser when done (no effect with --local)"
          subclass.option :local,
            type:    :boolean,
            default: false,
            desc:    "Score locally without logging to Braintrust (still calls the models)"
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
            project:     options[:local] ? nil : (options[:project] || config.project || configuration.project || configuration.name),
            project_id:  options[:local] || options[:project] ? nil : ENV["BRAINTRUST_PROJECT_ID"].to_s[/\S+/],
            parallelism: Integer(options[:parallelism] || config.defaults["parallelism"]),
            suite:       configuration.name
          )
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
          found.each { providers.for(it.model) } # an unserved id fails here, before anything is spent
          admitted, refusals = providers.admit(found, request_types: config.request_types)
          refusals.each { warnings.record(it.to_s) }
          raise Error, "no admitted models: #{refusals.join("; ")}" if admitted.empty?

          admitted
        end

        # Env, hooks, provider clients, Braintrust, then the catalogs.
        def setup!(contenders, options)
          configuration.runtime.setup!(providers: providers.used_by(contenders), braintrust: !options[:local])
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
        def execute(runs, concurrency: 0)
          summaries = Array.new(runs.size)
          warnings.capture { bars(runs, summaries, concurrency) }
          summaries.compact.each { |s| s.errors.each { warnings.record("[#{s.name}] #{it}") } }
          summaries.compact
        end

        # @return [Warnings] what this command has held back from the screen
        def warnings = @warnings ||= Warnings.new

        def bars(runs, summaries, concurrency)
          ProgressBars.for(ui).run("Running #{runs.size} experiment#{"s" unless runs.size == 1}",
            concurrent: concurrency.zero? || concurrency) do |multi|
            runs.each_with_index do |run, index|
              multi.progress(run.name, total: run.cases.size) do |bar|
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
        # With -o, the block's output goes to the file alone, and the rest to
        # both, each drawn for its own stream. The file is in color and ends
        # with the time it was closed, as dry-cli-ui's own reports do.
        #
        # @param summaries [Array<Experiment::Summary>]
        # @param output [String, nil] what -o was given: nil, "-", "" for the default file, or a path
        # @param open [Boolean]
        # @return [void]
        def report(summaries, output:, open:, &details)
          path = invocation.report_path(output)
          if path
            File.open(path, "w") do |file|
              report = Dry::CLI::UI::Report.new(file)
              writing_to(report) do
                details&.call
                leaderboard(summaries)
              end
              report.puts "Closed at #{Time.now.strftime("%Y-%m-%d %H:%M:%S %z")}"
            end
          else
            details&.call
          end
          leaderboard(summaries)
          status_box(:info, "Report written to #{relative(path)}", stream: err) if path
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

        # Tokens, cost and the mean primary metric per contender, over every
        # dataset it ran.
        def totals(summaries)
          groups = summaries.group_by { [it.model.id, it.model.effort, it.model.temperature] }.values.map do |group|
            values = group.filter_map { it.mean(primary) }
            { first: group.first, errors: group.sum { it.errors.size },
              value: values.size == group.size ? values.sum / values.size : nil,
              usage: group.map(&:usage).reduce(Usage.zero, :+) }
          end
          groups.sort_by! { -(it[:value] || -1) }
          rows = groups.map do |g|
            s = g[:first]
            [s.model.id, s.model.effort || "default", temperature_cell(s), percent(g[:value]),
             g[:errors], g[:usage].input_tokens, g[:usage].output_tokens, dollars(g[:usage].cost_usd)]
          end
          best = best_value(groups.map { [it[:value], it[:usage].cost_usd, it[:errors]] })
          table(rows,
            header:    ["model", "effort", "temp", primary.name, "errors", "tok_in", "tok_out", "cost"],
            highlight: [best].compact,
            fill:      0)
          return unless best

          g = groups[best]
          value_line(" overall (#{contender_label(g[:first])})", g[:value], g[:usage].cost_usd)
        end

        # Every experiment by its mean score, best first, with its cost and its
        # Braintrust page. URLs are never wrapped, so they stay clickable.
        def scores(summaries)
          rows = summaries.sort_by { -(it.score || -1) }.map do |s|
            [s.model.id, s.model.effort || "default", s.dataset, percent(s.score), dollars(s.usage.cost_usd), s.permalink || "-"]
          end
          table(rows, header: %w[model effort dataset score cost braintrust_url], fill: 0)
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

        # One row per experiment, best primary metric first, with the best
        # value per dataset; the glossary; the totals, over several datasets;
        # and every experiment by score.
        def leaderboard(summaries)
          ranked = summaries.sort_by { [it.dataset, -(it.mean(primary) || -1)] }
          rows = ranked.map do |s|
            [s.dataset, s.model.id, s.model.effort || "default", temperature_cell(s),
             *metrics.map { percent(s.mean(it)) },
             s.errors.size, format("%.1fs", s.duration), s.usage.input_tokens, s.usage.output_tokens, dollars(s.usage.cost_usd)]
          end
          best = best_per_dataset(ranked)
          table(rows,
            header:    ["dataset", "model", "effort", "temp", *metrics.map(&:name), "errors", "time", "tok_in", "tok_out", "cost"],
            highlight: best)
          best.each do |index|
            s = ranked[index]
            value_line(" [#{s.dataset}] (#{contender_label(s)})", s.mean(primary), s.usage.cost_usd)
          end
          table(glossary, header: %w[Term Description], fill: 1, wrap: true)
          totals(summaries) if summaries.map(&:dataset).uniq.size > 1
          scores(summaries)
        end

        # @return [Array<Array(String, String)>] the metrics' descriptions, then the gem's columns
        def glossary
          metrics.map { [it.name, it.description.to_s.empty? ? "(no description)" : it.description] } + GLOSSARY.to_a
        end
      end
    end
  end
end
