# frozen_string_literal: true

RSpec.describe Agent::Evals::CLI::Command do
  subject(:command) { described_class.new.tap { it.instance_variable_set(:@out, stream) } }

  let(:stream) { StringIO.new }

  def widths = stream.string.lines.map { it.chomp.length }.uniq

  describe "#table" do
    it "right-aligns columns that hold only numbers, placeholders aside" do
      command.send(:table,
        [["gemini", "97.1%", "default", "$0.0042"], ["jev", "-", "0.1", "$12.0000"]],
        header: %w[model accuracy temp cost],
        fill:   0)
      expect(stream.string).to match(/│ gemini +│    97\.1% │ default │  \$0\.0042 │/)
    end

    it "is exactly as wide as the terminal" do
      command.send(:table, [%w[gemini 97.1%]], header: %w[model accuracy])
      expect(widths).to eq([120])
    end

    it "wraps the fill column to fit, and stays that wide" do
      command.send(:table, [["01_case", "word " * 60]], header: %w[case wrong], fill: 1, wrap: true)
      expect(widths).to eq([120])
    end

    it "never wraps an unwrapped fill column, even when the table outgrows the screen" do
      command.send(:table, [["x" * 150, "1"]], header: %w[model n])
      expect(stream.string).to include("x" * 150)
    end

    it "draws a line between rows once a cell spans several lines" do
      command.send(:table, [%W[a one\ntwo], %w[b three]], header: %w[k v])
      expect(stream.string.scan("├").size).to eq(2)
    end

    context "when color is on" do
      before { allow(stream).to receive_messages(tty?: true, color?: true) }

      it "draws highlighted rows in bold yellow" do
        command.send(:table, [%w[a 1], %w[b 2]], header: %w[model n], highlight: [1])
        expect(stream.string).to include("\e[1;33mb\e[0m")
      end
    end
  end

  describe "#status_box" do
    it "frames the text plainly, the terminal's full width, without color" do
      command.send(:status_box, :info, "fake/one [vague]")
      expect([stream.string.include?("Info"), stream.string.include?("\e[44m"), widths]).to eq([true, false, [120]])
    end

    it "titles a warning" do
      command.send(:status_box, :warning, "careful")
      expect(stream.string).to include("Warning", "careful")
    end

    context "when color is on" do
      before { allow(stream).to receive_messages(tty?: true, color?: true, winsize: [40, 100]) }

      { info: "\e[44m", success: "\e[42m", warning: "\e[43m", error: "\e[41m" }.each do |level, background|
        it "paints #{level} on its background" do
          command.send(:status_box, level, "text")
          expect(stream.string).to include(background)
        end
      end
    end
  end

  describe "#wrap" do
    it "breaks at spaces within the width and keeps its own line breaks" do
      expect(command.send(:wrap, "aa bb cc\ndd", 5)).to eq("aa bb\ncc\ndd")
    end

    it "cuts a word longer than the width" do
      expect(command.send(:wrap, "abcdefgh", 3)).to eq("abc\ndef\ngh")
    end
  end

  describe "#terminal_width" do
    it { expect(command.send(:terminal_width)).to eq(120) }

    it "falls back when the terminal cannot say" do
      allow(stream).to receive_messages(tty?: true, color?: true)
      allow(stream).to receive(:winsize).and_raise(Errno::ENOTTY)
      expect(command.send(:terminal_width)).to eq(120)
    end
  end

  describe "#cases_for" do
    it { expect(command.send(:cases_for, ["clear"], dataset: "colors").size).to eq(2) }
    it { expect { command.send(:cases_for, ["nope"], dataset: "colors") }.to raise_error(Agent::Evals::Error, /no cases match nope in colors/) }
  end
end
