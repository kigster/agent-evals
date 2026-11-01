# frozen_string_literal: true

require "opentelemetry/sdk"

RSpec.describe LLM::Evals::Trackers::Logfire do
  subject(:tracker) { described_class.new(exporter: exporter, env: env, suite: "toy", project: "proj", options: options) }

  let(:env) { { "LOGFIRE_TOKEN" => "pylf_token" } }
  let(:options) { {} }
  let(:exporter) { OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new }
  let(:configuration) { LLM::Evals.configuration }
  let(:model) { LLM::Evals::Testing::FakeModel.new(junk: ["vague/002"], settings: { effort: "low", temperature: 0.3, max_tokens: 99 }) }
  let(:experiment) do
    LLM::Evals::Experiment.new(model: model,
      cases: configuration.discovery.cases(dataset: "colors"),
      adapter: configuration.adapter,
      scorer: configuration.scorer,
      parallelism: 1,
      trackers: [tracker])
  end
  let(:spans) { exporter.finished_spans }
  let(:root) { spans.find { it.name.start_with?("experiment") } }
  let(:children) { spans.reject { it.name.start_with?("experiment") } }

  it { expect(described_class.env_key).to eq("LOGFIRE_TOKEN") }
  it { expect(described_class.gems).to eq(%w[opentelemetry-sdk opentelemetry-exporter-otlp]) }
  it { expect(described_class.tracker_name).to eq("logfire") }
  it { is_expected.not_to be_include_replies }

  describe "credentials" do
    it "builds the US endpoint and the Authorization header from LOGFIRE_TOKEN" do
      expect(tracker.endpoint).to eq("https://logfire-us.pydantic.dev/v1/traces")
      expect(tracker.source).to eq("LOGFIRE_TOKEN")
      expect(tracker.describe).to eq("logfire: endpoint https://logfire-us.pydantic.dev/v1/traces, credentials from LOGFIRE_TOKEN")
    end

    context "with another region" do
      let(:env) { { "LOGFIRE_TOKEN" => "t", "LOGFIRE_BASE_URL" => "https://logfire-eu.pydantic.dev/" } }

      it { expect(tracker.endpoint).to eq("https://logfire-eu.pydantic.dev/v1/traces") }
      it { expect(tracker.source).to eq("LOGFIRE_TOKEN and LOGFIRE_BASE_URL") }
    end

    context "when the standard OTEL variables are set" do
      let(:env) { { "LOGFIRE_TOKEN" => "t", "OTEL_EXPORTER_OTLP_ENDPOINT" => "https://otel.example/v1/traces", "OTEL_EXPORTER_OTLP_HEADERS" => "Authorization=x" } }

      it "lets them win and says so" do
        expect(tracker.endpoint).to eq("https://otel.example/v1/traces")
        expect(tracker.source).to include("OTEL_EXPORTER_OTLP_ENDPOINT/OTEL_EXPORTER_OTLP_HEADERS", "LOGFIRE_TOKEN ignored")
      end
    end

    it "builds a real OTLP exporter with the endpoint and header when none is injected" do
      require "opentelemetry/exporter/otlp"
      allow(OpenTelemetry::Exporter::OTLP::Exporter).to receive(:new).and_return(exporter)
      described_class.new(env: env, suite: "toy").start(experiment)
      expect(OpenTelemetry::Exporter::OTLP::Exporter).to have_received(:new)
        .with(endpoint: "https://logfire-us.pydantic.dev/v1/traces", headers: { "Authorization" => "pylf_token" })
    end
  end

  describe "the span tree" do
    before { experiment.run }

    it "has one experiment span with the settings and the means" do
      expect(root.name).to eq("experiment fake/echo effort=low t=0.3 [colors]")
      expect(root.attributes).to include("evals.suite" => "toy",
        "evals.project" => "proj",
        "evals.model" => "fake/echo",
        "evals.provider" => "fake",
        "evals.dataset" => "colors",
        "evals.effort" => "low",
        "evals.temperature" => 0.3,
        "evals.max_tokens" => 99,
        "evals.cases" => 4,
        "evals.mean.field_accuracy" => 0.75,
        "evals.mean.exact_match" => 0.75,
        "evals.mean.score" => 0.75,
        "evals.errors" => 0)
      expect(root.attributes).to have_key("evals.duration_seconds")
      expect(root.resource.attribute_enumerator.to_h["service.name"]).to eq("toy")
    end

    it "has one child span per case, under the experiment" do
      expect(children.map(&:name)).to eq(["case colors/clear/001", "case colors/clear/002", "case colors/vague/001", "case colors/vague/002"])
      expect(children.map(&:parent_span_id).uniq).to eq([root.span_id])
      expect(children.map(&:trace_id).uniq).to eq([root.trace_id])
    end

    it "puts the score, metrics, usage and diagnostics on a case span, and no reply" do
      attributes = children.first.attributes
      expect(attributes).to include("evals.case" => "clear/001",
        "evals.dataset" => "colors",
        "evals.variant" => "clear",
        "evals.score" => 1.0,
        "evals.metric.field_accuracy" => 1.0,
        "evals.metric.exact_match" => 1.0,
        "evals.diagnostics" => "{}",
        "evals.usage.input_tokens" => 100,
        "evals.usage.output_tokens" => 10,
        "evals.usage.cost_usd" => 0.001)
      expect(attributes).not_to have_key("evals.metric.restraint")
      expect(attributes).not_to have_key("evals.reply")
    end

    it "marks a model failure" do
      expect(children.last.attributes).to include("evals.score" => 0.0, "evals.reply_error" => "reply is not JSON")
      expect(children.last.status.code).to eq(OpenTelemetry::Trace::Status::UNSET)
    end
  end

  it "records an exception on a transport failure" do
    allow(configuration.adapter).to receive(:call).and_raise(IOError, "closed")
    experiment.run
    expect(children.first.status.code).to eq(OpenTelemetry::Trace::Status::ERROR)
    expect(children.first.attributes).to include("evals.error" => "IOError: closed")
    expect(children.first.events.map(&:name)).to eq(["exception"])
    expect(root.attributes["evals.errors"]).to eq(4)
  end

  context "when replies are opted in" do
    let(:options) { { "include_replies" => true } }

    it "sends the raw reply" do
      experiment.run
      expect(children.first.attributes["evals.reply"]).to include('"wall":"red"')
    end
  end

  it "truncates long diagnostics" do
    long = LLM::Evals::Score.new(value: 0.0, metrics: {}, diagnostics: { "x" => "y" * 5000 })
    allow(configuration.scorer).to receive(:call).and_return(long)
    experiment.run
    expect(children.first.attributes["evals.diagnostics"].bytesize).to eq(described_class::DIAGNOSTICS_LIMIT + 3)
  end
end
