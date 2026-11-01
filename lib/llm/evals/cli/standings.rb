# frozen_string_literal: true

module LLM
  module Evals
    module CLI
      # Who ranks where: the arithmetic behind {Leaderboard}, which prints nothing.
      class Standings
        # How close to the best primary metric a model must come to compete on
        # price: 0.02 is two percentage points.
        VALUE_MARGIN = 0.02

        attr_reader :metrics, :primary, :weighted

        # @param metrics [Array<Metric>]
        # @param primary [Metric] the metric the ranking reads
        # @param weighted [WeightedScore, nil] nil when the file sets no weights
        def initialize(metrics:, primary:, weighted: nil)
          @metrics = metrics
          @primary = primary
          @weighted = weighted
        end

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
          scores = weighted_by(groups.map { it[:row] })
          groups.each_with_index { |g, index| g[:weighted] = scores[index] }
          groups.sort_by { -((weighted ? it[:weighted] : it[:value]) || -1) }
        end

        # @param groups [Array<Hash>] from {#contender_groups}
        # @return [Integer, nil] the index of the best value
        def best_contender(groups) = best_value(groups.map { [it[:value], it[:usage].cost_usd, it[:errors]] })

        # @param summaries [Array<Experiment::Summary>]
        # @return [Hash{Experiment::Summary => Float, nil}] by identity, each compared within its dataset
        def weighted_scores(summaries)
          summaries.group_by(&:dataset).values.each_with_object({}.compare_by_identity) do |group, scores|
            group.zip(weighted_by(group.map { weighted_row(it) })).each { |summary, value| scores[summary] = value }
          end
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

        private

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
        def weighted_by(rows) = weighted ? weighted.call(rows) : Array.new(rows.size)
      end
    end
  end
end
