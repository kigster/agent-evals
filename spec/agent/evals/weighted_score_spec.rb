# frozen_string_literal: true

RSpec.describe Agent::Evals::WeightedScore do
  subject(:weighted) { described_class.new(weights, metrics: %w[exact hallucinated_rate]) }

  let(:weights) { { "score" => 1 } }

  describe "#call" do
    it "uses a metric as it is under a positive weight" do
      expect(weighted.call([{ "score" => 0.9 }])).to eq([0.9])
    end

    context "with a negative weight on a metric" do
      let(:weights) { { "hallucinated_rate" => -1 } }

      it { expect(weighted.call([{ "hallucinated_rate" => 0.25 }])).to eq([0.75]) }
    end

    context "with weights that do not sum to 1" do
      let(:weights) { { "score" => 3, "exact" => 1 } }

      it { expect(weighted.call([{ "score" => 1.0, "exact" => 0.0 }])).to eq([0.75]) }
    end

    context "with cost" do
      let(:weights) { { "cost" => -1 } }

      it "places it on a log scale, so each doubling costs the same" do
        values = weighted.call([0.001, 0.002, 0.004].map { { "cost" => it } })
        expect(values).to eq(values.sort.reverse)
        expect(values).to match([be_within(1e-9).of(1.0), be_within(1e-9).of(0.5), be_within(1e-9).of(0.0)])
      end

      it "gives each 1 when all are equal" do
        expect(weighted.call([{ "cost" => 0.5 }, { "cost" => 0.5 }])).to eq([1.0, 1.0])
      end

      it "copes with a free model, which beats the rest" do
        expect(weighted.call([{ "cost" => 0.0 }, { "cost" => 0.004 }])).to eq([1.0, 0.0])
      end

      it "gives each 1 when every one is free" do
        expect(weighted.call([{ "cost" => 0.0 }, { "cost" => 0.0 }])).to eq([1.0, 1.0])
      end
    end

    context "with a column only some rows have" do
      let(:weights) { { "score" => 1, "exact" => 1 } }

      it "gives nil to the row missing it" do
        expect(weighted.call([{ "score" => 1.0, "exact" => 1.0 }, { "score" => 1.0, "exact" => nil }])).to eq([1.0, nil])
      end

      it "drops a column no row has" do
        expect(weighted.call([{ "score" => 0.5, "exact" => nil }])).to eq([0.5])
      end
    end

    it "gives nil when no weighted column is present at all" do
      expect(weighted.call([{ "score" => nil }])).to eq([nil])
    end
  end

  describe "the weights" do
    it "refuses tokens, naming what is known" do
      expect { described_class.new({ "tok_in" => -1 }, metrics: %w[exact]) }
        .to raise_error(Agent::Evals::Error, /unknown columns tok_in; known: exact, score, errors, time, cost/)
    end

    it "refuses a weight that is not a number" do
      expect { described_class.new({ "score" => "high" }, metrics: []) }.to raise_error(Agent::Evals::Error, /must be numbers: score/)
    end

    it "refuses all zeros" do
      expect { described_class.new({ "score" => 0 }, metrics: []) }.to raise_error(Agent::Evals::Error, /every weight is zero/)
    end

    it "ignores a zero among others" do
      expect(described_class.new({ "score" => 1, "cost" => 0 }, metrics: []).weights).to eq("score" => 1)
    end
  end

  it "states the formula and its weights" do
    expect(weighted.description).to include("Σ(|weight| × goodness)", "score 1")
  end
end
