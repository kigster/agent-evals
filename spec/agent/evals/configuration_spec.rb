# frozen_string_literal: true

RSpec.describe Agent::Evals::Configuration do
  subject(:configuration) { described_class.new }

  its(:name) { is_expected.to eq("agent-evals") }
  its(:cases_glob) { is_expected.to eq(described_class::DEFAULT_GLOB) }
  it { is_expected.not_to be_complete }
  it { expect(configuration.config).to eq(File.join(Dir.pwd, "config.yml")) }
  it { expect(configuration.providers.map(&:name)).to eq(%w[typesafe openrouter]) }

  it "refuses to serve a command without a suite" do
    expect { configuration.require_suite! }.to raise_error(Agent::Evals::Error, %r{create evals/eval_helper\.rb})
  end

  context "when configured" do
    let(:adapter) { Agent::Evals::Testing::EchoAdapter.new }
    let(:scorer) { Agent::Evals.configuration.scorer }
    let(:hook) { -> {} }
    let(:provider) { Agent::Evals::Testing::FakeProvider.new }

    before do
      configuration.suite "s", root: TOY_SUITE, env_files: ["evals/.env"], description: "desc"
      configuration.cases "evals/datasets/*/cases/**/input.txt"
      configuration.adapter adapter
      configuration.scorer scorer
      configuration.before_run(&hook)
      configuration.provider provider
      configuration.config "evals/config.yml"
      configuration.project "proj"
    end

    it { is_expected.to be_complete }
    it { expect(configuration.require_suite!).to be(configuration) }
    its(:root) { is_expected.to eq(TOY_SUITE) }
    its(:env_files) { is_expected.to eq([File.join(TOY_SUITE, "evals", ".env")]) }
    its(:description) { is_expected.to eq("desc") }
    its(:hooks) { is_expected.to eq([hook]) }
    it { expect(configuration.project).to eq("proj") }
    it { expect(configuration.config).to eq(File.join(TOY_SUITE, "evals", "config.yml")) }
    it { expect(configuration.lineup.project).to eq("toy-suite") }
    it { expect(configuration.discovery.datasets).to eq(%w[animals colors]) }
    it { expect(configuration.providers.for("fake/x")).to be(provider) }
    it { expect(configuration.runtime).to have_attributes(app_name: "s", hooks: [hook]) }

    it "takes the adapter and the scorer as writers too" do
      configuration.adapter = nil
      configuration.scorer = nil
      expect(configuration).not_to be_complete
    end
  end
end
