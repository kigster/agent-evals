# frozen_string_literal: true

RSpec.describe LLM::Evals::Testing::EchoAdapter do
  subject(:reply) { described_class.new.call(kase, model: model) }

  let(:kase) { LLM::Evals.configuration.discovery.cases(dataset: "animals").first }
  let(:model) { LLM::Evals::Testing::FakeModel.new(answers: ->(_) { text }) }
  let(:text) { "```json\n{\"species\": [\"cat\"]}\n```" }

  it "parses a fenced JSON object" do
    expect(reply).to have_attributes(output: { "species" => ["cat"] }, raw: text, error: nil)
    expect(reply.usage).to eq(LLM::Evals::Testing::FakeProvider::USAGE)
  end

  it "sends the input as the user prompt" do
    reply
    expect(model.provider.calls.first).to include(user: kase.input, system: described_class::SYSTEM, json: true)
  end

  context "when the reply is prose" do
    let(:text) { "Sure, two cats." }

    it { expect(reply).to have_attributes(error: "reply is not JSON", raw: text) }
  end

  context "when the reply is JSON but not an object" do
    let(:text) { "[1, 2]" }

    it { expect(reply.error).to eq("reply is not a JSON object") }
  end
end
