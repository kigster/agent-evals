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
  it { is_expected.not_to be_braintrust }
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

  context "with a Braintrust project" do
    subject(:experiment) do
      described_class.new(model: model, cases: cases, adapter: adapter, scorer: scorer, project: "p", parallelism: 1, suite: "toy")
    end

    let(:result) do
      instance_double(Braintrust::Eval::Result, errors: ["one failed"], permalink: "https://bt/exp", scores: {})
    end

    before do
      require "braintrust"
      allow(Braintrust::Eval).to receive(:run) do |**args|
        args[:cases].each do |kase|
          output = args[:task].call(input: kase[:input])
          args[:scorers].each { it.call(expected: kase[:expected], output: output, metadata: kase[:metadata]) }
          args[:on_progress].call(nil)
        end
        result
      end
    end

    it { is_expected.to be_braintrust }

    it "runs through Braintrust and keeps its errors and permalink" do
      summary = experiment.run
      expect(summary).to have_attributes(errors: ["one failed"], permalink: "https://bt/exp")
      expect(summary.results.size).to eq(4)
    end

    it "names, tags and describes the experiment" do
      experiment.run
      expect(Braintrust::Eval).to have_received(:run).with(hash_including(
        project:     "p",
        project_id:  nil,
        experiment:  "fake/echo effort=default t=0.2 [colors]",
        quiet:       true,
        parallelism: 1,
        tags:        ["toy", "fake/echo", "dataset-colors"],
        metadata:    hash_including(model: "fake/echo", dataset: "colors", temperature: 0.2)
      ))
    end

    it "gives Braintrust one case per case" do
      expect(experiment.braintrust_cases.first).to include(
        input:    { case: "colors/clear/001", text: cases.first.input },
        expected: cases.first.expected,
        tags:     %w[variant-clear dataset-colors]
      )
    end

    it "returns the output, or _error, from the task" do
      expect(experiment.task.call(input: { "case" => "colors/clear/002" })).to eq("wall" => "blue", "trim" => "black", "rooms" => 2)
      expect(experiment.task.call(input: { case: "colors/vague/002" })).to eq("_error" => "reply is not JSON")
    end

    describe "#scorers" do
      let(:scorers) { experiment.scorers.to_h { [it.name, it] } }

      before { experiment.task.call(input: { case: "colors/clear/001" }) }

      it { expect(scorers.keys).to eq(%w[field_accuracy exact_match restraint]) }

      it "reads the score the task computed" do
        expect(scorers["exact_match"].call(metadata: { case: "colors/clear/001" }).first).to include(score: 0.0)
      end

      it "records nothing for a nil metric" do
        expect(scorers["restraint"].call(metadata: { "case" => "colors/clear/001" })).to eq([])
      end
    end

    it "prefers a project id over the name" do
      with_id = described_class.new(model: model, cases: cases, adapter: adapter, scorer: scorer, project: "p", project_id: "uuid")
      with_id.run
      expect(Braintrust::Eval).to have_received(:run).with(hash_including(project: nil, project_id: "uuid"))
    end
  end
end
