# frozen_string_literal: true

RSpec.describe LLM::Evals::Tracker do
  subject(:tracker) { described_class.new(suite: "s", options: { "a" => 1 }) }

  it { expect(described_class.tracker_name).to eq("tracker") }
  it { expect(described_class.env_key).to be_nil }
  it { expect(described_class.gems).to eq([]) }
  it { expect(described_class.detect?({})).to be(false) }
  it { expect { described_class.requirements!({}) }.not_to raise_error }
  its(:name) { is_expected.to eq("tracker") }
  its(:describe) { is_expected.to eq("tracker") }
  it { is_expected.to be_enabled }
  its(:options) { is_expected.to eq("a" => 1) }
  it { expect(tracker.start(nil)).to be_nil }
  it { expect(tracker.record(nil)).to be_nil }
  it { expect(tracker.finish(nil, nil)).to eq(url: nil) }

  describe ".requirements!" do
    it "names the gem a tracker needs" do
      klass = Class.new(described_class) { def self.gems = ["no-such-tracker-gem"] }
      expect { klass.requirements!({}) }.to raise_error(LLM::Evals::MissingDependency, /needs the no-such-tracker-gem gem/)
    end

    it "names the env key a tracker needs" do
      expect { RecordingTracker.requirements!({}) }
        .to raise_error(LLM::Evals::Error, /the recording-tracker tracker needs RECORDING_TRACKER_KEY in the environment/)
      expect { RecordingTracker.requirements!("RECORDING_TRACKER_KEY" => "k") }.not_to raise_error
    end
  end
end
