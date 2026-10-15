# frozen_string_literal: true

module Agent
  module Evals
    module CLI
      # Several models at one setting, side by side: one experiment each,
      # and only the leaderboard.
      class Compare < ModelCommand
        desc "Run every case against several models and print a leaderboard"

        option :concurrency, default: "0", desc: "Models running at once; 0 runs them all together"

        example [
          "                                     # everything .agent-eval.config.yml lists",
          "-m anthropic/claude-haiku-5.5,openai/gpt-4o-mini -t 0",
          "-e low -c clear --concurrency 2",
          "-n                                   # show the matrix, spend nothing"
        ]

        def call(models:, dataset:, dry_run:, concurrency:, **options)
          config = lineup(options)
          contenders = contenders(config, models, options)
          datasets = datasets(dataset)
          return matrix(datasets, contenders) if dry_run

          setup!(contenders, options)
          runs = datasets.flat_map { |name| contenders.map { experiment(it, config, options, dataset: name) } }
          report(execute(runs, concurrency: Integer(concurrency)), output: options[:output], open: options[:open])
        end
      end
    end
  end
end
