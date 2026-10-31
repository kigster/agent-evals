# frozen_string_literal: true

RSpec.describe Agent::Evals::Warnings do
  subject(:warnings) { described_class.new }

  it "skips blank lines" do
    warnings.puts("one", "", "  ")
    expect(warnings.to_a).to eq(["one"])
  end

  it "quacks as an IO" do
    expect(warnings.write("ab", "c")).to eq(3)
    warnings.print("d")
    warnings << "e"
    warnings.sync = false
    expect([warnings.flush, warnings.sync, warnings.close, warnings.tty?, warnings.count]).to eq([warnings, true, nil, false, 4])
  end

  describe "#capture" do
    let(:stderr) { $stderr }

    before do
      require "braintrust"
      require "ruby_llm"
      warnings.capture do
        warn "from Kernel#warn"
        Braintrust::Log.warn("from Braintrust")
        RubyLLM.logger.warn("from RubyLLM")
        OpenTelemetry.handle_error(message: "from OpenTelemetry")
      end
    end

    it { expect(warnings.to_a.join("\n")).to include("from Kernel#warn", "from Braintrust", "from RubyLLM", "from OpenTelemetry") }
    it { expect($stderr).to be(stderr) }

    it "puts OpenTelemetry's logger back" do
      original = OpenTelemetry.logger
      warnings.capture { expect(OpenTelemetry.logger).not_to be(original) }
      expect(OpenTelemetry.logger).to be(original)
    end

    it { expect(warnings).not_to be_none }
  end

  it "saves the warnings, one paragraph each" do
    path = File.join(Dir.mktmpdir, "w.log")
    warnings.record("a").record("b").save(path)
    expect(File.read(path)).to eq("a\n\nb\n")
  end
end
