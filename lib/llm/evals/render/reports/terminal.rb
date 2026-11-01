# frozen_string_literal: true

module LLM
  module Evals
    module Render
      module Reports
        # Presents a decoded report in the terminal and optionally writes the
        # detailed view to a report file.
        class Terminal
          # @param invocation [Dry::CLI::UI::Invocation]
          # @param writing_to [#call] redirects the command's table helpers
          # @param leaderboard [#call] draws the summary leaderboard
          def initialize(invocation:, writing_to:, leaderboard:)
            @invocation = invocation
            @writing_to = writing_to
            @leaderboard = leaderboard
          end

          # @param summaries [Array<Experiment::Summary>]
          # @param output [String, nil]
          # @param scores [Boolean]
          # @param totals_mode [String] overall, variant or both
          # @yield [summaries] draw the per-case detail
          # @return [String, nil] report file path
          def call(summaries:, output:, scores:, totals_mode:, &details)
            path = @invocation.report_path(output)
            if path
              File.open(path, "w") do |file|
                report = Dry::CLI::UI::Report.new(file)
                @writing_to.call(report) do
                  details&.call(summaries)
                  @leaderboard.call(summaries, scores:, totals_mode:)
                end
                report.puts "Closed at #{Time.now.strftime("%Y-%m-%d %H:%M:%S %z")}"
              end
            else
              details&.call(summaries)
            end
            @leaderboard.call(summaries, scores:, totals_mode:)
            path
          end
        end
      end
    end
  end
end
