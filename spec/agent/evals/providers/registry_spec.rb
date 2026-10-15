# frozen_string_literal: true

RSpec.describe Agent::Evals::Providers::Registry do
  subject(:registry) { described_class.default }

  let(:fake) { Agent::Evals::Testing::FakeProvider.new }

  def contender(model) = Agent::Evals::Contender.new(model: model, effort: "default", temperature: 0.1, max_tokens: 10)

  it { expect(registry.map(&:name)).to eq(%w[typesafe openrouter]) }
  it { expect(registry.for("anthropic/claude-haiku-5.5")).to be_a(Agent::Evals::Providers::OpenRouter) }
  it { expect(registry.for("typesafe-api/jev-latest")).to be_a(Agent::Evals::Providers::TypeSafe) }
  it { expect(registry.efforts).to eq(Agent::Evals::Providers::OpenRouter::EFFORTS) }

  it "asks the last registered provider first" do
    registry.register(fake)
    expect(registry.for("fake/x")).to be(fake)
    expect(registry.for("acme/x")).to be_a(Agent::Evals::Providers::OpenRouter)
  end

  it "names the providers when none serves an id" do
    empty = described_class.new([Agent::Evals::Providers::TypeSafe.new])
    expect { empty.for("acme/x") }.to raise_error(Agent::Evals::Error, %r{no provider serves "acme/x"; have typesafe})
  end

  it "lists the providers and keys a lineup uses" do
    contenders = [contender("a/x"), contender("b/y"), contender("typesafe-api/jev")]
    expect(registry.used_by(contenders).map(&:name)).to eq(%w[openrouter typesafe])
    expect(registry.keys_for(contenders)).to eq(%w[OPENROUTER_API_KEY TYPESAFE_API_KEY])
  end

  it "builds a model through its provider" do
    registry.register(fake)
    expect(registry.model_for(contender("fake/x"))).to have_attributes(id: "fake/x", provider: fake, temperature: 0.1)
  end

  describe "#verify!" do
    before do
      allow(Agent::Evals::Providers::Catalog).to receive(:fetch).with(Agent::Evals::Providers::OpenRouter::URL)
                                                                .and_return("data" => [{ "id" => "a/x" }])
      allow(Agent::Evals::Providers::Catalog).to receive(:fetch).with(Agent::Evals::Providers::TypeSafe::URL, anything)
                                                                .and_return("models" => [{ "name" => "jev-latest" }])
    end

    it "passes models their providers list" do
      expect { registry.verify!([contender("a/x"), contender("typesafe-api/jev-latest")]) }.not_to raise_error
    end

    it "names every model its provider does not list" do
      expect { registry.verify!([contender("a/y"), contender("typesafe-api/jev-9")]) }
        .to raise_error(Agent::Evals::Error, %r{unknown models a/y, typesafe-api/jev-9: not listed})
    end

    it "does not ask a provider no model uses" do
      registry.verify!([contender("a/x")])
      expect(Agent::Evals::Providers::Catalog).not_to have_received(:fetch).with(Agent::Evals::Providers::TypeSafe::URL, anything)
    end

    it "passes anything through a provider without a catalog" do
      registry.register(fake)
      expect { registry.verify!([contender("fake/anything")]) }.not_to raise_error
    end
  end
end
