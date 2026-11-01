# frozen_string_literal: true

RSpec.describe LLM::Evals::CLI::Leaderboard do
  def leaderboard(*metrics)
    standings = LLM::Evals::CLI::Standings.new(metrics:, primary: metrics.first)
    described_class.new(standings:, table: ->(*, **) {}, out: StringIO.new, pastel: Pastel.new(enabled: false), colors: {})
  end

  describe "#glossary" do
    it "starts with the metrics and ends with the gem's columns" do
      terms = leaderboard(LLM::Evals::Metric.new(name: "accuracy", description: "right")).glossary.map(&:first)
      expect(terms.first).to eq("accuracy")
      expect(terms).to include("cost", "score")
    end

    it "marks a metric without a description" do
      expect(leaderboard(LLM::Evals::Metric.new(name: "bare")).glossary.first).to eq(["bare", "(no description)"])
    end

    it "lets a metric take over a column's name" do
      terms = leaderboard(LLM::Evals::Metric.new(name: "cost", description: "mine")).glossary
      expect(terms.count { it.first == "cost" }).to eq(1)
    end
  end
end
