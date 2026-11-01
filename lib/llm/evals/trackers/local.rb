# frozen_string_literal: true

require "fileutils"

module LLM
  module Evals
    module Trackers
      # Always on: every experiment's results and summary land in one JSON
      # file under `log/`, so a run is never lost to a closed terminal or a
      # remote tracker that was never configured.
      class Local < Tracker
        attr_reader :dir, :path

        # @param dir [String] where the files go; `log/llm-evals` at the repository root by default
        # @param context [Hash] see {Tracker#initialize}
        def initialize(dir: File.join(Dry::CLI::UI::Invocation.root(Dir.pwd), "log", "llm-evals"), **context)
          super(**context)
          @dir = dir
          @results = []
          @lock = Mutex.new
        end

        def describe = "local: #{dir}"

        def start(experiment)
          @started_at = Time.now
          @path = File.join(dir, "#{slug(experiment.name)}.#{@started_at.strftime("%Y-%m-%d.%H%M%S")}.json")
        end

        def record(result)
          @lock.synchronize { @results << result }
        end

        # @return [Hash] `url:` nil, `path:` the file written
        def finish(experiment, summary)
          FileUtils.mkdir_p(dir)
          File.write(path, JSON.pretty_generate(document(experiment, summary)))
          { url: nil, path: path }
        end

        private

        def slug(text) = text.gsub(/[^A-Za-z0-9.-]+/, "_").squeeze("_").delete_prefix("_").delete_suffix("_")

        def document(experiment, summary)
          {
            suite:      context[:suite],
            experiment: experiment.name,
            model:      experiment.model.id,
            provider:   experiment.model.provider.name,
            settings:   experiment.model.settings,
            dataset:    experiment.dataset,
            started_at: @started_at.iso8601,
            duration:   summary.duration,
            means:      summary.means,
            errors:     summary.errors,
            usage:      summary.usage.to_h,
            results:    @lock.synchronize { @results.sort_by { experiment.cases.index(it.case) }.map { row(it) } }
          }
        end

        def row(result)
          {
            case:        result.case.key,
            duration:    result.duration,
            error:       result.error,
            score:       result.score&.value,
            metrics:     result.score&.metrics,
            outcomes:    result.score&.outcomes,
            diagnostics: result.score&.diagnostics,
            reply_error: result.reply&.error,
            usage:       result.reply&.usage&.to_h
          }
        end
      end
    end
  end
end
