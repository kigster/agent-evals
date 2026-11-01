# frozen_string_literal: true

module LLM
  module Evals
    module CLI
      # Turns a saved JSON run into a standalone HTML report without calling a model.
      class Render < Command
        desc "Render a saved JSON eval report as standalone HTML"

        argument :input, required: true, desc: "JSON report file produced by run or compare --format json"
        option :output, aliases: ["-o"], desc: "HTML output path (default: a timestamped file under log/)"

        def call(input:, output: nil, **)
          source = File.read(input)
          path = if output == "-"
                   nil
                 elsif output.nil? || output.empty?
                   invocation.report_path("").sub(/\.log\z/, ".html")
                 else
                   invocation.report_path(output)
                 end
          pipeline = LLM::Evals::Render::Reports::Pipeline.new(providers: configuration.providers,
            runtime: configuration.runtime,
            destination: File.dirname(path || input),
            temp_dir: File.dirname(input),
            project: configuration.name)
          document = pipeline.write_html(json: source, path:)
          out.write(document) unless path
          status_box(:success, "HTML report written to #{relative(path)}", stream: err) if path
        end

        private

        def invocation = ui.send(:invocation)

        def relative(path) = Pathname(path).relative_path_from(Dir.pwd).to_s
      end
    end
  end
end
