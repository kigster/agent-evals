# frozen_string_literal: true

RSpec.describe LLM::Evals::Contender do
  it "turns defaults into nil and parses the rest" do
    contender = described_class.new(model: "m", effort: "default", temperature: "default", max_tokens: "10")
    expect(contender.settings).to eq(effort: nil, temperature: nil, max_tokens: 10)
  end

  it "keeps explicit settings" do
    contender = described_class.new(model: "m", effort: "low", temperature: 0.3, max_tokens: nil)
    expect(contender.settings).to eq(effort: "low", temperature: 0.3, max_tokens: nil)
  end
end
