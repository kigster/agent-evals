# frozen_string_literal: true

RSpec.describe Agent::Evals::Providers::TypeSafe do
  subject(:provider) { described_class.new }

  its(:name) { is_expected.to eq("typesafe") }
  its(:efforts) { is_expected.to eq([]) }
  its(:env_keys) { is_expected.to eq(["TYPESAFE_API_KEY"]) }
  it { expect(provider).to be_serves("typesafe-api/jev-latest") }
  it { expect(provider).not_to be_serves("typesafe/jev-router") }
  it { expect(provider.model_name("typesafe-api/jev-latest")).to eq("jev-latest") }
  it { expect(provider.usage(input_tokens: 1_000_000).cost_usd).to be_within(1e-9).of(0.042) }

  it "lists the catalog with the prefix" do
    allow(Agent::Evals::Providers::Catalog).to receive(:fetch).with(described_class::URL, hash_including("Authorization"))
                                                              .and_return("models" => [{ "name" => "jev-latest" }])
    expect(provider.catalog).to eq(["typesafe-api/jev-latest"])
  end

  it "refuses to chat" do
    model = provider.model_for(Agent::Evals::Contender.new(model: "typesafe-api/jev-latest", effort: nil, temperature: nil, max_tokens: nil))
    expect { model.complete(user: "x") }.to raise_error(Agent::Evals::Error, /typed questions, not chat/)
  end
end
