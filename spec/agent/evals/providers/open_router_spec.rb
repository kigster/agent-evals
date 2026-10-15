# frozen_string_literal: true

RSpec.describe Agent::Evals::Providers::OpenRouter do
  subject(:provider) { described_class.new }

  let(:model) { Agent::Evals::Model.new(id: "acme/m1", provider: provider, settings: { effort: "low", temperature: 0.0, max_tokens: 500 }) }
  let(:chat) { instance_double(RubyLLM::Chat) }
  let(:reply) { "```json\n{\"a\": 1}\n```" }

  before do
    require "ruby_llm"
    allow(RubyLLM).to receive(:chat).and_return(chat)
    %i[with_instructions with_temperature with_max_output_tokens with_thinking with_provider_options].each do |name|
      allow(chat).to receive(name).and_return(chat)
    end
    tokens = RubyLLM::Tokens.new(input: 1200, output: 80, reported_cost: 0.0003)
    allow(chat).to receive(:ask).and_return(instance_double(RubyLLM::Message, content: reply, tokens: tokens))
  end

  its(:name) { is_expected.to eq("openrouter") }
  its(:env_keys) { is_expected.to eq(["OPENROUTER_API_KEY"]) }
  its(:prefix) { is_expected.to eq("") }
  it { expect(provider.model_name("acme/m1")).to eq("acme/m1") }

  it "lists the catalog" do
    allow(Agent::Evals::Providers::Catalog).to receive(:fetch).with(described_class::URL).and_return("data" => [{ "id" => "a/b" }])
    expect(provider.catalog).to eq(["a/b"])
  end

  it "configures RubyLLM for OpenRouter" do
    ENV["OPENROUTER_API_KEY"] = "k"
    provider.setup!(app_name: "spec suite")
    expect(RubyLLM.config).to have_attributes(openrouter_api_key: "k", openrouter_app_name: "spec suite")
  ensure
    ENV.delete("OPENROUTER_API_KEY")
  end

  describe "#complete" do
    subject(:completion) { model.complete(system: "sys", user: "hello") }

    its(:text) { is_expected.to eq(reply) }
    it { expect(completion.usage).to eq(Agent::Evals::Usage.new(input_tokens: 1200, output_tokens: 80, cost_usd: 0.0003)) }

    it "sends the prompts through OpenRouter" do
      completion
      expect(RubyLLM).to have_received(:chat).with(model: "acme/m1", provider: :openrouter, assume_model_exists: true)
      expect(chat).to have_received(:with_instructions).with("sys")
      expect(chat).to have_received(:ask).with("hello")
    end

    it "sends the settings" do
      completion
      expect(chat).to have_received(:with_thinking).with(effort: :low)
      expect(chat).to have_received(:with_temperature).with(0.0)
      expect(chat).to have_received(:with_max_output_tokens).with(500)
      expect(chat).to have_received(:with_provider_options).with(response_format: { type: "json_object" })
    end

    context "with the model's own defaults and no JSON mode" do
      let(:model) { Agent::Evals::Model.new(id: "acme/m1", provider: provider) }

      before { model.complete(user: "hello", json: false) }

      it { expect(chat).not_to have_received(:with_thinking) }
      it { expect(chat).not_to have_received(:with_temperature) }
      it { expect(chat).not_to have_received(:with_max_output_tokens) }
      it { expect(chat).not_to have_received(:with_instructions) }
      it { expect(chat).not_to have_received(:with_provider_options) }
    end
  end
end
