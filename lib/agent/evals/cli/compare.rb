# frozen_string_literal: true

module Agent
  module Evals
    module CLI
      # Several models at one setting, side by side: one experiment each,
      # and only the leaderboard.
      class Compare < ModelCommand
        desc "Run every case against several models and print a leaderboard"

        example [
          "                                     # everything .agent-eval.config.yml lists",
          "-m anthropic/claude-haiku-5.5,openai/gpt-4o-mini -t 0",
          "-e low -c clear -j 2                 # two experiments at a time",
          "-n                                   # show the matrix, spend nothing"
        ]

        def call(models:, dataset:, dry_run:, **options)
          config = lineup(options)
          weigh(config)
          contenders = contenders(config, models, options)
          datasets = datasets(dataset)
          return matrix(datasets, contenders) if dry_run

          setup!(contenders, options)
          runs = datasets.flat_map { |name| contenders.map { experiment(it, config, options, dataset: name) } }
          report(execute(runs, concurrency: concurrency(options)), output: options[:output], open: options[:open], scores: options[:scores])
        end
      end
    end
  end
end
