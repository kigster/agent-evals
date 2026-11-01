# frozen_string_literal: true

RSpec.describe Agent::Evals::Render::Reports::JSON do
  describe ".dump and .load" do
    let(:provider) { Agent::Evals.configuration.providers.for("fake/echo") }
    let(:model) { Agent::Evals::Model.new(id: "fake/echo", provider:, settings: { effort: "low", temperature: 0.2 }) }
    let(:kase) do
      Agent::Evals::Case.new(id: "clear/001",
        dataset: "colors",
        variant: "clear",
        input: "Choose blue.",
        expected: { color: "blue" },
        path: "/cases/clear/001",
        metadata: { number: 1, difficulty: 2 })
    end
    let(:experiment) do
      Agent::Evals::Experiment.new(model:,
        cases: [kase],
        adapter: Agent::Evals.configuration.adapter,
        scorer: Agent::Evals.configuration.scorer)
    end
    let(:score) { Agent::Evals::Score.new(value: 1, metrics: { "accuracy" => 1 }, outcomes: { "color" => true }, diagnostics: {}) }
    let(:reply) do
      Agent::Evals::Reply.new(output: { color: "blue" },
        raw: "{\"color\":\"blue\"}",
        usage: { input_tokens: 4, output_tokens: 2, cost_usd: 0.001 })
    end
    let(:result) { Agent::Evals::RunResult.new(experiment:, case: kase, reply:, score:, duration: 0.25) }
    let(:summary) do
      Agent::Evals::Experiment::Summary.new(model:,
        dataset: "colors",
        name: experiment.name,
        means: { "accuracy" => 1.0, "score" => 1.0 },
        results: [result],
        errors: [],
        duration: 0.25,
        permalink: nil,
        usage: reply.usage)
    end
    let(:metric) { Agent::Evals::Metric.new(name: "accuracy", primary: true) }
    let(:weighted) { Agent::Evals::WeightedScore.new({ "accuracy" => 0.75, "cost" => -0.25 }, metrics: ["accuracy"]) }

    it "round trips summaries, case data, replies, metrics, and ranking weights" do
      document = described_class.dump([summary], metrics: [metric], weighted_score: weighted)
      parsed = described_class.load(document, providers: Agent::Evals.configuration.providers)

      expect(parsed.metrics).to eq([metric])
      expect(parsed.weighted_score.weights).to eq(weighted.weights)
      expect(parsed.summaries.first.results.first.case.input).to eq("Choose blue.")
      expect(parsed.summaries.first.results.first.case.expected).to eq("color" => "blue")
      expect(parsed.summaries.first.results.first.reply.output).to eq("color" => "blue")
      expect(parsed.summaries.first.usage.input_tokens).to eq(4)
      expect(parsed.summaries.first.usage.output_tokens).to eq(2)
      expect(parsed.summaries.first.usage.cost_usd).to eq(0.001)
    end

    it "rejects an unsupported report format version" do
      expect { described_class.load('{"format":"agent-evals-report","version":9}', providers: Agent::Evals.configuration.providers) }
        .to raise_error(Agent::Evals::Error, /unsupported report format version/)
    end
  end

  describe ".decode errors" do
    let(:providers) { Agent::Evals.configuration.providers }

    it "rejects malformed JSON" do
      expect { described_class.decode("{not json", providers:) }.to raise_error(Agent::Evals::Error, /invalid report JSON/)
    end

    it "rejects a report naming an unknown provider" do
      document = { format: described_class::FORMAT, version: described_class::VERSION, metrics: [],
                   summaries: [{ model: { id: "x/y", provider: "nowhere" }, dataset: "d", name: "n", means: {}, results: [] }] }
      expect { described_class.decode(JSON.generate(document), providers:) }
        .to raise_error(Agent::Evals::Error, /unknown provider "nowhere"/)
    end
  end

  describe ".dump run options" do
    it "stringifies symbols in nested run options" do
      document = JSON.parse(described_class.dump([], metrics: [], run_options: { mode: :fast, list: [:a] }))
      expect(document["run_options"]).to eq("mode" => "fast", "list" => ["a"])
    end
  end
end
