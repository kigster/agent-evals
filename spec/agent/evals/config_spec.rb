# frozen_string_literal: true

RSpec.describe Agent::Evals::Config do
  subject(:config) { described_class.new(path) }

  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "config.yml") }

  after { FileUtils.remove_entry(dir) }

  context "with vendors, defaults and lists" do
    before do
      File.write(path, <<~YAML)
        project: p1
        defaults:
          temperature: 0.5
        vendors:
          acme:
            - model: big
              effort: [low, high]
              temperature: [0.0, 1.0]
            - model: small
      YAML
    end

    its(:project) { is_expected.to eq("p1") }
    its(:defaults) { is_expected.to include("temperature" => 0.5, "effort" => "default", "max_tokens" => 4096) }

    it "expands every effort and temperature" do
      expect(config.contenders.map { [it.model, it.effort, it.temperature] }).to eq(
        [["acme/big", "low", 0.0], ["acme/big", "low", 1.0], ["acme/big", "high", 0.0], ["acme/big", "high", 1.0],
         ["acme/small", "default", 0.5]]
      )
    end

    it "lets flags beat the file" do
      expect(config.contenders("effort" => "max", "temperature" => nil).map(&:effort).uniq).to eq(["max"])
    end

    it "builds contenders for models given directly" do
      expect(config.contenders_for(["x/y"], "max_tokens" => "100").first).to have_attributes(model: "x/y", max_tokens: 100)
    end
  end

  context "without a file" do
    its(:contenders) { is_expected.to eq([]) }
    its(:project) { is_expected.to be_nil }
  end

  context "with the toy suite's config.yml" do
    subject(:config) { Agent::Evals.configuration.lineup }

    it { expect(config.contenders.map(&:model)).to eq(%w[fake/echo fake/echo fake/parrot]) }
  end
end
