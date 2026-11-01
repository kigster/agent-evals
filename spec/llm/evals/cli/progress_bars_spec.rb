# frozen_string_literal: true

RSpec.describe LLM::Evals::CLI::ProgressBars do
  subject(:bars) { described_class.new(terminal, clock: -> { 0.0 }, config: Dry::CLI::UI.config) }

  let(:terminal) { Dry::CLI::UI::Terminal.new(StringIO.new, env: {}, color: false, animate: true, width: 120) }
  let(:job) { Dry::CLI::UI::Widgets::Multi::Job.new("fake/one", -> {}, Dry::CLI::UI::Widgets::Progress::Handle.new(3)) }

  before do
    3.times { job.handle.advance }
    job.state = :done
    job.seconds = 1.5
    bars.instance_variable_get(:@jobs) << job
    bars.instance_variable_set(:@title, "Running 1 experiment")
    bars.instance_variable_set(:@state, :running)
    bars.instance_variable_set(:@started, 0.0)
  end

  it "keeps a finished bar, full, with the time it took" do
    expect(bars.send(:row, job, 40)).to match(%r{\Afake/one {33}.* 100%  3/3  in 1\.5s|fake/one +\S+ 100%  3/3  in 1\.5s})
  end

  describe ".labels" do
    let(:runs) do
      [["01-bookkeeping-cfo", "moonshotai/kimi-k3", "effort=low t=0.2"], ["clear", "fake/one", "effort=default t=default"]].map do |dataset, id, label|
        instance_double(LLM::Evals::Experiment, dataset: dataset, model: instance_double(LLM::Evals::Model, id: id, label: label))
      end
    end

    it "pads the dataset and the settings, so every model starts in one column" do
      expect(described_class.labels(runs)).to eq([
                                                   "[01-bookkeeping-cfo]  effort=low t=0.2         | moonshotai/kimi-k3",
                                                   "[clear]               effort=default t=default | fake/one"
                                                 ])
    end
  end

  describe "the model's color" do
    let(:other) { Dry::CLI::UI::Widgets::Multi::Job.new("[b]  effort=low t=0.2 | fake/two", -> {}, Dry::CLI::UI::Widgets::Progress::Handle.new(3)) }
    let(:job) { Dry::CLI::UI::Widgets::Multi::Job.new("[a]  effort=low t=0.2 | fake/one", -> {}, Dry::CLI::UI::Widgets::Progress::Handle.new(3)) }
    let(:same) { Dry::CLI::UI::Widgets::Multi::Job.new("[b]  effort=low t=0.2 | fake/one", -> {}, Dry::CLI::UI::Widgets::Progress::Handle.new(3)) }

    before do
      allow(terminal).to receive(:pastel).and_return(Pastel.new(enabled: true))
      [other, same].each do |added|
        added.state = :running
        added.started = 0.0
        bars.instance_variable_get(:@jobs) << added
      end
    end

    # The color each row draws its model in.
    def colors = bars.send(:rows).drop(1).map { it[%r{\| (\e\[9\dm)fake/}, 1] }

    it "is bright, the same on every row of a model, and differs between models" do
      expect(colors).to all(match(/\e\[9[1-7]m/))
      expect(colors[0]).to eq(colors[2])
      expect(colors[0]).not_to eq(colors[1])
    end

    it "does not move the columns" do
      expect(bars.send(:label_width)).to eq(42)
    end
  end

  it "pads labels to at least 40 columns, plus the indent" do
    expect(bars.send(:label_width)).to eq(42)
  end

  it "lists the jobs under the headline without a tree" do
    expect(bars.send(:rows).last).to start_with("  ")
  end

  it "draws the headline's bar in yellow" do
    allow(terminal).to receive(:pastel).and_return(Pastel.new(enabled: true))
    bars.instance_variable_set(:@state, :running)
    bars.instance_variable_set(:@started, 0.0)
    expect(bars.send(:headline, 42)).to include("\e[33m")
  end

  context "when the screen is too short for every job" do
    subject(:bars) { described_class.new(terminal, clock: -> { now }, config: Dry::CLI::UI.config) }

    let(:now) { 10.0 }
    let(:running) do
      Array.new(3) do |index|
        Dry::CLI::UI::Widgets::Multi::Job.new("fake/running-#{index}", -> {}, Dry::CLI::UI::Widgets::Progress::Handle.new(2)).tap { it.state = :running }
      end
    end

    before do
      job.started = 8.0
      job.seconds = 1.5 # finished at 9.5
      bars.instance_variable_get(:@jobs).concat(running)
      allow(terminal).to receive(:height).and_return(4)
    end

    it "keeps a job that just finished, full, ahead of the newest running rows" do
      expect(bars.send(:visible)).to eq([job, running[0]])
      expect(bars.send(:rows)[1]).to include("100%  3/3  in 1.5s")
    end

    context "when the finished row has lingered" do
      let(:now) { 9.5 + described_class::LINGER }

      it "gives its place back to the running rows" do
        expect(bars.send(:visible)).to eq(running.first(2))
      end
    end

    it "gives the finished at most half the rows, the newest first" do
      newer = Dry::CLI::UI::Widgets::Multi::Job.new("fake/newer", -> {}, Dry::CLI::UI::Widgets::Progress::Handle.new(2))
      newer.state = :done
      newer.started = 9.0
      newer.seconds = 0.9 # finished at 9.9
      bars.instance_variable_get(:@jobs) << newer
      expect(bars.send(:visible)).to eq([running[0], newer])
    end

    it "leaves every row out of the final frame" do
      bars.instance_variable_set(:@state, :done)
      running.each { it.state = :done }
      expect(bars.send(:visible)).to be_empty
    end
  end

  it "overwrites the last frame in place, inside a synchronized update" do
    bars.instance_variable_set(:@drawn, 2)
    bars.send(:redraw)
    expect(terminal.instance_variable_get(:@io).string).to start_with("\e[?2026h\e[2A\r").and(end_with("\e[?2026l"))
  end
end
