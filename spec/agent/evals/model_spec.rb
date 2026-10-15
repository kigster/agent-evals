# frozen_string_literal: true

RSpec.describe Agent::Evals::Model do
  subject(:model) { described_class.new(id: "fake/one", provider: provider, settings: { "effort" => "low", temperature: 0.0 }) }

  let(:provider) { Agent::Evals::Testing::FakeProvider.new(answers: lambda(&:upcase)) }

  its(:effort) { is_expected.to eq("low") }
  its(:temperature) { is_expected.to eq(0.0) }
  its(:max_tokens) { is_expected.to be_nil }
  its(:name) { is_expected.to eq("one") }
  its(:label) { is_expected.to eq("effort=low t=0.0") }
  its(:to_s) { is_expected.to eq("fake/one effort=low t=0.0") }

  it "completes through its provider" do
    expect(model.complete(system: "s", user: "hi").text).to eq("HI")
    expect(provider.calls.first).to include(model: "fake/one", system: "s", json: true)
  end

  context "with the model's own defaults" do
    subject(:model) { described_class.new(id: "fake/one", provider: provider) }

    its(:label) { is_expected.to eq("effort=default t=default") }
  end
end
