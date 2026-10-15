# frozen_string_literal: true

RSpec.describe Agent::Evals::CLI::ProgressBars do
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

  it "overwrites the last frame in place, inside a synchronized update" do
    bars.instance_variable_set(:@drawn, 2)
    bars.send(:redraw)
    expect(terminal.instance_variable_get(:@io).string).to start_with("\e[?2026h\e[2A\r").and(end_with("\e[?2026l"))
  end
end
