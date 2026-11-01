# frozen_string_literal: true

require "fileutils"
require "tempfile"
require "uri"

module LLM
  module Evals
    module Render
      module Reports
        # Writes the canonical JSON snapshot and passes that snapshot to the
        # selected display. Temporary snapshots are removed after presentation.
        class Pipeline
          Result = Data.define(:json_path, :html_path, :css_path, :js_path, :browser_opened)

          # @param providers [Providers::Registry]
          # @param runtime [Runtime]
          # @param destination [String]
          # @param temp_dir [String]
          # @param project [String]
          def initialize(providers:, runtime:, destination:, temp_dir:, project:)
            @providers = providers
            @runtime = runtime
            @destination = destination
            @temp_dir = temp_dir
            @project = project
          end

          # @param summaries [Array<Experiment::Summary>]
          # @param metrics [Array<Metric>]
          # @param weighted_score [WeightedScore, nil]
          # @param run_options [Hash]
          # @param autosave [Boolean]
          # @param display [String]
          # @param open [Boolean]
          # @yield [report] display the decoded JSON in the terminal
          # @return [Result]
          def call(summaries:, metrics:, weighted_score:, run_options:, autosave:, display:, open:)
            return Result.new(nil, nil, nil, nil, nil) unless autosave || display != "none"

            stamp = timestamp
            json_path = autosave ? artifact_path(@destination, stamp, "json") : temporary_json_path
            write_json(summaries:, metrics:, weighted_score:, run_options:, path: json_path)
            return Result.new(json_path:, html_path: nil, css_path: nil, js_path: nil, browser_opened: nil) if display == "none"

            report = JSON.decode(File.read(json_path), providers: @providers)
            assets = case display
                     when "tui"
                       yield report if block_given?
                       [nil, nil, nil, nil]
                     when "browser"
                       render_browser(report, stamp:, open:)
                     else
                       [nil, nil, nil, nil]
                     end
            html_path, css_path, js_path, browser_opened = assets
            Result.new(json_path: autosave ? json_path : nil, html_path:, css_path:, js_path:, browser_opened:)
          ensure
            FileUtils.rm_f(json_path) if defined?(json_path) && json_path && !autosave
          end

          # @param summaries [Array<Experiment::Summary>]
          # @param metrics [Array<Metric>]
          # @param weighted_score [WeightedScore, nil]
          # @param run_options [Hash]
          # @param path [String, nil] nil returns JSON text to the caller
          # @return [String, nil] JSON text when no path was supplied
          def write_json(summaries:, metrics:, weighted_score:, run_options:, path:)
            document = JSON.dump(summaries, metrics:, weighted_score:, run_options:)
            if path
              FileUtils.mkdir_p(File.dirname(path))
              File.write(path, document)
              nil
            else
              document
            end
          end

          # @param json [String] serialized run results
          # @param path [String, nil] nil returns HTML text to the caller
          # @return [String, nil] HTML text when no path was supplied
          def write_html(json:, path:)
            report = JSON.decode(json, providers: @providers)
            document = HTML.render(report)
            if path
              FileUtils.mkdir_p(File.dirname(path))
              File.write(path, document)
              nil
            else
              document
            end
          end

          # Writes an explicitly requested JSON report under the configured
          # destination, using the same timestamped name as an autosaved result.
          #
          # @param summaries [Array<Experiment::Summary>]
          # @param metrics [Array<Metric>]
          # @param weighted_score [WeightedScore, nil]
          # @param run_options [Hash]
          # @return [String] the saved JSON path
          def save_json(summaries:, metrics:, weighted_score:, run_options:)
            path = artifact_path(@destination, timestamp, "json")
            write_json(summaries:, metrics:, weighted_score:, run_options:, path:)
            path
          end

          private

          def render_browser(report, stamp:, open:)
            FileUtils.mkdir_p(@destination)
            html_path = artifact_path(@destination, stamp, "html")
            css_path = artifact_path(@destination, stamp, "css")
            js_path = artifact_path(@destination, stamp, "js")
            File.write(css_path, File.read(File.join(HTML::TEMPLATE_DIRECTORY, "html_report.css")))
            File.write(js_path, File.read(File.join(HTML::TEMPLATE_DIRECTORY, "html_report.js")))
            html = HTML.render(report,
              stylesheet_path: File.basename(css_path),
              script_path:     File.basename(js_path))
            File.write(html_path, html)
            browser_opened = @runtime.browse(URI::DEFAULT_PARSER.escape("file://#{html_path}")) if open
            [html_path, css_path, js_path, browser_opened]
          end

          def artifact_path(directory, stamp, extension)
            File.join(directory, "#{@project}.results.#{stamp}.#{extension}")
          end

          def timestamp = Time.now.strftime("%Y-%m-%d.%H%M%S%6N")

          def temporary_json_path
            FileUtils.mkdir_p(@temp_dir)
            file = Tempfile.create(["#{@project}.results.", ".json"], @temp_dir)
            path = file.path
            file.close
            path
          end
        end
      end
    end
  end
end
