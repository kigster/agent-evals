# frozen_string_literal: true

RSpec.describe Agent::Evals::Helper do
  describe ".extract" do
    it { expect(described_class.extract(%w[run --helper x.rb -m a])).to eq([%w[run -m a], "x.rb"]) }
    it { expect(described_class.extract(%w[run --helper=y.rb])).to eq([["run"], "y.rb"]) }
    it { expect(described_class.extract(%w[cases -v])).to eq([%w[cases -v], nil]) }
  end

  describe ".locate" do
    let(:dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(dir) }

    it "prefers the flag" do
      expect(described_class.locate("evals/h.rb", from: dir, env: { "AGENT_EVALS_HELPER" => "other" })).to eq(File.join(dir, "evals", "h.rb"))
    end

    it "then the variable" do
      expect(described_class.locate(nil, from: dir, env: { "AGENT_EVALS_HELPER" => "/abs/h.rb" })).to eq("/abs/h.rb")
    end

    it "then walks up to the nearest evals/eval_helper.rb" do
      FileUtils.mkdir_p(File.join(dir, "evals"))
      FileUtils.mkdir_p(File.join(dir, "a", "b"))
      FileUtils.touch(File.join(dir, "evals", "eval_helper.rb"))
      expect(described_class.locate(nil, from: File.join(dir, "a", "b"), env: {})).to eq(File.join(dir, "evals", "eval_helper.rb"))
    end

    it "is nil when there is none" do
      expect(described_class.locate(nil, from: dir, env: {})).to be_nil
    end
  end

  describe ".load!" do
    it { expect(described_class.load!(nil)).to be(false) }
    it { expect { described_class.load!("/no/such/helper.rb") }.to raise_error(Agent::Evals::Error, /no eval helper at/) }

    it "requires the file" do
      path = File.join(Dir.mktmpdir, "eval_helper.rb")
      File.write(path, "ENV['AGENT_EVALS_HELPER_LOADED'] = '1'\n")
      expect(described_class.load!(path)).to be(true)
      expect(ENV.fetch("AGENT_EVALS_HELPER_LOADED")).to eq("1")
    ensure
      ENV.delete("AGENT_EVALS_HELPER_LOADED")
    end
  end
end
