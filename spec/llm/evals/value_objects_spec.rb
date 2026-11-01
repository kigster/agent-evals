# frozen_string_literal: true

RSpec.describe "value objects" do
  describe LLM::Evals::Usage do
    it { expect(described_class.zero).to have_attributes(input_tokens: 0, output_tokens: 0, cost_usd: 0.0) }
    it { expect(described_class.from(nil)).to eq(described_class.zero) }
    it { expect(described_class.from("input_tokens" => 3, "cost_usd" => "0.5")).to have_attributes(input_tokens: 3, cost_usd: 0.5) }

    it "returns the same usage it is given" do
      usage = described_class.new(input_tokens: 1, output_tokens: 2, cost_usd: 0.1)
      expect(described_class.from(usage)).to be(usage)
    end

    it "adds" do
      sum = described_class.new(input_tokens: 1, output_tokens: 2, cost_usd: 0.1) + described_class.new(input_tokens: 1, output_tokens: 2, cost_usd: 0.1)
      expect(sum).to have_attributes(input_tokens: 2, output_tokens: 4, cost_usd: be_within(1e-9).of(0.2))
    end
  end

  describe LLM::Evals::Completion do
    it "defaults the usage and stringifies the text" do
      expect(described_class.new(text: 42)).to have_attributes(text: "42", usage: LLM::Evals::Usage.zero, raw: nil)
    end
  end

  describe LLM::Evals::Reply do
    it { expect(described_class.new(output: {})).not_to be_error }
    it { expect(described_class.new(error: "no JSON")).to be_error }
    it { expect(described_class.new(usage: { input_tokens: 5 }).usage.input_tokens).to eq(5) }
  end

  describe LLM::Evals::Metric do
    subject(:metric) { described_class.new(name: :accuracy, description: "d", primary: true) }

    its(:name) { is_expected.to eq("accuracy") }
    its(:aggregate) { is_expected.to eq(:mean) }
    it { expect(metric.combine([1.0, nil, 0.0])).to eq(0.5) }
    it { expect(metric.combine([nil, nil])).to be_nil }
    it { expect { described_class.new(name: "x", aggregate: :median) }.to raise_error(ArgumentError, /aggregate/) }
  end

  describe LLM::Evals::Score do
    it "keeps the metrics by string name" do
      expect(described_class.new(value: 1, metrics: { accuracy: 1.0 }).metrics).to eq("accuracy" => 1.0)
    end

    it { expect { described_class.new(value: 1.5) }.to raise_error(ArgumentError, /not within 0..1/) }
    it { expect { described_class.new(value: nil) }.to raise_error(ArgumentError, /not within 0..1/) }

    it "builds the zero score of a failed reply" do
      metrics = [LLM::Evals::Metric.new(name: "a"), LLM::Evals::Metric.new(name: "b")]
      expect(described_class.failed(metrics, "no JSON"))
        .to have_attributes(value: 0.0, metrics: { "a" => 0.0, "b" => 0.0 }, diagnostics: { "error" => "no JSON" })
    end
  end

  describe LLM::Evals::RunResult do
    let(:kase) { LLM::Evals.configuration.discovery.all.first }

    it { expect(described_class.new(experiment: nil, case: kase, error: "boom")).to be_failed }
    it { expect(described_class.new(experiment: nil, case: kase)).not_to be_failed }
  end

  describe LLM::Evals::Case do
    subject(:kase) { LLM::Evals.configuration.discovery.cases(dataset: "colors").first }

    its(:id) { is_expected.to eq("clear/001") }
    its(:key) { is_expected.to eq("colors/clear/001") }
    its(:number) { is_expected.to eq(1) }
    its(:difficulty) { is_expected.to eq(1) }
    it { is_expected.to be_expected }
  end
end
