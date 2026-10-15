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
      expect(described_class.locate("evals/h.rb", from: dir, env: { "AGENT_EVALS_HELPER" => "other" }).helper).to eq(File.join(dir, "evals", "h.rb"))
    end

    it "then the variable" do
      expect(described_class.locate(nil, from: dir, env: { "AGENT_EVALS_HELPER" => "/abs/h.rb" }).helper).to eq("/abs/h.rb")
    end

    it "then walks up to the nearest evals/eval_helper.rb, with its config beside it" do
      FileUtils.mkdir_p(File.join(dir, "evals"))
      FileUtils.mkdir_p(File.join(dir, "a", "b"))
      FileUtils.touch(File.join(dir, "evals", "eval_helper.rb"))
      FileUtils.touch(File.join(dir, "evals", ".agent-eval.config.yml"))
      found = described_class.locate(nil, from: File.join(dir, "a", "b"), env: {})
      expect(found).to have_attributes(helper: File.join(dir, "evals", "eval_helper.rb"), config: File.join(dir, "evals", ".agent-eval.config.yml"))
    end

    it "finds a config-only suite, from outside or inside evals/" do
      FileUtils.mkdir_p(File.join(dir, "evals", "datasets"))
      FileUtils.touch(File.join(dir, "evals", ".agent-eval.config.yml"))
      from_outside = described_class.locate(nil, from: dir, env: {})
      from_inside = described_class.locate(nil, from: File.join(dir, "evals", "datasets"), env: {})
      expect([from_outside, from_inside].map(&:config).uniq).to eq([File.join(dir, "evals", ".agent-eval.config.yml")])
      expect(from_outside.helper).to be_nil
    end

    it "is empty when there is none" do
      expect(described_class.locate(nil, from: dir, env: {})).not_to be_any
    end
  end

  describe ".load!" do
    it { expect(described_class.load!(nil)).to be(false) }
    it { expect(described_class.load!(described_class::Found.new)).to be(false) }

    it "roots a fresh configuration at a config-only suite" do
      configuration = Agent::Evals::Configuration.new
      found = described_class::Found.new(config: File.join(CONFIG_ONLY_SUITE, "evals", ".agent-eval.config.yml"))
      expect(described_class.load!(found, configuration: configuration)).to be(true)
      expect(configuration).to have_attributes(root: File.join(CONFIG_ONLY_SUITE, "evals"), name: "config_only_suite")
      expect(configuration.require_suite!.scorer).to be_a(ToySuite::Evals::Scorer)
    end

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
