# frozen_string_literal: true

require "io/console"
require "pastel"
require "tty-box"
require "tty-table"

module Agent
  module Evals
    module CLI
      # What every command inherits: the ui helpers, and the flags they all share.
      class Command < Dry::CLI::Command
        include Dry::CLI::UI

        # A cell that reads as a number: 42, 1,200, 97.1%, 3.5s, $0.0042.
        NUMBER = /\A-?\$?\d[\d,]*(?:\.\d+)?[%s]?\z/

        # Cells that stand in for a number without being one; they do not stop
        # a column from right-aligning.
        PLACEHOLDERS = ["", "-", "default"].freeze

        # The width assumed when the output is not a terminal.
        DEFAULT_WIDTH = 120

        # The narrowest a wrapped column gets, however full the screen.
        MIN_WRAP = 30

        # Each status box's title and colors.
        STATUS = {
          info:    { title: " Info ", fg: :bright_white, bg: :blue },
          success: { title: " Success ", fg: :black, bg: :green },
          warning: { title: " Warning ", fg: :black, bg: :yellow },
          error:   { title: " Error ", fg: :bright_white, bg: :red }
        }.freeze

        def self.inherited(subclass)
          super
          subclass.option :verbose, type: :boolean, default: false, aliases: ["-v"], desc: "Print the full backtrace on failure"
        end

        private

        # @return [Configuration] the suite, which must be loaded
        def configuration = Agent::Evals.configuration.require_suite!

        # @return [Discovery]
        def discovery = configuration.discovery

        # ui.table, as wide as the terminal (and so as the info and warning
        # boxes), with every all-numeric column right-aligned and a line between
        # rows once any cell spans several. dry-cli-ui does none of that, so this
        # renders through tty-table, as it does.
        #
        # The fill column takes whatever width the others leave. With wrap, its
        # text is word-wrapped to fit; without, it is only ever widened, so an
        # id is never broken and a table too wide for the screen stays so.
        #
        # @param rows [Array<Array<#to_s>>]
        # @param header [Array<String>]
        # @param highlight [Array<Integer>] rows drawn in bold yellow (when color is on)
        # @param fill [Integer] the column that absorbs the spare width
        # @param wrap [Boolean] word-wrap the fill column to fit
        # @return [void]
        def table(rows, header:, highlight: [], fill: 1, wrap: false)
          return if rows.empty?

          cells = rows.map { |row| row.map(&:to_s) }
          widths = column_widths([header] + cells)
          spare = terminal_width - (widths.sum - widths[fill]) - ((3 * widths.size) + 1)
          if wrap
            widths[fill] = [spare, MIN_WRAP].max
            cells.each { it[fill] = wrap(it[fill], widths[fill]) }
          else
            widths[fill] = [spare, widths[fill]].max
          end
          alignments = header.each_index.map do |index|
            column = cells.map { it[index] }.reject { PLACEHOLDERS.include?(it) }
            !column.empty? && column.all? { NUMBER.match?(it) } ? :right : :left
          end
          multiline = cells.flatten.any? { it.include?("\n") }
          cells = cells.each_with_index.map { |row, index| highlight.include?(index) ? row.map { pastel.bold.yellow(it) } : row }
          rendered = TTY::Table.new(header: header.map { pastel.bold(it) }, rows: cells).render(
            :unicode,
            padding:       [0, 1],
            width:         Dry::CLI::UI::Widgets::Table::UNLIMITED,
            alignments:    alignments,
            multiline:     multiline,
            column_widths: widths
          ) { |renderer| renderer.border.separator = :each_row if multiline }
          out.puts rendered
        end

        # @return [Array<Integer>] each column's widest line
        def column_widths(rows)
          rows.transpose.map { |column| column.flat_map { it.to_s.split("\n") }.map(&:length).max.to_i }
        end

        # ui.info, ui.success, ui.warn and ui.error, painted on their color
        # across the full width of the terminal. dry-cli-ui colors only a box's
        # title, so this draws the box with tty-box, which it uses too. Without
        # color it is a plain framed box.
        #
        # @param level [Symbol] a key of {STATUS}
        # @param text [String]
        # @param stream [IO] out by default; warnings and errors go to err
        # @return [void]
        def status_box(level, text, stream: out)
          look = STATUS.fetch(level)
          colored = color?(stream)
          style = colored ? { fg: look[:fg], bg: look[:bg], border: { fg: look[:fg], bg: look[:bg] } } : {}
          # tty-box drops a word wider than the box, such as a long path; cut it first
          stream.puts TTY::Box.frame(wrap(text, terminal_width - 4),
            width:        terminal_width,
            padding:      [0, 1],
            title:        { top_left: look[:title] },
            style:        style,
            enable_color: colored)
        end

        # A report written with -o is in color, as dry-cli-ui writes its own.
        #
        # @param stream [IO]
        # @return [Boolean] whether the stream takes color
        def color?(stream = out)
          (stream.respond_to?(:color?) && stream.color?) || (stream.respond_to?(:tty?) && stream.tty? && !ENV.key?("NO_COLOR"))
        end

        def pastel = @pastel ||= Pastel.new(enabled: color?)

        # @return [Integer] columns available on this terminal; {DEFAULT_WIDTH} when it is not one.
        #   While writing to a report, the screen's.
        def terminal_width
          screen = @screen || out
          width = screen.respond_to?(:winsize) && screen.tty? ? screen.winsize[1] : 0
          width.positive? ? width : DEFAULT_WIDTH
        rescue SystemCallError
          DEFAULT_WIDTH
        end

        # Word-wraps text to a width, keeping its own line breaks. A word
        # longer than the width is cut.
        #
        # @param text [String]
        # @param width [Integer]
        # @return [String]
        def wrap(text, width)
          text.split("\n").flat_map { |line| line.scan(/\S.{0,#{width - 1}}(?=\s|\z)|\S{#{width}}/).map(&:strip) }.join("\n")
        end

        # @param only [Array<String>, nil] case prefixes from --case
        # @param dataset [String]
        # @return [Array<Case>]
        # @raise [Error] when nothing matches
        def cases_for(only, dataset:)
          list = discovery.cases(dataset: dataset, only: Array(only))
          raise Error, "no cases match #{Array(only).join(", ")} in #{dataset}" if list.empty?

          list
        end
      end
    end
  end
end
