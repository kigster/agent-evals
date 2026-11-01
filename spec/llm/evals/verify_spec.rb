# frozen_string_literal: true

RSpec.describe LLM::Evals::Verify do
  subject(:problems) { described_class.new(configuration).problems }

  let(:configuration) { LLM::Evals.configuration }

  it { is_expected.to eq({}) }

  context "with a broken copy" do
    let(:root) { copy_toy_suite }
    let(:configuration) { configuration_for(root) }
    let(:colors) { File.join(root, "datasets", "colors", "cases") }

    before do
      File.write(File.join(colors, "clear", "001", "input.txt"), "  \n")
      File.write(File.join(colors, "clear", "002", "expected.json"), "[1, 2]")
      File.write(File.join(colors, "vague", "001", "expected.json"), "{oops")
      File.delete(File.join(colors, "vague", "002", "expected.json"))
    end

    after { FileUtils.remove_entry(File.dirname(root)) }

    it "reports each problem under its case" do
      expect(problems).to match(
        "colors/clear/001" => ["input is empty"],
        "colors/clear/002" => ["expected.json must hold an object"],
        "colors/vague/001" => [a_string_starting_with("expected.json is not valid JSON")],
        "colors/vague/002" => ["expected.json is missing"]
      )
    end

    it "turns an exception in the scorer into a problem" do
      allow(configuration.scorer).to receive(:verify).and_raise(KeyError, "nope")
      expect(problems["animals/clear/001"]).to eq(["KeyError: nope"])
    end

    it "includes what the adapter says about a dataset" do
      allow(configuration.adapter).to receive(:verify).with("animals").and_return(["schema drifted"])
      allow(configuration.adapter).to receive(:verify).with("colors").and_return([])
      expect(problems["animals"]).to eq(["schema drifted"])
    end
  end
end
