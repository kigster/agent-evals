# frozen_string_literal: true

RSpec.describe Agent::Evals::Render::Reports::Pipeline do
  subject(:pipeline) do
    described_class.new(providers: configuration.providers, runtime:, destination:, temp_dir: dir, project: "demo")
  end

  let(:configuration) { Agent::Evals.configuration }
  let(:runtime) { instance_double(Agent::Evals::Runtime, browse: true) }
  let(:dir) { Dir.mktmpdir }
  let(:destination) { File.join(dir, "out") }
  let(:metrics) { [Agent::Evals::Metric.new(name: "accuracy", primary: true)] }
  let(:model) { Agent::Evals::Model.new(id: "fake/echo", provider: configuration.providers.for("fake/echo")) }
  let(:summary) do
    Agent::Evals::Experiment::Summary.new(model:,
      dataset: "colors",
      name: "fake/echo",
      means: { "accuracy" => 1.0 },
      results: [],
      errors: [],
      duration: 0.0,
      permalink: nil,
      usage: Agent::Evals::Usage.zero)
  end
  let(:arguments) { { summaries: [summary], metrics:, weighted_score: nil, run_options: {} } }

  after { FileUtils.remove_entry(dir) }

  it "returns the JSON text when no path is given" do
    expect(JSON.parse(pipeline.write_json(**arguments, path: nil))).to include("format" => "agent-evals-report")
  end

  it "accepts a tui display without a block and removes the temporary snapshot" do
    result = pipeline.call(**arguments, autosave: false, display: "tui", open: false)
    expect([result.json_path, result.html_path, Dir[File.join(dir, "*.json")]]).to eq([nil, nil, []])
  end

  context "with the browser display" do
    let(:result) { pipeline.call(**arguments, autosave: true, display: "browser", open: true) }

    it "writes the HTML report beside its stylesheet and script" do
      expect([result.html_path, result.css_path, result.js_path, result.json_path]).to all(satisfy { File.exist?(it) })
    end

    it "links the assets by file name" do
      expect(File.read(result.html_path)).to include(File.basename(result.css_path), File.basename(result.js_path))
    end

    it "opens the report through the stubbed runtime" do
      expect(result.browser_opened).to be(true)
      expect(runtime).to have_received(:browse).with("file://#{result.html_path}")
    end
  end

  it "does not open a browser when open is false" do
    result = pipeline.call(**arguments, autosave: false, display: "browser", open: false)
    expect(result.browser_opened).to be_nil
    expect(runtime).not_to have_received(:browse)
  end
end
