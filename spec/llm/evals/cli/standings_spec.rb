# frozen_string_literal: true

RSpec.describe LLM::Evals::CLI::Standings do
  subject(:standings) { described_class.new(metrics: [metric], primary: metric) }

  let(:metric) { LLM::Evals::Metric.new(name: "accuracy", primary: true) }

  describe "#best_value" do
    it "picks the cheapest entry within two points of the best primary metric" do
      expect(standings.best_value([[0.98, 0.0486, 0], [0.969, 0.0037, 0], [0.894, 0.0014, 0]])).to eq(1)
    end

    it "never picks a cheap entry that falls outside the margin" do
      expect(standings.best_value([[0.98, 0.05, 0], [0.95, 0.001, 0]])).to eq(0)
    end

    it "skips entries with errors or no score" do
      expect(standings.best_value([[0.99, 0.0, 10], [nil, 0.0, 0], [0.9, 0.01, 0]])).to eq(2)
    end

    it { expect(standings.best_value([[nil, 0.0, 3]])).to be_nil }
  end
end
