# frozen_string_literal: true

module Agent
  module Evals
    # One number a {Scorer} reports per case. `aggregate` is how the run
    # combines them (only :mean today), skipping nil, so a metric a case does
    # not apply to never drags its mean down with a free 0 or up with a free 1.
    # The `primary` metric ranks the leaderboard and picks the best value.
    class Metric < Data.define(:name, :description, :aggregate, :primary)
      AGGREGATES = %i[mean].freeze

      def initialize(name:, description: "", aggregate: :mean, primary: false)
        raise ArgumentError, "aggregate must be one of #{AGGREGATES.join(", ")}" unless AGGREGATES.include?(aggregate)

        super(name: name.to_s, description: description, aggregate: aggregate, primary: primary)
      end

      # @param values [Array<Float, nil>] one per case
      # @return [Float, nil] nil when no case reported the metric
      def combine(values)
        present = values.compact
        present.sum.fdiv(present.size) unless present.empty?
      end
    end
  end
end
