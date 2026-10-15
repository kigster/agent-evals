# frozen_string_literal: true

RSpec.describe Agent::Evals::Providers::TypeSafe do
  subject(:provider) { described_class.new }

  its(:name) { is_expected.to eq("typesafe") }
  its(:request_type) { is_expected.to eq(:typesafe) }
  its(:efforts) { is_expected.to eq([]) }
  its(:env_keys) { is_expected.to eq(["TYPESAFE_API_KEY"]) }
  it { is_expected.to be_direct }
  its(:request_type_description) { is_expected.to eq("typed questions: noul, choice, score") }
  it { expect(provider.model_name("typesafe/jev-latest")).to eq("jev-latest") }
  it { expect(provider.usage(input_tokens: 1_000_000).cost_usd).to be_within(1e-9).of(0.042) }

  it "lists the catalog with the prefix" do
    allow(Agent::Evals::Providers::Catalog).to receive(:fetch).with(described_class::URL, hash_including("Authorization"))
                                                              .and_return("models" => [{ "name" => "jev-latest" }])
    expect(provider.catalog).to eq(["typesafe/jev-latest"])
  end

  it "refuses to chat" do
    model = provider.model_for(Agent::Evals::Contender.new(model: "typesafe/jev-latest", provider: :typesafe))
    expect { model.complete(user: "x") }.to raise_error(Agent::Evals::Error, /no typesafe consumer yet; the typed request shape is defined by the first suite that declares request_types: \[typesafe\]/)
  end
end
