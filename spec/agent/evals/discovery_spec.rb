# frozen_string_literal: true

RSpec.describe Agent::Evals::Discovery do
  subject(:discovery) { Agent::Evals.configuration.discovery }

  its(:datasets) { is_expected.to eq(%w[animals colors]) }
  it { expect(discovery.all.size).to eq(8) }
  it { expect(discovery.cases(dataset: "colors").map(&:id)).to eq(%w[clear/001 clear/002 vague/001 vague/002]) }
  it { expect(discovery.cases(only: ["vague/00"]).map(&:key)).to eq(%w[animals/vague/001 animals/vague/002 colors/vague/001 colors/vague/002]) }
  it { expect(discovery.cases(only: ["colors/clear"]).size).to eq(2) }
  it { expect(discovery.cases(dataset: "animals", only: ["clear/001,clear/002"]).size).to eq(2) }
  it { expect { discovery.cases(dataset: "nope") }.to raise_error(Agent::Evals::Error, /no dataset "nope"; have animals, colors/) }

  it "decodes a case" do
    kase = discovery.cases(dataset: "animals").first
    expect(kase).to have_attributes(dataset: "animals",
      variant: "clear",
      id: "clear/001",
      number: 1,
      input: "Alan Turing keeps two cats and a parrot at home.",
      expected: include("count" => 3))
    expect(kase.path).to end_with("animals/cases/clear/001")
  end

  context "with a layout without numbers or a datasets folder" do
    subject(:discovery) { described_class.new(root: dir, glob: "*/*/input.txt") }

    let(:dir) { Dir.mktmpdir }

    before do
      FileUtils.mkdir_p(File.join(dir, "fruit", "ripe"))
      File.write(File.join(dir, "fruit", "ripe", "input.txt"), "a banana\n")
      File.write(File.join(dir, "fruit", "ripe", "expected.json"), "{\"color\": \"yellow\"}")
      File.write(File.join(dir, "fruit", "ripe", "metadata.json"), "{\"difficulty\": 7, \"source\": \"made up\"}")
      FileUtils.mkdir_p(File.join(dir, "fruit", "raw"))
      File.write(File.join(dir, "fruit", "raw", "input.txt"), "")
      File.write(File.join(dir, "fruit", "raw", "expected.json"), "{nope")
    end

    after { FileUtils.remove_entry(dir) }

    it "takes the first folder as the dataset and the parent as the variant and id" do
      expect(discovery.cases(dataset: "fruit").map { [it.variant, it.id, it.number] }).to eq([["raw", "raw", nil], ["ripe", "ripe", nil]])
    end

    it "merges metadata.json over the decoded metadata" do
      expect(discovery.cases(only: ["ripe"]).first.metadata).to include(difficulty: 7, source: "made up")
    end

    it "notes an unparsable expected.json instead of raising" do
      kase = discovery.cases(only: ["raw"]).first
      expect(kase.expected).to be_nil
      expect(kase.metadata[:expected_error]).to start_with("expected.json is not valid JSON")
    end

    it "notes a missing expected.json" do
      File.delete(File.join(dir, "fruit", "raw", "expected.json"))
      expect(discovery.cases(only: ["raw"]).first.metadata[:expected_error]).to eq("expected.json is missing")
    end
  end
end
