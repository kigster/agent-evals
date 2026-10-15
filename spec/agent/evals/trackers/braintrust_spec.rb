# frozen_string_literal: true

require "braintrust"
require "opentelemetry/sdk"

RSpec.describe Agent::Evals::Trackers::Braintrust do
  subject(:tracker) { described_class.new(suite: "toy", project: "proj", project_id: project_id) }

  let(:project_id) { nil }
  let(:exporter) { OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new }
  let(:provider) do
    OpenTelemetry::SDK::Trace::TracerProvider.new.tap { it.add_span_processor(OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter)) }
  end
  let(:state) { instance_double(Braintrust::State, login: nil, object_permalink: "https://bt/exp/e1") }
  let(:projects) { instance_double(Braintrust::API::Internal::Projects, create: { "id" => "p1" }) }
  let(:experiments) { instance_double(Braintrust::API::Internal::Experiments, create: { "id" => "e1" }) }
  let(:configuration) { Agent::Evals.configuration }
  let(:experiment) do
    Agent::Evals::Experiment.new(model: Agent::Evals::Testing::FakeModel.new(junk: ["vague/002"]),
      cases: configuration.discovery.cases(dataset: "colors"),
      adapter: configuration.adapter,
      scorer: configuration.scorer,
      parallelism: 1,
      trackers: [tracker])
  end
  let(:spans) { exporter.finished_spans }

  before do
    allow(Braintrust).to receive_messages(init: nil, current_state: state)
    allow(OpenTelemetry).to receive(:tracer_provider).and_return(provider)
    allow(Braintrust::API::Internal::Projects).to receive(:new).with(state).and_return(projects)
    allow(Braintrust::API::Internal::Experiments).to receive(:new).with(state).and_return(experiments)
  end

  it { expect(described_class.env_key).to eq("BRAINTRUST_API_KEY") }
  it { expect(described_class.gems).to eq(["braintrust"]) }
  it { expect(described_class.tracker_name).to eq("braintrust") }
  it { expect(tracker.describe).to eq('braintrust: project "proj"') }

  it "logs in, creates the project and the experiment, and hands back its page" do
    summary = experiment.run
    expect(Braintrust).to have_received(:init).with(blocking_login: true, auto_instrument: false)
    expect(projects).to have_received(:create).with(name: "proj")
    expect(experiments).to have_received(:create).with(hash_including(
      name:       "fake/echo effort=default t=0.2 [colors]",
      project_id: "p1",
      ensure_new: true,
      tags:       ["toy", "fake/echo", "dataset-colors"],
      metadata:   hash_including(model: "fake/echo", provider: "fake", temperature: 0.2)
    ))
    expect(summary.permalink).to eq("https://bt/exp/e1")
  end

  it "emits one eval span per case, parented to the experiment, with scores and metadata" do
    experiment.run
    expect(spans.map(&:name)).to eq(%w[eval eval eval eval])
    first = spans.first.attributes
    expect(first["braintrust.parent"]).to eq("experiment_id:e1")
    expect(JSON.parse(first["braintrust.input_json"])).to include("case" => "colors/clear/001")
    expect(JSON.parse(first["braintrust.expected_json"])).to eq("wall" => "red", "trim" => "white", "rooms" => 1)
    expect(JSON.parse(first["braintrust.output_json"])).to eq("wall" => "red", "trim" => "white", "rooms" => 1)
    expect(JSON.parse(first["braintrust.scores"])).to eq("field_accuracy" => 1.0, "exact_match" => 1.0)
    expect(JSON.parse(first["braintrust.metadata"])).to include("case" => "colors/clear/001", "usage" => hash_including("input_tokens" => 100))
    expect(first["braintrust.tags"]).to eq(%w[variant-clear dataset-colors])
  end

  it "records a model failure as _error output with every score 0" do
    experiment.run
    junk = spans.last.attributes
    expect(JSON.parse(junk["braintrust.output_json"])).to eq("_error" => "reply is not JSON")
    expect(JSON.parse(junk["braintrust.scores"])).to eq("field_accuracy" => 0.0, "exact_match" => 0.0, "restraint" => 0.0)
  end

  it "marks a transport failure on the span and sends no output" do
    allow(configuration.adapter).to receive(:call).and_raise(IOError, "closed")
    experiment.run
    expect(spans.first.status.code).to eq(OpenTelemetry::Trace::Status::ERROR)
    expect(spans.first.attributes).not_to have_key("braintrust.output_json")
    expect(JSON.parse(spans.first.attributes["braintrust.metadata"])).to include("error" => "IOError: closed")
  end

  context "with a project id" do
    let(:project_id) { "uuid" }

    it "skips the project lookup" do
      experiment.run
      expect(projects).not_to have_received(:create)
      expect(experiments).to have_received(:create).with(hash_including(project_id: "uuid"))
      expect(tracker.describe).to eq("braintrust: project uuid")
    end
  end
end
