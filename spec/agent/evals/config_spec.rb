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
          typesafe:
            - model: jev-router
        direct:
          typesafe:
            - model: jev-latest
              temperature: [0.5, 0.9]
      YAML
    end

    it "lists vendors first, then direct entries carrying their provider" do
      expect(config.contenders.map { [it.model, it.provider, it.temperature] }.last(3)).to eq(
        [["typesafe/jev-router", nil, 0.5], ["typesafe/jev-latest", :typesafe, 0.5], ["typesafe/jev-latest", :typesafe, 0.9]]
      )
    end

    it "keeps a vendors id and a direct id apart by key" do
      expect(config.contenders.map(&:key).last(2)).to eq(%w[typesafe:typesafe/jev-latest typesafe:typesafe/jev-latest])
      expect(config.contenders[-3]).not_to be_direct
    end

    it "refuses an unknown provider under direct, naming the file" do
      File.write(path, "direct:\n  ollama:\n    - model: llama3\n")
      expect { config.contenders }.to raise_error(Agent::Evals::Error, /#{Regexp.escape(path)}: unknown provider "ollama" under direct:; known: typesafe/)
    end

    its(:project) { is_expected.to eq("p1") }
    its(:defaults) { is_expected.to include("temperature" => 0.5, "effort" => "default", "max_tokens" => 4096) }

    it "expands every effort and temperature" do
      expect(config.contenders.first(5).map { [it.model, it.effort, it.temperature] }).to eq(
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
    it { expect { config.request_types }.to raise_error(Agent::Evals::Error, /#{Regexp.escape(path)}: request_types is required; list one or more of prompt, typesafe/) }
  end

  describe "#tracker and #tracker_options" do
    it "reads one tracker and its section" do
      File.write(path, "tracker: logfire\nlogfire:\n  include_replies: true\n")
      expect(config.tracker).to eq("logfire")
      expect(config.tracker_options("logfire")).to eq("include_replies" => true)
      expect(config.tracker_options("braintrust")).to eq({})
    end

    it { expect(config.tracker).to be_nil }

    it "refuses a list of several" do
      File.write(path, "tracker: [braintrust, logfire]\n")
      expect { config.tracker }.to raise_error(Agent::Evals::Error, /#{Regexp.escape(path)}: tracker: names braintrust, logfire; exactly one remote tracker runs, or none/)
    end
  end

  describe "#score_weights" do
    it "is empty without the section" do
      expect(config.score_weights).to eq({})
    end

    it "reads the weights" do
      File.write(path, "weighted_score:\n  weights:\n    cost: -0.5\n")
      expect(config.score_weights).to eq("cost" => -0.5)
    end

    it "refuses a section without a weights mapping" do
      File.write(path, "weighted_score: 3\n")
      expect { config.score_weights }.to raise_error(Agent::Evals::Error, /needs a weights: mapping/)
    end
  end

  describe "#results" do
    it "provides compatible defaults when the results section is absent" do
      expect(config.results).to have_attributes(autosave: true, display_mode: "tui")
      expect(config.results.destination).to eq(File.expand_path("evals/results", Dir.pwd))
      expect(config.results.temp_dir).to eq(File.expand_path("tmp", Dir.pwd))
    end

    it "reads autosave, directories and display from the config" do
      File.write(path, <<~YAML)
        results:
          autosave: true
          destination: ./custom/results
          temp_dir: ./custom/tmp
          display: browser
      YAML

      expect(config.results).to have_attributes(autosave: true, display_mode: "browser")
      expect(config.results.destination).to eq(File.expand_path("custom/results", Dir.pwd))
      expect(config.results.temp_dir).to eq(File.expand_path("custom/tmp", Dir.pwd))
    end

    it "rejects unsupported display modes" do
      File.write(path, "results:\n  display: terminal\n")

      expect { config.results }.to raise_error(Agent::Evals::Error, /display must be one of none, tui, browser/)
    end

    it "requires autosave to be a boolean" do
      File.write(path, "results:\n  autosave: enabled\n")

      expect { config.results }.to raise_error(Agent::Evals::Error, /autosave must be true or false/)
    end
  end

  describe "#request_types" do
    it "reads the declared types as symbols" do
      File.write(path, "request_types: [prompt, typesafe]\n")
      expect(config.request_types).to eq(%i[prompt typesafe])
    end

    it "refuses an empty list, naming the file" do
      File.write(path, "request_types: []\n")
      expect { config.request_types }.to raise_error(Agent::Evals::Error, /#{Regexp.escape(path)}: request_types is required/)
    end

    it "refuses an unknown type, naming the file" do
      File.write(path, "request_types: [prompt, telepathy]\n")
      expect { config.request_types }.to raise_error(Agent::Evals::Error, /#{Regexp.escape(path)}: unknown request_types telepathy; known: prompt, typesafe/)
    end
  end

  context "with the toy suite's lineup" do
    subject(:config) { Agent::Evals.configuration.lineup }

    it { expect(config.contenders.map(&:model)).to eq(%w[fake/echo fake/echo fake/parrot typesafe/jev-latest]) }
    it { expect(config.contenders.last).to be_direct }
    it { expect(config.request_types).to eq([:prompt]) }
  end
end
