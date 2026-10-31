# frozen_string_literal: true

module Agent
  module Evals
    # One number from the leaderboard's columns, weighted as the lineup file
    # says, for a suite to state what matters most to it. A positive weight
    # means higher is better; a negative one, lower is better:
    #
    #   weighted_score:
    #     weights:
    #       score: 0.4
    #       hallucinated_rate: -0.2
    #       cost: -0.2
    #
    #   weighted_score = Σ(|weight| × goodness) / Σ|weight|
    #
    # Goodness runs from 0 to 1. Metrics are used as they are, or as 1 - value
    # under a negative weight. Each error halves the errors column's goodness, so
    # that a single one costs half its weight: a failed case has no scores, so
    # no other column notices it, and as a share of the cases it would barely
    # register. {MAGNITUDES}
    # are placed on a log scale between the lowest and highest in the group, so
    # that each doubling costs the same: on a linear scale, one model a hundred
    # times the price would squash all the others together. Where the whole
    # group is equal, each gets 1.
    #
    # Magnitudes are relative, so a weighted score compares within one group
    # only: another model in the lineup moves everyone's.
    class WeightedScore
      # Columns compared on a log scale.
      MAGNITUDES = %w[time cost].freeze

      # The gem's columns that can be weighted, beside the metrics. `temp` is a
      # setting, not a result, and tokens are already in the cost.
      COLUMNS = ["score", "errors", *MAGNITUDES].freeze

      # What each error multiplies the errors column's goodness by.
      ERROR_FACTOR = 0.5

      attr_reader :weights

      # @param weights [Hash{String => Numeric}]
      # @param metrics [Array<String>] the scorer's metric names
      # @raise [Error] on a weight that is not a number, an unknown column, or no weight at all
      def initialize(weights, metrics:)
        known = (metrics + COLUMNS).uniq
        unknown = weights.keys - known
        raise Error, "weighted_score: unknown columns #{unknown.join(", ")}; known: #{known.join(", ")}" if unknown.any?

        invalid = weights.reject { |_name, weight| weight.is_a?(Numeric) }.keys
        raise Error, "weighted_score: weights must be numbers: #{invalid.join(", ")}" if invalid.any?

        raise Error, "weighted_score: errors must have a negative weight, since fewer is better" if weights.fetch("errors", -1).positive?

        @weights = weights.reject { |_name, weight| weight.zero? }
        raise Error, "weighted_score: every weight is zero" if @weights.empty?
      end

      # A column no row has does not count. A row missing a column the others
      # have gets nil: it was not measured on everything they were.
      #
      # @param rows [Array<Hash{String => Numeric, nil}>] one per contender, compared with each other
      # @return [Array<Float, nil>] in the order given
      def call(rows)
        present = weights.select { |name, _weight| rows.any? { it[name] } }
        total = present.values.sum(&:abs)
        rows.map do |row|
          next if present.empty? || present.keys.any? { row[it].nil? }

          present.sum { |name, weight| weight.abs * goodness(name, row[name], weight, rows) } / total
        end
      end

      # @return [String] the formula, with this lineup's weights, for the glossary
      def description
        "Σ(|weight| × goodness) / Σ|weight|, from 0% to 100%, and higher is better. A negative weight means that column is better low. " \
          "Each error halves the errors column. " \
          "#{MAGNITUDES.join(", ")} are on a log scale within the group, so compare weighted_score within one table only. " \
          "Weights: #{weights.map { |name, weight| "#{name} #{weight}" }.join(", ")}."
      end

      private

      def goodness(name, value, weight, rows)
        return ERROR_FACTOR**value if name == "errors"

        position = MAGNITUDES.include?(name) ? position(value, rows.filter_map { it[name] }) : value.to_f
        return 1.0 if position.nil?

        weight.negative? ? 1.0 - position : position
      end

      # A zero has no logarithm, so it stands at half the lowest above zero.
      #
      # @return [Float, nil] from 0 at the lowest to 1 at the highest; nil when all are equal
      def position(value, values)
        highest = values.max
        return nil if values.min == highest

        lowest = values.select(&:positive?).min
        lowest /= 2.0 if values.any?(&:zero?)
        (Math.log([value, lowest].max) - Math.log(lowest)) / (Math.log(highest) - Math.log(lowest))
      end
    end
  end
end
