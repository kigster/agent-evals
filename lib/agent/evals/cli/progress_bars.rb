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
      # - on a screen too short for every job, a finished row stays for
      #   {LINGER} seconds, since a short job would otherwise leave the screen
      #   before anyone saw it full: at two cases, its last frame is 50%;
      # - labels padded to at least {LABEL_WIDTH} columns, in the columns
      #   {.labels} lays out, each model in a bright color of its own for the
      #   whole run, chosen at random;
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

        # Seconds a finished row stays on a screen too short for every job,
        # at most; see {#visible}.
        LINGER = 1.5

        # Tells the terminal to show a frame only once all of it has arrived.
        # Terminals that do not know these ignore them.
        SYNC_START = "\e[?2026h"
        SYNC_END = "\e[?2026l"

        # Stands between a label's fixed columns and its model.
        MODEL_SEPARATOR = " | "

        # What a model can be drawn in. More models than these share them.
        MODEL_COLORS = %i[bright_red bright_green bright_yellow bright_blue bright_magenta bright_cyan bright_white].freeze

        # @param console [Dry::CLI::UI::Console] the command's ui, whose stream, clock and settings it draws with
        def self.for(console) = new(console.send(:err), clock: console.send(:clock), config: console.send(:config))

        # One label per experiment, the dataset and the settings each padded to
        # the widest of its column, so that every model starts in one column:
        # `[01-bookkeeping-cfo]  effort=low t=0.2 | moonshotai/kimi-k3`.
        #
        # @param runs [Array<Experiment>]
        # @return [Array<String>] in the order given
        def self.labels(runs)
          datasets = runs.map { "[#{it.dataset}]" }
          dataset_width = datasets.map(&:length).max
          settings_width = runs.map { it.model.label.length }.max
          runs.zip(datasets).map do |run, dataset|
            "#{dataset.ljust(dataset_width)}  #{run.model.label.ljust(settings_width)}#{MODEL_SEPARATOR}#{run.model.id}"
          end
        end

        private

        # @return [Integer]
        def label_width = [LABEL_WIDTH, title.length, *jobs.map { it.label.length }].max + INDENT.length

        def rows
          width = label_width
          [headline(width), *visible.map { "#{INDENT}#{painted(row(it, width - INDENT.length))}" }]
        end

        # @param text [String] a job's row, whose label holds the width it was padded to
        # @return [String] the row with its model in that model's color
        def painted(text)
          text.sub(/(?<=#{Regexp.escape(MODEL_SEPARATOR)})\S+/) { terminal.pastel.public_send(model_colors[it], it) }
        end

        # @return [Hash{String => Symbol}] each model's color, given when first drawn
        def model_colors
          @model_colors ||= begin
            palette = MODEL_COLORS.shuffle
            Hash.new { |colors, model| colors[model] = palette[colors.size % palette.size] }
          end
        end

        # The running jobs and those just finished, in the order declared. The
        # finished get at most half the rows, newest first: when jobs end
        # faster than rows linger, the oldest must not hold the screen.
        def visible
          return super unless crowded? && state == :running

          slots = [terminal.height - 2, 0].max
          now = clock.call
          finished = jobs.select { lingering?(it, now) }.max_by(slots / 2) { finished_at(it) }
          jobs & (finished + jobs.select { it.state == :running }.first(slots - finished.size))
        end

        def lingering?(job, now) = ENDED.include?(job.state) && now - finished_at(job) < LINGER

        def finished_at(job) = job.started + job.seconds

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
