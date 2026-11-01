# frozen_string_literal: true

module LLM
  module Evals
    module CLI
      # One experiment per model and dataset, each with a per-case breakdown.
      # Without -m, every model .llm-evals.config.yml lists. {Compare} runs the same
      # experiments and prints only the leaderboard.
      class Run < ModelCommand
        desc "Run every case against a model, or every model in .llm-evals.config.yml, with a per-case breakdown"

        example [
          "-m anthropic/claude-haiku-5.5",
          "-m openai/gpt-4.1-mini -t 0 -c clear/00        # one variant's first cases",
          "-m google/gemini-2.5-flash -e high --local      # score without Braintrust",
          "-d colors,animals -o                           # both datasets; the breakdowns go to log/",
          "-n                                             # show what would run, call nothing"
        ]

        def call(models:, dataset:, dry_run:, **options)
          config = lineup(options)
          weigh(config)
          contenders = contenders(config, models, options)
          datasets = datasets(dataset)
          return matrix(datasets, contenders) if dry_run

          setup!(contenders, options)
          runs = datasets.flat_map { |name| contenders.map { experiment(it, config, options, dataset: name) } }
          summaries = execute(runs, concurrency: concurrency(options))
          report(summaries,
            output:      options[:output],
            open:        options[:open],
            scores:      options[:scores],
            format:      options[:format],
            config:,
            options:,
            run_options: serialize_run_options(config:, contenders:, datasets:, runs:, models:, dataset:, options:)) do |display_summaries|
            display_summaries.each { breakdown(it, titled: display_summaries.size > 1) }
          end
        end

        private

        # One row per case: its score, and whatever the scorer diagnosed.
        def breakdown(summary, titled: false)
          status_box :info, summary.name if titled
          rows = summary.results.map do |result|
            [result.case.id, result.case.difficulty, result.score ? percent(result.score.value) : "-", diagnosis(result)]
          end
          table(rows, header: %w[case difficulty score diagnostics], fill: 3, wrap: true)
        end

        # The scorer's diagnostics, one per line, rendered without knowing
        # their shape: "field: value" for a Hash, each item for an Array.
        def diagnosis(result)
          return result.error if result.failed?

          result.score.diagnostics.map do |field, detail|
            case detail
            when Hash then "#{field}: #{detail.map { |k, v| "#{k}=#{v.inspect}" }.join(" ")}"
            when Array then "#{field}: #{detail.join(", ")}"
            else "#{field}: #{detail}"
            end
          end.join("\n")
        end
      end
    end
  end
end
