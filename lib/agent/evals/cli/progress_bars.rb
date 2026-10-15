# frozen_string_literal: true

module Agent
  module Evals
    module CLI
      # dry-cli-ui's multi_progress, drawn differently:
      #
      # - a flat list, the jobs indented under the headline, with no tree;
      # - the headline's bar, which counts every case, in yellow;
      # - a finished job keeps its bar, full, with the time it took where the
      #   ETA was, instead of turning into a one-line summary;
      # - labels padded to at least {LABEL_WIDTH} columns;
      # - each frame overwrites the last line by line, inside a synchronized
      #   update, rather than clearing the screen below and drawing it again,
      #   which flickers with many rows.
      class ProgressBars < Dry::CLI::UI::Widgets::MultiProgress
        # The fewest columns a label is padded to.
        LABEL_WIDTH = 40

        # What each job's row starts with.
        INDENT = "  "

        # The headline's bar color.
        HEADLINE_COLOR = :yellow

        # Rows that have ended and drew a bar while they ran.
        ENDED = %i[done failed].freeze

        # Tells the terminal to show a frame only once all of it has arrived.
        # Terminals that do not know these ignore them.
        SYNC_START = "\e[?2026h"
        SYNC_END = "\e[?2026l"

        # @param console [Dry::CLI::UI::Console] the command's ui, whose stream, clock and settings it draws with
        def self.for(console) = new(console.send(:err), clock: console.send(:clock), config: console.send(:config))

        private

        def label_width = [LABEL_WIDTH, title.length, *jobs.map { it.label.length }].max + INDENT.length

        def rows
          width = label_width
          [headline(width), *visible.map { "#{INDENT}#{row(it, width - INDENT.length)}" }]
        end

        def redraw
          drawn = rows
          cursor = terminal.cursor
          up = @drawn.positive? ? cursor.up(@drawn) : ""
          lines = drawn.map { "\r#{it}#{cursor.clear_line_after}\n" }.join
          below = drawn.size < @drawn ? cursor.clear_screen_down : ""
          terminal.print("#{SYNC_START}#{up}#{lines}#{below}#{SYNC_END}")
          @drawn = drawn.size
        end

        def headline(width)
          return super unless live?

          finished = state != :running
          bar = full_meter(current, total, started, HEADLINE_COLOR, counts, (@seconds if finished))
          "#{glyph(state)} #{title.ljust(width)} #{bar}#{finished ? noted(headline_note) : stopping}"
        end

        def row(job, width)
          return super unless ENDED.include?(job.state) && !spinner?(job) && live?

          handle = job.handle
          bar = full_meter(handle.current, handle.total, job.started, handle.color, handle.counts, job.seconds.to_f)
          "#{glyph(job.state)} #{job.label.ljust(width)} #{bar}#{noted(note(job))}"
        end

        # {#meter}, with the time taken in place of the ETA once seconds are known.
        def full_meter(done, all, since, color, tally, seconds)
          return meter(done, all, since, color, tally) if seconds.nil?

          took = Dry::CLI::UI::Duration.format(seconds)
          Dry::CLI::UI::Widgets::Progress.meter(terminal.pastel,
            config,
            done:        done,
            all:         all,
            columns:     bar_columns,
            eta:         took,
            color:       color,
            counts:      tally,
            count_width: count_width).sub("ETA #{took}", "in #{took}")
        end
      end
    end
  end
end
