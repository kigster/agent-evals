# frozen_string_literal: true

RSpec.describe Agent::Evals::Runtime do
  subject(:runtime) { described_class.new(env_files: [env_file, File.join(dir, "missing")], hooks: hooks, app_name: "spec") }

  let(:dir) { Dir.mktmpdir }
  let(:env_file) { File.join(dir, ".env") }
  let(:hooks) { [] }

  after do
    FileUtils.remove_entry(dir)
    %w[AGENT_EVALS_A AGENT_EVALS_B AGENT_EVALS_C].each { ENV.delete(it) }
  end

  describe "#load_env" do
    before do
      ENV["AGENT_EVALS_B"] = "from-shell"
      File.write(env_file, "# comment\n\nAGENT_EVALS_A=\"quoted\"\nAGENT_EVALS_B=from-file\n")
      runtime.load_env
    end

    it { expect(ENV.fetch("AGENT_EVALS_A")).to eq("quoted") }
    it { expect(ENV.fetch("AGENT_EVALS_B")).to eq("from-shell") }
  end

  describe "#require_env!" do
    it "passes when every variable is set" do
      ENV["AGENT_EVALS_A"] = "set"
      expect { runtime.require_env!(%w[AGENT_EVALS_A]) }.not_to raise_error
    end

    it "names the missing variables, and says there is no env file" do
      expect { runtime.require_env!(%w[AGENT_EVALS_A AGENT_EVALS_B]) }
        .to raise_error(Agent::Evals::Error, /missing AGENT_EVALS_A, AGENT_EVALS_B: .*there is no #{Regexp.escape(env_file)}/)
    end

    it "says so when the env file exists but lacks them" do
      File.write(env_file, "OTHER=1\n")
      expect { runtime.require_env!(%w[AGENT_EVALS_C]) }.to raise_error(Agent::Evals::Error, /checked the environment, then #{Regexp.escape(env_file)}/)
    end

    it "says so when no env files are configured" do
      expect { described_class.new.require_env!(%w[AGENT_EVALS_C]) }.to raise_error(Agent::Evals::Error, /no env files are configured/)
    end
  end

  describe "#setup!" do
    let(:provider) { Agent::Evals::Testing::FakeProvider.new }
    let(:hooks) { [-> { ENV["AGENT_EVALS_C"] = "hooked" }] }

    before { allow(provider).to receive(:setup!) }

    it "loads env, runs the hooks and sets the providers up" do
      runtime.setup!(providers: [provider])
      expect(ENV.fetch("AGENT_EVALS_C")).to eq("hooked")
      expect(provider).to have_received(:setup!).with(app_name: "spec")
    end

    it "refuses to start without the providers' keys" do
      allow(provider).to receive(:env_keys).and_return(%w[AGENT_EVALS_A])
      expect { runtime.setup!(providers: [provider]) }.to raise_error(Agent::Evals::Error, /missing AGENT_EVALS_A/)
    end

    it "checks the chosen tracker's gems and key" do
      expect { runtime.setup!(tracker: RecordingTracker) }.to raise_error(Agent::Evals::Error, /RECORDING_TRACKER_KEY/)
    end
  end

  describe "#browse" do
    let(:browser) { described_class.new }

    before { allow(browser).to receive(:system).and_return(nil) }

    it { expect(browser.browse("https://example.com")).to be(false) }

    it "hands the URL to the platform opener" do
      browser.browse("https://example.com")
      expect(browser).to have_received(:system).with(a_string_matching(/open/), "https://example.com", out: File::NULL, err: File::NULL)
    end
  end
end
