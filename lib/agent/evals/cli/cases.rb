# frozen_string_literal: true

module Agent
  module Evals
    module CLI
      # The cases, without calling anything.
      class Cases < Command
        desc "List the eval cases in every dataset"

        option :dataset, type: :array, aliases: ["-d"], default: [], desc: "Only these datasets, comma-separated"

        def call(dataset: [], **)
          scorer = configuration.scorer
          names = dataset.flat_map { it.split(",") }
          names = discovery.datasets if names.empty?
          rows = names.flat_map { discovery.cases(dataset: it) }.map do |kase|
            [kase.dataset, kase.id, kase.difficulty, scorer.summary(kase) || summary(kase), kase.input.split.size]
          end
          raise Error, "no cases found under #{discovery.root} with #{discovery.glob}" if rows.empty?

          table(rows, header: %w[dataset case difficulty expected words])
        end

        private

        # The generic cell when the scorer has nothing to say: how many fields
        # the expected answer holds, or what kind of thing it is.
        def summary(kase)
          case kase.expected
          when Hash then "#{kase.expected.size} fields"
          when Array then "#{kase.expected.size} items"
          when nil then "-"
          else kase.expected.class.name.downcase
          end
        end
      end
    end
  end
end
