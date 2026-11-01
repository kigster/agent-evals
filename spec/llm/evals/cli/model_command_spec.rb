# frozen_string_literal: true

RSpec.describe LLM::Evals::CLI::ModelCommand do
  let(:command) { described_class.new }

  describe "#best_value" do
    def best(entries) = command.send(:best_value, entries)

    it "picks the cheapest entry within two points of the best primary metric" do
      expect(best([[0.98, 0.0486, 0], [0.969, 0.0037, 0], [0.894, 0.0014, 0]])).to eq(1)
    end

    it "never picks a cheap entry that falls outside the margin" do
      expect(best([[0.98, 0.05, 0], [0.95, 0.001, 0]])).to eq(0)
    end

    it "skips entries with errors or no score" do
      expect(best([[0.99, 0.0, 10], [nil, 0.0, 0], [0.9, 0.01, 0]])).to eq(2)
    end

    it { expect(best([[nil, 0.0, 3]])).to be_nil }
  end

  describe "#glossary" do
    it "starts with the scorer's metrics and ends with the gem's columns" do
      terms = command.send(:glossary).map(&:first)
      expect(terms.first(3)).to eq(%w[field_accuracy exact_match restraint])
      expect(terms).to include("cost", "score")
    end

    it "marks a metric without a description" do
      allow(command).to receive(:metrics).and_return([LLM::Evals::Metric.new(name: "bare")])
      expect(command.send(:glossary).first).to eq(["bare", "(no description)"])
    end
  end
end
