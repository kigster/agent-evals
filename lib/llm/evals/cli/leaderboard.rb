# frozen_string_literal: true

module LLM
  module Evals
    module CLI
      # The terminal summary of a run: one row per experiment, the glossary, the
      # selected totals view, and the winners. Every column that is not a metric
      # is the gem's; the metric columns, their glossary and the ranking come
      # from the suite's {Scorer#metrics}.
      class Leaderboard
        include Formatting

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
          "score"   => "The mean of each case's overall score, as the scorer computed it. With --scores, a table " \
                       "ranks every experiment by it."
        }.freeze

        # @param standings [Standings]
        # @param table [#call] draws rows, as {Command#table}
        # @param out [IO] where the lines between tables go
        # @param pastel [Pastel]
        # @param colors [ModelColors] shared with the progress bars, so a model keeps its color
        def initialize(standings:, table:, out:, pastel:, colors:)
          @standings = standings
          @table = table
          @out = out
          @pastel = pastel
          @colors = colors
        end

        # One row per experiment, best primary metric first, or best wscore when the
        # file sets weights; the glossary; the selected totals view; with
        # scores, every experiment by score; and, last, the winners.
        #
        # @param summaries [Array<Experiment::Summary>]
        # @param scores [Boolean] also print every experiment by score
        # @param totals_mode [String] `overall`, `variant` or `both`
        # @return [void]
        def call(summaries, scores: false, totals_mode: "overall")
          weights = standings.weighted_scores(summaries)
          ranked = summaries.sort_by { [it.dataset, -((weighted ? weights[it] : it.mean(primary)) || -1)] }
          rows = ranked.map do |s|
            [s.dataset, s.model.id, s.model.effort || "default", temperature_cell(s),
             *(percent(weights[s]) if weighted),
             *metrics.map { percent(s.mean(it)) },
             s.errors.size, format("%.1fs", s.duration), s.usage.input_tokens, s.usage.output_tokens, dollars(s.usage.cost_usd)]
          end
          best = standings.best_per_dataset(ranked)
          table.call(rows,
            header:    ["dataset", "model", "effort", "temp", *("wscore" if weighted), *metrics.map(&:name),
                        "errors", "time", "tok_in", "tok_out", "cost"],
            highlight: best)
          table.call(glossary, header: %w[Term Description], fill: 1, wrap: true)
          overall = totals(summaries, mode: totals_mode)
          score_table(summaries) if scores
          winners("Best value: the cheapest within #{(Standings::VALUE_MARGIN * 100).round} points of the best #{primary.name}",
            best.map { ranked[it] },
            primary.name) { it.mean(primary) }
          if weighted
            leaders = ranked.group_by(&:dataset).values.filter_map { |group| group.find { weights[it] && it.errors.empty? } }
            winners("Best wscore: by the weights in weighted_score", leaders, "wscore") { weights[it] }
          end
          overall&.call
        end

        # @return [Array<Array(String, String)>] the metrics' descriptions, then the gem's columns, less any a metric took the name of
        def glossary
          described = metrics.map { [it.name, it.description.to_s.empty? ? "(no description)" : it.description] } + GLOSSARY.reject { |term, _| metrics.any? { it.name == term } }.to_a
          weighted ? [["wscore", weighted.description], *described] : described
        end

        private

        attr_reader :standings, :table, :out, :pastel, :colors

        def metrics = standings.metrics

        def primary = standings.primary

        def weighted = standings.weighted

        def value_line(label, value, cost)
          out.puts "best value#{label}: #{format("%.1f%%", value * 100)} at #{dollars(cost)}, " \
                   "the cheapest within #{(Standings::VALUE_MARGIN * 100).round} points of the best #{primary.name}"
        end

        def weighted_line(label, value)
          out.puts "best wscore#{label}: #{format("%.1f%%", value * 100)}, by the weights in weighted_score"
        end

        def contender_label(summary) = "#{summary.model.id} effort=#{summary.model.effort || "default"}"

        def temperature_cell(summary) = summary.model.temperature.nil? ? "default" : summary.model.temperature

        # The selected totals view: one aggregate table, one per variant, or both.
        #
        # @return [Proc, nil] prints the conclusions over every dataset, for after
        #   everything else; nil over a single dataset
        def totals(summaries, mode: "overall")
          variants = summaries.flat_map { |summary| summary.results.map { it.case.variant } }.uniq.sort
          several_datasets = summaries.map(&:dataset).uniq.size > 1
          has_multiple_groups = several_datasets || variants.size > 1
          if has_multiple_groups && %w[overall both].include?(mode)
            out.puts "[all cases]"
            contender_table(standings.contender_groups(summaries))
          end
          if has_multiple_groups && %w[variant both].include?(mode)
            variants.each do |variant|
              out.puts "[#{variant}]"
              contender_table(standings.contender_groups(summaries.map { it.for_variant(variant, metrics) }))
            end
          end
          return unless several_datasets

          groups = standings.contender_groups(summaries)
          best = standings.best_contender(groups)
          winner = groups.find { it[:weighted] && it[:errors].zero? }
          lambda do
            value_line(" overall (#{contender_label(groups[best][:first])})", groups[best][:value], groups[best][:usage].cost_usd) if best
            weighted_line(" overall (#{contender_label(winner[:first])})", winner[:weighted]) if weighted && winner
          end
        end

        # @param groups [Array<Hash>] from {Standings#contender_groups}
        # @return [void]
        def contender_table(groups)
          rows = groups.map do |g|
            s = g[:first]
            [s.model.id, s.model.effort || "default", temperature_cell(s), *(percent(g[:weighted]) if weighted), percent(g[:value]),
             g[:errors], g[:usage].input_tokens, g[:usage].output_tokens, dollars(g[:usage].cost_usd)]
          end
          table.call(rows,
            header:    ["model", "effort", "temp", *("wscore" if weighted), primary.name, "errors", "tok_in", "tok_out", "cost"],
            highlight: [standings.best_contender(groups)].compact,
            fill:      0)
        end

        # Every experiment by its mean score, best first, with its cost and its
        # Braintrust page. URLs are never wrapped, so they stay clickable.
        def score_table(summaries)
          weights = standings.weighted_scores(summaries)
          rows = summaries.sort_by { -(it.score || -1) }.map do |s|
            [s.model.id, s.model.effort || "default", s.dataset, percent(s.score), *(percent(weights[s]) if weighted), dollars(s.usage.cost_usd), s.permalink || "-"]
          end
          table.call(rows, header: ["model", "effort", "dataset", "score", *("wscore" if weighted), "cost", "url"], fill: 0)
        end

        # One line per dataset's winner, each column aligned, with its model last in
        # the color of its progress bars.
        #
        # @param title [String]
        # @param summaries [Array<Experiment::Summary>]
        # @param label [String] the name of what the block reads
        # @yieldparam summary [Experiment::Summary]
        # @yieldreturn [Float]
        def winners(title, summaries, label)
          return if summaries.empty?

          rows = summaries.map { ["[#{it.dataset}]", "effort=#{it.model.effort || "default"}", "#{label}=#{percent(yield(it))}", dollars(it.usage.cost_usd)] }
          widths = rows.transpose.map { |column| column.map(&:length).max }
          out.puts title
          rows.zip(summaries).each do |(dataset, effort, value, cost), summary|
            model = summary.model.id
            out.puts "  #{dataset.ljust(widths[0])}  #{effort.ljust(widths[1])}  #{value.rjust(widths[2])}  #{cost.rjust(widths[3])}  " \
                     "#{pastel.public_send(colors[model], model)}"
          end
        end
      end
    end
  end
end
