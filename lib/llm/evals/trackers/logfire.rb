# frozen_string_literal: true

module LLM
  module Evals
    module Trackers
      # Pydantic Logfire, which has no Ruby gem of its own: it is an OTLP
      # backend for the standard OpenTelemetry Ruby SDK (pydantic.dev/logfire/ruby,
      # read 2026-10-15). Traces only; Logfire's metrics and logs SDKs are
      # pre-1.0. One span per experiment, one child span per case.
      #
      # The write token comes from `LOGFIRE_TOKEN`, our name for what their
      # page passes as a raw `Authorization` header. When the standard
      # `OTEL_EXPORTER_OTLP_ENDPOINT` or `OTEL_EXPORTER_OTLP_HEADERS` is
      # already set, the SDK's own reading of it wins and {#describe} says so.
      # The raw reply is not sent unless the config file opts in with
      # `logfire: { include_replies: true }`.
      class Logfire < Tracker
        # Logfire's US region, per their docs on 2026-10-15; other regions
        # exist, so LOGFIRE_BASE_URL overrides it.
        DEFAULT_BASE_URL = "https://logfire-us.pydantic.dev"
        TOKEN = "LOGFIRE_TOKEN"
        BASE_URL = "LOGFIRE_BASE_URL"
        OTEL_ENDPOINT = "OTEL_EXPORTER_OTLP_ENDPOINT"
        OTEL_HEADERS = "OTEL_EXPORTER_OTLP_HEADERS"

        # Bytes of the diagnostics JSON kept on a case span; the rest is cut,
        # since an attribute is not the place for a whole transcript.
        DIAGNOSTICS_LIMIT = 4096

        def self.env_key = TOKEN
        def self.gems = %w[opentelemetry-sdk opentelemetry-exporter-otlp]

        attr_reader :endpoint, :source

        # @param exporter [#export, nil] an exporter to use instead of OTLP, for tests
        # @param env [Hash]
        # @param context [Hash] see {Tracker#initialize}
        def initialize(exporter: nil, env: ENV, **context)
          super(**context)
          @env = env
          @exporter = exporter
          @endpoint, @headers, @source = settings(env)
          @cases = []
        end

        def describe = "logfire: endpoint #{endpoint || "(SDK default)"}, credentials from #{source}"

        # @return [Boolean] whether raw replies ride along on the case spans
        def include_replies? = options["include_replies"] == true || options[:include_replies] == true

        def start(experiment)
          @provider = provider
          @tracer = @provider.tracer("llm-evals", LLM::Evals::VERSION)
          @span = @tracer.start_span("experiment #{experiment.name}", attributes: experiment_attributes(experiment))
        end

        def record(result)
          now = Time.now
          span = @tracer.start_span("case #{result.case.key}",
            with_parent:     OpenTelemetry::Trace.context_with_span(@span),
            start_timestamp: now - result.duration,
            attributes:      case_attributes(result))
          if result.failed?
            span.record_exception(Error.new(result.error))
            span.status = OpenTelemetry::Trace::Status.error(result.error)
          end
          span.finish(end_timestamp: now)
        end

        # Closes the experiment span with the summary and flushes. No URL:
        # Logfire's trace pages are not something the token lets us build.
        #
        # @return [Hash] `url:` nil
        def finish(_experiment, summary)
          summary.means.each { |metric, mean| @span.set_attribute("evals.mean.#{metric}", mean) unless mean.nil? }
          @span.set_attribute("evals.errors", summary.errors.size)
          @span.set_attribute("evals.duration_seconds", summary.duration)
          @span.set_attribute("evals.usage.cost_usd", summary.usage.cost_usd)
          @span.finish
          @provider.force_flush
          @provider.shutdown unless @exporter # an injected exporter is the caller's to read afterwards
          { url: nil }
        end

        private

        # Which credentials win: the standard OTEL_* variables when either is
        # set, else our LOGFIRE_* pair. Returns the endpoint and headers to
        # hand the exporter (nil leaves the SDK's own reading in place).
        def settings(env)
          if [OTEL_ENDPOINT, OTEL_HEADERS].any? { !env[it].to_s.empty? }
            [env[OTEL_ENDPOINT], nil, "#{OTEL_ENDPOINT}/#{OTEL_HEADERS} (set in the environment; #{TOKEN} ignored)"]
          else
            base = env[BASE_URL].to_s.empty? ? DEFAULT_BASE_URL : env[BASE_URL]
            ["#{base.chomp("/")}/v1/traces", { "Authorization" => env[TOKEN].to_s }, "#{TOKEN}#{" and #{BASE_URL}" unless env[BASE_URL].to_s.empty?}"]
          end
        end

        # A tracer provider of our own, so the global one, which a consumer
        # may have configured for its application, is left alone.
        def provider
          exporter = @exporter || OpenTelemetry::Exporter::OTLP::Exporter.new(**{ endpoint: endpoint, headers: @headers }.compact)
          processor = if @exporter
                        OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter)
                      else
                        OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(exporter)
                      end
          resource = OpenTelemetry::SDK::Resources::Resource.create("service.name" => context[:suite] || "llm-evals")
          OpenTelemetry::SDK::Trace::TracerProvider.new(resource: resource).tap { it.add_span_processor(processor) }
        end

        def experiment_attributes(experiment)
          model = experiment.model
          { "evals.suite" => context[:suite].to_s, "evals.project" => context[:project].to_s, "evals.experiment" => experiment.name,
            "evals.model" => model.id, "evals.provider" => model.provider.name, "evals.dataset" => experiment.dataset,
            "evals.effort" => model.effort.to_s, "evals.temperature" => model.temperature.to_f, "evals.max_tokens" => model.max_tokens.to_i,
            "evals.cases" => experiment.cases.size }
        end

        def case_attributes(result)
          kase = result.case
          attributes = { "evals.case" => kase.id, "evals.dataset" => kase.dataset, "evals.variant" => kase.variant,
                         "evals.duration_seconds" => result.duration }
          return attributes.merge("evals.error" => result.error) if result.failed?

          score = result.score
          attributes["evals.score"] = score.value
          score.metrics.each { |metric, value| attributes["evals.metric.#{metric}"] = value unless value.nil? }
          score.outcomes.group_by { |_, v| v.to_s }.each { |outcome, pairs| attributes["evals.outcome.#{outcome}"] = pairs.size }
          attributes["evals.diagnostics"] = truncate(JSON.generate(score.diagnostics))
          attributes["evals.usage.input_tokens"] = result.reply.usage.input_tokens
          attributes["evals.usage.output_tokens"] = result.reply.usage.output_tokens
          attributes["evals.usage.cost_usd"] = result.reply.usage.cost_usd
          attributes["evals.reply_error"] = result.reply.error if result.reply.error?
          attributes["evals.reply"] = truncate(result.reply.raw.to_s) if include_replies?
          attributes
        end

        def truncate(text) = text.bytesize > DIAGNOSTICS_LIMIT ? "#{text.byteslice(0, DIAGNOSTICS_LIMIT)}..." : text
      end
    end
  end
end
