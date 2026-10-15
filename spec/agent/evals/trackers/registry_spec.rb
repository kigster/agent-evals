# frozen_string_literal: true

RSpec.describe Agent::Evals::Trackers::Registry do
  subject(:registry) { described_class.default }

  let(:braintrust) { Agent::Evals::Trackers::Braintrust }
  let(:logfire) { Agent::Evals::Trackers::Logfire }

  its(:names) { is_expected.to eq(%w[braintrust logfire]) }
  it { expect(registry.named(:logfire)).to be(logfire) }
  it { expect { registry.named("weave") }.to raise_error(Agent::Evals::Error, /no tracker named "weave"; known: braintrust, logfire/) }

  it "registers a tracker, replacing one of the same name" do
    registry.register(RecordingTracker)
    other = Class.new(RecordingTracker) { def self.tracker_name = "recording-tracker" }
    registry.register(other)
    expect(registry.select { it.tracker_name == "recording-tracker" }).to eq([other])
  end

  describe "#choose" do
    it { expect(registry.choose(local: true, flag: "braintrust", env: { "LOGFIRE_TOKEN" => "t" })).to be_nil }
    it { expect(registry.choose(flag: "logfire", config: "braintrust", env: { "BRAINTRUST_API_KEY" => "k" })).to eq([logfire, "--tracker"]) }
    it { expect(registry.choose(flag: "none", config: "braintrust", env: {})).to be_nil }
    it { expect(registry.choose(config: "braintrust", env: { "LOGFIRE_TOKEN" => "t" })).to eq([braintrust, "tracker: in the config file"]) }
    it { expect(registry.choose(config: "off", env: { "LOGFIRE_TOKEN" => "t" })).to be_nil }
    it { expect(registry.choose(env: {})).to be_nil }
    it { expect { registry.choose(flag: "weave", env: {}) }.to raise_error(Agent::Evals::Error, /no tracker named "weave"/) }

    it "auto-detects the one tracker whose key is set, and says so" do
      klass, why = registry.choose(env: { "LOGFIRE_TOKEN" => "t" })
      expect(klass).to be(logfire)
      expect(why).to include("LOGFIRE_TOKEN is set", "--tracker")
    end

    it "refuses an ambiguous environment" do
      expect { registry.choose(env: { "LOGFIRE_TOKEN" => "t", "BRAINTRUST_API_KEY" => "k" }) }
        .to raise_error(Agent::Evals::Error, /more than one tracker is configured in the environment \(BRAINTRUST_API_KEY, LOGFIRE_TOKEN\); choose one with --tracker braintrust\|logfire/)
    end
  end
end
