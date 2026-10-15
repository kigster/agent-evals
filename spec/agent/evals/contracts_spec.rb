# frozen_string_literal: true

RSpec.describe "the two contracts" do
  let(:kase) { Agent::Evals.configuration.discovery.all.first }
  let(:model) { Agent::Evals::Testing::FakeModel.new }

  describe Agent::Evals::Adapter do
    subject(:adapter) { described_class.new }

    it { expect { adapter.call(kase, model: model) }.to raise_error(NotImplementedError, /must return an Agent::Evals::Reply/) }
    it { expect(adapter.prepare("x")).to be_nil }
    it { expect(adapter.context(kase)).to eq({}) }
    it { expect(adapter.verify("x")).to eq([]) }
    it { expect(adapter.metadata).to eq({}) }
  end

  describe Agent::Evals::Scorer do
    let(:scorer) { described_class.new }

    it { expect { scorer.metrics }.to raise_error(NotImplementedError, /Metric/) }
    it { expect { scorer.call(kase, nil, context: {}) }.to raise_error(NotImplementedError, /Score/) }
    it { expect(scorer.verify(kase, context: {})).to eq([]) }
    it { expect(scorer.summary(kase)).to be_nil }

    describe "#primary" do
      let(:metrics) { [Agent::Evals::Metric.new(name: "a"), Agent::Evals::Metric.new(name: "b", primary: true)] }

      it "is the metric flagged primary" do
        allow(scorer).to receive(:metrics).and_return(metrics)
        expect(scorer.primary.name).to eq("b")
      end

      it "falls back to the first" do
        allow(scorer).to receive(:metrics).and_return([Agent::Evals::Metric.new(name: "a")])
        expect(scorer.primary.name).to eq("a")
      end
    end
  end
end
