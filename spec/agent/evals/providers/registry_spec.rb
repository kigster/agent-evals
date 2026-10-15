# frozen_string_literal: true

RSpec.describe Agent::Evals::Providers::Registry do
  subject(:registry) { described_class.default }

  let(:fake) { Agent::Evals::Testing::FakeProvider.new }
  let(:direct_jev) { contender("typesafe/jev-latest", provider: :typesafe) }

  def contender(model, provider: nil)
    Agent::Evals::Contender.new(model: model, effort: "default", temperature: 0.1, max_tokens: 10, provider: provider)
  end

  it { expect(registry.map(&:name)).to eq(%w[typesafe openrouter]) }
  it { expect(registry.for("anthropic/claude-haiku-5.5")).to be_a(Agent::Evals::Providers::OpenRouter) }
  it("sends Jev on OpenRouter to OpenRouter") { expect(registry.for("typesafe/jev-router")).to be_a(Agent::Evals::Providers::OpenRouter) }
  it("sends a direct entry to the provider it names") { expect(registry.for(direct_jev)).to be_a(Agent::Evals::Providers::TypeSafe) }
  it("never lets a direct provider claim a vendors id") { expect(registry.for(contender("typesafe/jev-latest"))).to be_a(Agent::Evals::Providers::OpenRouter) }
  its(:direct_names) { is_expected.to eq(["typesafe"]) }
  it { expect(registry.direct(:typesafe)).to be_a(Agent::Evals::Providers::TypeSafe) }
  it { expect { registry.direct(:ollama) }.to raise_error(Agent::Evals::Error, /no direct provider "ollama"; have typesafe/) }
  it { expect(registry.efforts).to eq(Agent::Evals::Providers::OpenRouter::EFFORTS) }

  it "asks the last registered provider first" do
    registry.register(fake)
    expect(registry.for("fake/x")).to be(fake)
    expect(registry.for("acme/x")).to be_a(Agent::Evals::Providers::OpenRouter)
  end

  it "names the providers when none serves an id" do
    only_fake = described_class.new([fake, Agent::Evals::Providers::TypeSafe.new])
    expect { only_fake.for("acme/x") }.to raise_error(Agent::Evals::Error, %r{no provider serves "acme/x"; have fake\z})
  end

  it "lists the providers and keys a lineup uses" do
    contenders = [contender("a/x"), contender("b/y"), direct_jev]
    expect(registry.used_by(contenders).map(&:name)).to eq(%w[openrouter typesafe])
    expect(registry.keys_for(contenders)).to eq(%w[OPENROUTER_API_KEY TYPESAFE_API_KEY])
  end

  it "builds a model through its provider" do
    registry.register(fake)
    expect(registry.model_for(contender("fake/x"))).to have_attributes(id: "fake/x", provider: fake, temperature: 0.1)
  end

  describe "#admit" do
    let(:contenders) { [contender("acme/x"), direct_jev, contender("typesafe/jev-router")] }

    it "admits the providers whose request type the suite declares, and refuses the rest by name" do
      admitted, refused = registry.admit(contenders, request_types: [:prompt])
      expect(admitted.map(&:model)).to eq(%w[acme/x typesafe/jev-router])
      expect(refused.map(&:to_s)).to eq(["typesafe/jev-latest refused: needs typesafe; this suite produces prompt"])
    end

    it "admits everything a suite declaring both can ask" do
      admitted, refused = registry.admit(contenders, request_types: %i[prompt typesafe])
      expect([admitted.size, refused]).to eq([3, []])
    end

    it "refuses everything when the suite declares only typesafe" do
      admitted, refused = registry.admit(contenders, request_types: [:typesafe])
      expect(admitted).to eq([direct_jev])
      expect(refused.map { it.contender.model }).to eq(%w[acme/x typesafe/jev-router])
    end
  end

  describe "#verify!" do
    before do
      allow(Agent::Evals::Providers::Catalog).to receive(:fetch).with(Agent::Evals::Providers::OpenRouter::URL)
                                                                .and_return("data" => [{ "id" => "a/x" }])
      allow(Agent::Evals::Providers::Catalog).to receive(:fetch).with(Agent::Evals::Providers::TypeSafe::URL, anything)
                                                                .and_return("models" => [{ "name" => "jev-latest" }])
    end

    it "passes models their providers list" do
      expect { registry.verify!([contender("a/x"), direct_jev]) }.not_to raise_error
    end

    it "names every model its provider does not list" do
      expect { registry.verify!([contender("a/y"), contender("typesafe/jev-9", provider: :typesafe)]) }
        .to raise_error(Agent::Evals::Error, %r{unknown models a/y, typesafe/jev-9: not listed})
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
