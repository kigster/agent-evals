# frozen_string_literal: true

RSpec.describe Agent::Evals::Configuration do
  subject(:configuration) { described_class.new }

  its(:name) { is_expected.to eq("agent-evals") }
  its(:cases_glob) { is_expected.to eq(described_class::DEFAULT_GLOB) }
  it { is_expected.not_to be_complete }
  it { expect(configuration.config).to eq(File.join(Dir.pwd, ".agent-eval.config.yml")) }
  it { expect(configuration.providers.map(&:name)).to eq(%w[typesafe openrouter]) }
  it { expect(configuration.trackers.names).to eq(%w[braintrust logfire]) }

  it "registers a tracker" do
    configuration.tracker RecordingTracker
    expect(configuration.trackers.named("recording-tracker")).to be(RecordingTracker)
  end

  it "refuses to serve a command without a suite, naming the file and the keys" do
    expect { configuration.require_suite! }
      .to raise_error(Agent::Evals::Error, %r{register an adapter and a scorer in evals/eval_helper\.rb, or set adapter: and scorer: \(with require:\) in #{Regexp.escape(configuration.config)}})
  end

  describe "#resolve_from_config!" do
    let(:dir) { Dir.mktmpdir }
    let(:path) { File.join(dir, ".agent-eval.config.yml") }

    before { configuration.suite "cfg", root: dir }

    after { FileUtils.remove_entry(dir) }

    def write(yaml) = File.write(path, yaml)

    it "fills the adapter and the scorer from the file" do
      write("require: toy_suite/evals\nadapter: ToySuite::Evals::Adapter\nscorer: ToySuite::Evals::Scorer\n")
      expect(configuration.require_suite!.adapter).to be_a(ToySuite::Evals::Adapter)
      expect(configuration.scorer).to be_a(ToySuite::Evals::Scorer)
    end

    it "lets the helper win and fills only what it left unset" do
      adapter = Agent::Evals::Testing::EchoAdapter.new
      configuration.adapter adapter
      write("require: [toy_suite/evals]\nadapter: ToySuite::Evals::Adapter\nscorer: ToySuite::Evals::Scorer\n")
      configuration.require_suite!
      expect(configuration.adapter).to be(adapter)
      expect(configuration.scorer).to be_a(ToySuite::Evals::Scorer)
    end

    it "names the key and the value of a require that fails" do
      write("require: no_such_evals_gem\nadapter: X\nscorer: Y\n")
      expect { configuration.require_suite! }
        .to raise_error(Agent::Evals::Error, /#{Regexp.escape(path)}: require: no_such_evals_gem could not be loaded \(cannot load such file/)
    end

    it "names the key and the value of an unknown constant" do
      write("adapter: ToySuite::Evals::Nope\nscorer: ToySuite::Evals::Scorer\n")
      expect { configuration.require_suite! }
        .to raise_error(Agent::Evals::Error, /#{Regexp.escape(path)}: adapter: ToySuite::Evals::Nope could not be instantiated \(NameError/)
    end

    it "names the key of a constant that cannot be built without arguments" do
      write("adapter: ToySuite::Evals::Adapter\nscorer: Agent::Evals::Metric\n")
      expect { configuration.require_suite! }.to raise_error(Agent::Evals::Error, /scorer: Agent::Evals::Metric could not be instantiated \(ArgumentError/)
    end

    it "still fails without the keys, naming them" do
      write("request_types: [prompt]\n")
      expect { configuration.require_suite! }.to raise_error(Agent::Evals::Error, /set adapter: and scorer: \(with require:\) in #{Regexp.escape(path)}/)
    end

    it "does nothing once complete" do
      configuration.adapter Agent::Evals::Testing::EchoAdapter.new
      configuration.scorer ToySuite::Evals::Scorer.new
      write("require: no_such_evals_gem\n")
      expect { configuration.require_suite! }.not_to raise_error
    end
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
      configuration.config "evals/.agent-eval.config.yml"
      configuration.project "proj"
    end

    it { is_expected.to be_complete }
    it { expect(configuration.require_suite!).to be(configuration) }
    its(:root) { is_expected.to eq(TOY_SUITE) }
    its(:env_files) { is_expected.to eq([File.join(TOY_SUITE, "evals", ".env")]) }
    its(:description) { is_expected.to eq("desc") }
    its(:hooks) { is_expected.to eq([hook]) }
    it { expect(configuration.project).to eq("proj") }
    it { expect(configuration.config).to eq(File.join(TOY_SUITE, "evals", ".agent-eval.config.yml")) }
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
