# frozen_string_literal: true

RSpec.describe Agent::Evals::Trackers::Local do
  subject(:tracker) { described_class.new(dir: dir, suite: "toy") }

  let(:dir) { File.join(Dir.mktmpdir, "log") }
  let(:configuration) { Agent::Evals.configuration }
  let(:experiment) do
    Agent::Evals::Experiment.new(model: Agent::Evals::Testing::FakeModel.new(junk: ["vague/002"]),
      cases: configuration.discovery.cases(dataset: "colors"),
      adapter: configuration.adapter,
      scorer: configuration.scorer,
      trackers: [tracker])
  end

  after { FileUtils.remove_entry(File.dirname(dir)) }

  it { expect(described_class.new(suite: "x").dir).to end_with("/log/agent-evals") }
  it { expect(tracker.describe).to eq("local: #{dir}") }

  it "writes the run to one JSON file, and returns no URL" do
    summary = experiment.run
    files = Dir[File.join(dir, "*.json")]
    expect(files.size).to eq(1)
    expect(File.basename(files.first)).to match(/\Afake_echo_effort_default_t_0\.2_colors\.\d{4}-\d\d-\d\d\.\d{6}\.json\z/)
    document = JSON.parse(File.read(files.first))
    expect(document).to include("suite" => "toy", "model" => "fake/echo", "provider" => "fake", "dataset" => "colors", "errors" => [])
    expect(document["means"]).to eq(summary.means)
    expect(document["results"].map { it["case"] }).to eq(%w[colors/clear/001 colors/clear/002 colors/vague/001 colors/vague/002])
    expect(document["results"].last).to include("score" => 0.0, "reply_error" => "reply is not JSON", "diagnostics" => { "error" => "reply is not JSON" })
    expect(summary.permalink).to be_nil
  end

  it "records a failed case with its error and no score" do
    allow(configuration.adapter).to receive(:call).and_raise(IOError, "closed")
    experiment.run
    row = JSON.parse(File.read(Dir[File.join(dir, "*.json")].first))["results"].first
    expect(row).to include("error" => "IOError: closed", "score" => nil, "usage" => nil)
  end
end
