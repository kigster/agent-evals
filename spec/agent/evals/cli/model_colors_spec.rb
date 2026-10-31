# frozen_string_literal: true

RSpec.describe Agent::Evals::CLI::ModelColors do
  subject(:colors) { described_class.new }

  it "keeps a model's color" do
    first = colors["fake/one"]
    colors["fake/two"]
    expect(colors["fake/one"]).to be(first)
  end

  it "gives models their own until they run out" do
    models = described_class::COLORS.size.times.map { "fake/#{it}" }
    expect(models.map { colors[it] }).to match_array(described_class::COLORS)
  end

  it "shares them after that" do
    described_class::COLORS.size.times { colors["fake/#{it}"] }
    expect(described_class::COLORS).to include(colors["fake/extra"])
  end
end
