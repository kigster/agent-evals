# frozen_string_literal: true

require "json"
require "time"

module Agent
  module Evals
    module Render
      module Reports
        # A portable snapshot of completed runs, suitable for rendering later
        # without repeating model calls or depending on the original case files.
        class JSON
          FORMAT = "agent-evals-report"
          VERSION = 1
          Loaded = Data.define(:suite, :generated_at, :run_options, :summaries, :metrics, :weighted_score)
          SavedExperiment = Data.define(:model)

          # @param summaries [Array<Experiment::Summary>]
          # @param metrics [Array<Metric>]
          # @param weighted_score [WeightedScore, nil]
          # @return [String]
          def self.dump(summaries, metrics:, weighted_score: nil, run_options: {})
            document = {
              format:       FORMAT,
              version:      VERSION,
              suite:        Agent::Evals.configuration.name,
              generated_at: Time.now.iso8601,
              run_options:  json_value(run_options),
              metrics:      metrics.map { { name: it.name, description: it.description, aggregate: it.aggregate, primary: it.primary } },
              weights:      weighted_score&.weights,
              summaries:    summaries.map { summary(it) }
            }
            ::JSON.pretty_generate(document)
          end

          def self.json_value(value)
            case value
            when Hash then value.to_h { |key, item| [key.to_s, json_value(item)] }
            when Array then value.map { json_value(it) }
            when Symbol then value.to_s
            else value
            end
          end
          private_class_method :json_value

          # @param source [String] report JSON, not a path
          # @param providers [Providers::Registry]
          # @return [Loaded]
          # @raise [Error] for an unknown format/version or provider
          def self.decode(source, providers:)
            document = ::JSON.parse(source)
            unless document["format"] == FORMAT && document["version"] == VERSION
              raise Error, "unsupported report format version (expected #{FORMAT} v#{VERSION})"
            end

            metrics = document.fetch("metrics").map do |metric|
              Metric.new(name: metric.fetch("name"),
                description: metric.fetch("description", ""),
                aggregate: metric.fetch("aggregate", "mean").to_sym,
                primary: metric.fetch("primary", false))
            end
            weights = document["weights"]
            weighted_score = WeightedScore.new(weights, metrics: metrics.map(&:name)) if weights && !weights.empty?
            Loaded.new(suite: document.fetch("suite", "agent-evals"),
              generated_at: document["generated_at"],
              run_options: document.fetch("run_options", {}),
              summaries: document.fetch("summaries").map { summary_from(it, providers) },
              metrics:,
              weighted_score:)
          rescue ::JSON::ParserError => e
            raise Error, "invalid report JSON: #{e.message}"
          end

          def self.load(source, providers:) = decode(source, providers:)

          def self.summary(summary)
            {
              model:     { id: summary.model.id, provider: summary.model.provider.name, settings: summary.model.settings },
              dataset:   summary.dataset,
              name:      summary.name,
              means:     summary.means,
              errors:    summary.errors,
              duration:  summary.duration,
              permalink: summary.permalink,
              usage:     summary.usage.to_h,
              results:   summary.results.map { result(it) }
            }
          end
          private_class_method :summary

          def self.result(result)
            {
              case:     {
                id:       result.case.id,
                dataset:  result.case.dataset,
                variant:  result.case.variant,
                input:    result.case.input,
                expected: result.case.expected,
                metadata: result.case.metadata
              },
              reply:    result.reply && {
                output:   result.reply.output,
                raw:      result.reply.raw,
                usage:    result.reply.usage.to_h,
                error:    result.reply.error,
                metadata: result.reply.metadata
              },
              score:    result.score && {
                value:       result.score.value,
                metrics:     result.score.metrics,
                outcomes:    result.score.outcomes,
                diagnostics: result.score.diagnostics
              },
              duration: result.duration,
              error:    result.error
            }
          end
          private_class_method :result

          def self.summary_from(data, providers)
            model_data = data.fetch("model")
            provider = providers.find { it.name == model_data.fetch("provider") }
            raise Error, "report uses unknown provider #{model_data.fetch("provider").inspect}" unless provider

            model = Model.new(id: model_data.fetch("id"), provider:, settings: model_data.fetch("settings", {}))
            placeholder_cases = data.fetch("results").map do |result_data|
              case_data = result_data.fetch("case")
              kase = Case.new(id: case_data.fetch("id"),
                dataset: case_data.fetch("dataset"),
                variant: case_data.fetch("variant"),
                input: case_data.fetch("input"),
                expected: case_data["expected"],
                path: "",
                metadata: (case_data["metadata"] || {}).transform_keys(&:to_sym))
              [result_data, kase]
            end
            experiment = SavedExperiment.new(model:)
            results = placeholder_cases.map do |result_data, kase|
              reply_data = result_data["reply"]
              reply = if reply_data
                        Reply.new(output: reply_data["output"],
                          raw: reply_data["raw"],
                          usage: reply_data["usage"],
                          error: reply_data["error"],
                          metadata: reply_data["metadata"] || {})
                      end
              score_data = result_data["score"]
              if score_data
                score = Score.new(value: score_data.fetch("value"),
                  metrics: score_data["metrics"] || {},
                  outcomes: score_data["outcomes"] || {},
                  diagnostics: score_data["diagnostics"] || {})
              end
              RunResult.new(experiment:, case: kase, reply:, score:, duration: result_data.fetch("duration", 0.0), error: result_data["error"])
            end

            Experiment::Summary.new(model:,
              dataset: data.fetch("dataset"),
              name: data.fetch("name"),
              means: data.fetch("means"),
              results:,
              errors: data.fetch("errors", []),
              duration: data.fetch("duration", 0.0),
              permalink: data["permalink"],
              usage: Usage.from(data["usage"]))
          end
          private_class_method :summary_from
        end
      end
    end
  end
end
