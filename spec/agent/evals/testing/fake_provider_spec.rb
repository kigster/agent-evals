# frozen_string_literal: true

RSpec.describe Agent::Evals::Testing::FakeProvider do
  subject(:provider) { described_class.new(junk: ["colors/vague/001"], wrong: { "clear/002" => { "rooms" => 9 } }) }

  let(:cases) { Agent::Evals.configuration.discovery.cases(dataset: "colors") }
  let(:model) { Agent::Evals::Model.new(id: "fake/echo", provider: provider) }

  def answer(kase) = model.complete(user: kase.input).text

  it { expect(JSON.parse(answer(cases[0]))).to eq(cases[0].expected) }
  it { expect(JSON.parse(answer(cases[1]))).to include("rooms" => 9) }
  it { expect(answer(cases[2])).to eq(described_class::JUNK) }
  it { expect(model.complete(user: "never seen").text).to eq("{}") }
  it { expect(model.complete(user: "x").usage).to eq(described_class::USAGE) }
  it { expect(provider.unknown(["fake/anything"])).to eq([]) }
  it { expect(provider.request_type).to eq(:prompt) }

  it "records its calls" do
    model.complete(system: "s", user: "u", json: false)
    expect(provider.calls).to eq([{ model: "fake/echo", system: "s", user: "u", json: false }])
  end

  it "answers through a callable instead" do
    custom = described_class.new(answers: ->(user) { "[#{user}]" })
    expect(Agent::Evals::Model.new(id: "fake/x", provider: custom).complete(user: "hi").text).to eq("[hi]")
  end

  it "looks cases up in the discovery it is given" do
    root = copy_toy_suite
    File.write(File.join(root, "datasets", "colors", "cases", "clear", "001", "expected.json"), '{"wall": "green"}')
    scoped = described_class.new(discovery: configuration_for(root).discovery)
    expect(JSON.parse(Agent::Evals::Model.new(id: "fake/x", provider: scoped).complete(user: cases[0].input).text)).to eq("wall" => "green")
  ensure
    FileUtils.remove_entry(File.dirname(root)) if root
  end

  describe Agent::Evals::Testing::FakeModel do
    subject(:fake) { described_class.new(junk: ["x"]) }

    its(:id) { is_expected.to eq("fake/echo") }
    its(:temperature) { is_expected.to eq(0.2) }
    it { expect(fake.provider).to be_a(Agent::Evals::Testing::FakeProvider) }
  end
end
