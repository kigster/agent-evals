# frozen_string_literal: true

require "fileutils"
require "pathname"
require "uri"

module LLM
  module Evals
    module CLI
      # The options shared by the commands that call a model. Settings resolve
      # flag first, then the config entry, then .llm-evals.config.yml's defaults.
      #
      # Every column that is not a metric is the gem's; the metric columns,
      # their glossary and the ranking come from the suite's {Scorer#metrics}.
      class ModelCommand < Command
        include Formatting

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
          subclass.option :config, aliases: ["-C"], desc: "The lineup file (default: the suite's .llm-evals.config.yml)"
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
          subclass.option :totals,
            values:  %w[overall variant both],
            default: "overall",
            desc:    "Group TUI totals by overall results, case variant or both"
          subclass.option :format,
            values: %w[tui html json],
            desc:   "Override the configured display: tui, html or json"
          subclass.option :display,
            values: %w[none tui browser],
            desc:   "Override results.display from the lineup"
          subclass.option :autosave,
            type:    :boolean,
            default: nil,
            desc:    "Save a JSON snapshot regardless of results.autosave"
          subclass.option :destination,
            desc: "Override results.destination"
          subclass.option :temp_dir,
            desc: "Override results.temp_dir"
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
        def metrics = @report_metrics || scorer.metrics

        # Reads the file's weights before anything is spent, so a bad one fails
        # the run rather than the report at its end.
        #
        # @return [WeightedScore, nil] nil when the file sets none
        # @raise [Error] on a bad weight
        def weigh(config)
          config.results # validate output settings before model calls start
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

        # Captures the parsed flags and the settings that actually reached the
        # experiments. The former preserves the invocation; the latter records
        # defaults and expanded case/model selections that were implicit.
        def serialize_run_options(config:, contenders:, datasets:, runs:, models:, dataset:, options:)
          {
            command:   invocation.action.to_s,
            cli:       { models:, dataset:, **options },
            effective: {
              project:       options[:project] || config.project || configuration.project || configuration.name,
              request_types: config.request_types.map(&:to_s),
              datasets:,
              cases:         runs.group_by(&:dataset).transform_values { |dataset_runs| dataset_runs.flat_map { it.cases.map(&:id) }.uniq },
              contenders:    contenders.map do |contender|
                settings = contender.settings
                { model: contender.model, provider: providers.for(contender).name, effort: settings[:effort],
                  temperature: settings[:temperature], max_tokens: settings[:max_tokens] }
              end,
              defaults:      config.defaults,
              parallelism:   Integer(options[:parallelism] || config.defaults["parallelism"]),
              concurrency:   concurrency(options),
              tracker:       options[:local] ? "none" : remote_tracker(config, options)&.tracker_name
            }
          }
        end

        # The local JSON log, always, then the one remote tracker if any,
        # each experiment getting instances of its own.
        #
        # @return [Array<Tracker>]
        def trackers_for(config, options)
          context = { suite:      configuration.name,
                      project:    options[:project] || config.project || configuration.project || configuration.name,
                      project_id: options[:project] ? nil : ENV["BRAINTRUST_PROJECT_ID"].to_s[/\S+/] }
          local = Trackers::Local.new(dir: File.join(Dry::CLI::UI::Invocation.root(Dir.pwd), "log", "llm-evals"), **context)
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
        # or every model .llm-evals.config.yml lists.
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
        # Saves or renders through {Render::Reports::Pipeline}; the configured
        # display and autosave policy are independent of model execution.
        #
        # @param summaries [Array<Experiment::Summary>]
        # @param output [String, nil] what -o was given: nil, "-", "" for the default file, or a path
        # @param open [Boolean]
        # @param scores [Boolean] also print every experiment by score
        # @param format [String] `tui`, `html` or `json`
        # @return [void]
        def report(summaries, config:, options:, run_options:, output:, open:, scores: false, format: nil, &details)
          results = effective_results(config, options)
          results[:display] = { "tui" => "tui", "none" => "none", "html" => "browser", "json" => "none" }.fetch(format, results[:display]) if format
          snapshot_options = run_options.merge(results:)
          pipeline = render_pipeline(results, run_options)

          if format == "html"
            json_path = if results[:autosave]
                          pipeline.save_json(summaries:, metrics:, weighted_score: @weighted, run_options: snapshot_options)
                        end
            json = if json_path
                     File.read(json_path)
                   else
                     pipeline.write_json(summaries:, metrics:, weighted_score: @weighted, run_options: snapshot_options, path: nil)
                   end
            if json_path
              status_box(:success, "JSON results written to #{relative(json_path)}", stream: err)
            end
            path = report_output_path(output, "html")
            document = pipeline.write_html(json:, path:)
            path ? status_box(:success, "HTML report written to #{relative(path)}", stream: err) : out.write(document)
            save_warnings
            if open && path
              url = URI::DEFAULT_PARSER.escape("file://#{path}")
              status_box(:warning, "could not open #{path}", stream: err) unless configuration.runtime.browse(url)
            end
            return
          end
          if format == "json"
            if output.nil? || output.empty?
              path = pipeline.save_json(summaries:, metrics:, weighted_score: @weighted, run_options: snapshot_options)
              status_box(:success, "JSON report written to #{relative(path)}", stream: err)
            else
              path = report_output_path(output, "json")
              document = pipeline.write_json(summaries:, metrics:, weighted_score: @weighted, run_options: snapshot_options, path:)
              path ? status_box(:success, "JSON report written to #{relative(path)}", stream: err) : out.write(document)
            end
            save_warnings
            return
          end

          result = pipeline.call(summaries:,
            metrics:,
            weighted_score: @weighted,
            run_options: snapshot_options,
            autosave: results[:autosave],
            display: results[:display],
            open:) do |report|
            @report_metrics = report.metrics
            @weighted = report.weighted_score
            terminal_report(report.summaries, output:, open:, scores:, totals_mode: options[:totals]) do |shown|
              details&.call(shown)
            end
          end
          if result.json_path
            status_box(:success, "JSON results written to #{relative(result.json_path)}", stream: err)
          end
          if result.html_path
            status_box(:success, "HTML report written to #{relative(result.html_path)}", stream: err)
            status_box(:warning, "could not open #{result.html_path}", stream: err) if open && !result.browser_opened
          end
          save_warnings unless results[:display] == "tui"
        end

        def terminal_report(summaries, output:, open:, scores:, totals_mode:, &details)
          terminal = LLM::Evals::Render::Reports::Terminal.new(invocation:, writing_to: method(:writing_to), leaderboard: method(:leaderboard))
          path = terminal.call(summaries:, output:, scores:, totals_mode:, &details)
          status_box(:info, "Report written to #{relative(path)}", stream: err) if path
          save_warnings
          url = summaries.max_by { it.score || -1 }&.permalink
          status_box(:warning, "could not open #{url}", stream: err) if open && url && !configuration.runtime.browse(url)
        end

        def effective_results(config, options)
          configured = config.results
          {
            autosave:    options[:autosave].nil? ? configured.autosave : options[:autosave],
            destination: File.expand_path(options[:destination] || configured.destination),
            temp_dir:    File.expand_path(options[:temp_dir] || configured.temp_dir),
            display:     options[:display] || configured.display_mode
          }
        end

        def render_pipeline(results, run_options)
          project = run_options.dig(:effective, :project) || run_options.dig("effective", "project") || configuration.name
          project = project.to_s.downcase.gsub(/[^a-z0-9]+/, "-").sub(/\A-/, "").sub(/-+\z/, "")
          LLM::Evals::Render::Reports::Pipeline.new(providers:,
            runtime: configuration.runtime,
            destination: results[:destination],
            temp_dir: results[:temp_dir],
            project:)
        end

        def report_output_path(output, extension)
          return nil if output == "-"

          path = if output.nil? || output.empty?
                   invocation.report_path("")
                 else
                   invocation.report_path(output)
                 end
          path.sub(/\.log\z/, ".#{extension}")
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

        def primary = metrics.find(&:primary) || scorer.primary

        def model_colors = @model_colors ||= ModelColors.new

        # Built per call: {#report} swaps the metrics and the weights for those of
        # the saved snapshot, and {#writing_to} swaps the stream, before this runs.
        def leaderboard(summaries, scores: false, totals_mode: "overall")
          standings = Standings.new(metrics:, primary:, weighted: @weighted)
          Leaderboard.new(standings:, table: method(:table), out:, pastel:, colors: model_colors)
                     .call(summaries, scores:, totals_mode:)
        end
      end
    end
  end
end
