# frozen_string_literal: true

module Agent
  module Evals
    module CLI
      # Turns a saved JSON run into a standalone HTML report without calling a model.
      class Render < Command
        desc "Render a saved JSON eval report as standalone HTML"

        argument :input, required: true, desc: "JSON report file produced by run or compare --format json"
        option :output, aliases: ["-o"], desc: "HTML output path (default: a timestamped file under log/)"

        def call(input:, output: nil, **)
          source = File.read(input)
          report = ReportJson.load(source, providers: configuration.providers)
          path = if output == "-"
                   nil
                 elsif output.nil? || output.empty?
                   invocation.report_path("").sub(/\.log\z/, ".html")
                 else
                   invocation.report_path(output)
                 end
          document = HtmlReport.render(report.summaries, metrics: report.metrics, weighted_score: report.weighted_score)
          path ? File.write(path, document) : out.write(document)
          status_box(:success, "HTML report written to #{relative(path)}", stream: err) if path
        end

        private

        def invocation = ui.send(:invocation)

        def relative(path) = Pathname(path).relative_path_from(Dir.pwd).to_s
      end
    end
  end
end
