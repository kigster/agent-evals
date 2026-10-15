# frozen_string_literal: true

RSpec.describe Agent::Evals::Experiment do
  subject(:experiment) do
    described_class.new(model: model, cases: cases, adapter: adapter, scorer: scorer, parallelism: 2)
  end

  let(:configuration) { Agent::Evals.configuration }
  let(:adapter) { configuration.adapter }
  let(:scorer) { configuration.scorer }
  let(:cases) { configuration.discovery.cases(dataset: "colors") }
  let(:model) { Agent::Evals::Testing::FakeModel.new(junk: ["vague/002"], wrong: { "clear/001" => { "trim" => "pink" } }) }

  its(:name) { is_expected.to eq("fake/echo effort=default t=0.2 [colors]") }
  its(:dataset) { is_expected.to eq("colors") }
  it { expect { described_class.new(model: model, cases: [], adapter: adapter, scorer: scorer) }.to raise_error(ArgumentError, /at least one case/) }

  describe "#run" do
    subject(:summary) { experiment.run(on_case: -> { ticks << 1 }) }

    let!(:ticks) { [] }

    its(:errors) { is_expected.to eq([]) }
    its(:permalink) { is_expected.to be_nil }
    its("results.size") { is_expected.to eq(4) }
    it { expect(summary.means["exact_match"]).to eq(0.5) }
    it { expect(summary.means["field_accuracy"]).to be_within(0.001).of(((2.0 / 3) + 1 + 1 + 0) / 4) }
    it { expect(summary.mean(scorer.primary)).to eq(summary.means["field_accuracy"]) }
    it { expect(summary.score).to eq(summary.means["field_accuracy"]) }
    it { expect(summary.means["restraint"]).to eq(0.5) }
    it { expect(summary.usage).to have_attributes(input_tokens: 400, output_tokens: 40) }
    it { expect(summary.results.map { it.case.id }).to eq(%w[clear/001 clear/002 vague/001 vague/002]) }

    it "diagnoses the wrong field" do
      expect(summary.results.first.score.diagnostics).to eq("trim" => { want: "white", got: "pink" })
    end

    it "scores a junk reply as zero rather than failing the case" do
      result = summary.results.last
      expect(result.reply).to be_error
      expect(result.score).to have_attributes(value: 0.0, diagnostics: { "error" => "reply is not JSON" })
    end

    it "reports each finished case" do
      summary
      expect(ticks.size).to eq(4)
    end

    context "when the adapter raises" do
      before { allow(adapter).to receive(:call).and_raise(RuntimeError, "out of credits") }

      it "counts the error and scores nothing" do
        expect(summary.errors).to all(match(%r{colors/\w+/00\d: RuntimeError: out of credits}))
        expect(summary.errors.size).to eq(4)
        expect(summary.means.values).to all(be_nil)
        expect(summary.results).to all(be_failed)
      end
    end

    context "when the adapter returns something else" do
      before { allow(adapter).to receive(:call).and_return({}) }

      it { expect(summary.errors.first).to include("returned Hash, not an Agent::Evals::Reply") }
    end
  end

  context "with trackers" do
    subject(:experiment) do
      described_class.new(model: model, cases: cases, adapter: adapter, scorer: scorer, parallelism: 1, trackers: [first, second, off])
    end

    let(:first) { RecordingTracker.new(url: "https://first/exp") }
    let(:second) { RecordingTracker.new(url: nil) }
    let(:off) { RecordingTracker.new(enabled: false) }

    it "tells each enabled tracker about the run, in order, and keeps the first URL" do
      summary = experiment.run
      expect(first.events.map(&:first)).to eq([:start, :record, :record, :record, :record, :finish])
      expect(first.events.select { it.first == :record }.map { it.last.case.id }).to eq(%w[clear/001 clear/002 vague/001 vague/002])
      expect(first.events.last.last).to be_a(described_class::Summary)
      expect(second.events.map(&:first)).to eq(first.events.map(&:first))
      expect(off.events).to eq([])
      expect(summary.permalink).to eq("https://first/exp")
      expect(experiment.trackers).to eq([first, second])
    end

    it "records a failed case too" do
      allow(adapter).to receive(:call).and_raise(IOError, "closed")
      experiment.run
      expect(first.events.select { it.first == :record }.map(&:last)).to all(be_failed)
    end
  end
end
