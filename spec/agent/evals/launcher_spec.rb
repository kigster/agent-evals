# frozen_string_literal: true

RSpec.describe Agent::Evals::Launcher do
  subject(:status) { described_class.new(argv, StringIO.new, stdout, stderr, kernel).execute! }

  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:kernel) { class_double(Kernel, exit: nil) }
  let(:configuration) { Agent::Evals.configuration }
  let(:runtime) { instance_double(Agent::Evals::Runtime, setup!: nil, browse: true) }

  before { allow(configuration).to receive(:runtime).and_return(runtime) }

  def run_cli
    status
    stdout.string
  end

  context "with no arguments" do
    let(:argv) { [] }

    it("prints help, titled after the suite") { expect(run_cli).to include("compare", "agent-evals (toy)", "The toy suite") }
    it("exits 0") { run_cli && expect(kernel).to(have_received(:exit).with(0)) }
  end

  context "with version" do
    let(:argv) { ["version"] }

    it { expect(run_cli).to eq("#{Agent::Evals::VERSION}\n") }
  end

  context "with completion" do
    let(:argv) { %w[completion zsh] }

    it { expect(run_cli).to include("#compdef agent-evals") }
  end

  context "with cases" do
    let(:argv) { ["cases"] }

    it { expect(run_cli).to include("colors", "vague/002", "1/3 answered", "animals") }
  end

  context "with cases and a refused lineup entry" do
    let(:argv) { ["cases"] }

    it "names it on stderr" do
      run_cli
      expect(stderr.string).to include("typesafe-api/jev-latest refused: needs typesafe; this suite produces prompt")
    end
  end

  context "with cases of one dataset" do
    let(:argv) { %w[cases -d colors] }

    it { expect(run_cli).to include("colors").and(satisfy { !it.include?("animals") }) }
  end

  context "with cases and a scorer that has no summary" do
    let(:argv) { ["cases"] }

    before { allow(configuration.scorer).to receive(:summary).and_return(nil) }

    it { expect(run_cli).to include("3 fields") }
  end

  context "with verify" do
    let(:argv) { ["verify"] }

    it { expect(run_cli).to include("8 cases verified across animals, colors") }
  end

  context "with verify over a broken suite" do
    let(:argv) { ["verify"] }

    before { allow(Agent::Evals::Verify).to receive(:new).and_return(instance_double(Agent::Evals::Verify, problems: { "colors/clear/001" => ["bad"] })) }

    it "exits 1 and names the case" do
      run_cli
      expect(kernel).to have_received(:exit).with(1)
      expect(stderr.string).to include("colors/clear/001: bad", "1 case(s) failed verification")
    end
  end

  context "with run --dry-run" do
    let(:argv) { %w[run -n] }
    let(:log) { Dir.mktmpdir }

    before { allow(Dry::CLI::UI::Invocation).to receive(:root).and_return(log) }

    after { FileUtils.remove_entry(log) }

    it "prints the matrix and calls nothing" do
      expect(run_cli).to include("max_tokens", "fake/parrot", "animals", "colors")
      expect(runtime).not_to have_received(:setup!)
    end

    it "leaves the refused contender out of the matrix and names it in the warnings" do
      expect(run_cli).not_to include("typesafe-api/jev-latest")
      expect(stderr.string.delete("│\n ")).to include('1Warningwasrecordedin')
      expect(File.read(Dir[File.join(log, "log", "*.warnings.*")].first))
        .to eq("typesafe-api/jev-latest refused: needs typesafe; this suite produces prompt\n")
    end
  end

  context "with run on a refused model alone" do
    let(:argv) { %w[run -m typesafe-api/jev-latest --local] }

    it "stops with the refusal, before anything is set up" do
      run_cli
      expect(stderr.string).to include("no admitted models: typesafe-api/jev-latest refused: needs typesafe; this suite produces prompt")
      expect(runtime).not_to have_received(:setup!)
      expect(kernel).to have_received(:exit).with(1)
    end
  end

  context "with run on a refused model and an admitted one" do
    let(:argv) { %w[run -m fake/one,typesafe-api/jev-latest -d colors -c clear/001 --local] }
    let(:log) { Dir.mktmpdir }

    before { allow(Dry::CLI::UI::Invocation).to receive(:root).and_return(log) }

    after { FileUtils.remove_entry(log) }

    it "runs the admitted one and records the refusal" do
      expect(run_cli).to include("fake/one").and(satisfy { !it.include?("typesafe-api") })
      expect(File.read(Dir[File.join(log, "log", "*.warnings.*")].first)).to include("typesafe-api/jev-latest refused")
    end
  end

  context "with run and a lineup without request_types" do
    let(:dir) { Dir.mktmpdir }
    let(:path) { File.join(dir, "lineup.yml") }
    let(:argv) { ["run", "--local", "-n", "--config", path] }

    before { File.write(path, "vendors:\n  fake:\n    - model: other\n") }

    after { FileUtils.remove_entry(dir) }

    it { run_cli && expect(stderr.string).to(include("#{path}: request_types is required")) }
  end

  context "with run on one dataset" do
    let(:argv) { %w[run -m fake/one -d colors -c vague --local] }

    it "runs, sets the runtime up without Braintrust, and reports" do
      expect(run_cli).to include("fake/one", "vague/001", "100.0%", "field_accuracy")
      expect(runtime).to have_received(:setup!).with(providers: [configuration.providers.for("fake/one")], braintrust: false)
    end
  end

  context "with run over two datasets" do
    let(:argv) { %w[run -m fake/one -d colors,animals -c clear/001 --local] }

    it { expect(run_cli).to include("fake/one effort=default t=0.2 [colors]", "fake/one effort=default t=0.2 [animals]", "tok_in") }
  end

  context "with run writing its report to a file" do
    let(:dir) { Dir.mktmpdir }
    let(:path) { File.join(dir, "report.log") }
    let(:argv) { ["run", "-m", "fake/one,fake/two", "-c", "clear/001", "--local", "-o", path] }

    after { FileUtils.remove_entry(dir) }

    it "keeps the breakdowns off the screen" do
      expect(run_cli).not_to include("diagnostics")
    end

    it "keeps the leaderboard, glossary and scores on the screen" do
      expect(run_cli).to include("restraint", "Description", "braintrust_url")
    end

    it "writes all of it to the file, in color, ending with the time" do
      run_cli
      expect(File.read(path)).to include("diagnostics", "Description", "braintrust_url", "\e[1m").and(match(/Closed at .+\n\z/))
    end
  end

  context "with run holding back its warnings" do
    let(:argv) { %w[run -m fake/one -c clear/001 --local] }
    let(:log) { Dir.mktmpdir }

    before do
      allow(Dry::CLI::UI::Invocation).to receive(:root).and_return(log)
      allow(configuration.adapter).to receive(:call).and_raise(RuntimeError, "out of credits")
    end

    after { FileUtils.remove_entry(log) }

    it "prints only how many, and where" do
      run_cli
      expect(stderr.string.delete("│\n ")).to match(/2Warningswererecordedin.*run\.warnings\.\d{4}-\d\d-\d\d\.\d{6}\.log/)
      expect(stderr.string).not_to include("out of credits")
    end

    it "saves them" do
      run_cli
      expect(File.read(Dir[File.join(log, "log", "*.warnings.*")].first)).to include("[fake/one effort=default t=0.2 [animals]]", "out of credits")
    end
  end

  context "with run showing a wrong field" do
    let(:argv) { %w[run -m fake/one -d colors -c clear/001 --local] }

    before do
      provider = Agent::Evals::Testing::FakeProvider.new(wrong: { "clear/001" => { "trim" => "pink" } })
      allow(configuration.providers).to receive(:for).and_return(provider)
    end

    it { expect(run_cli).to include('trim: want="white" got="pink"', "66.7%") }
  end

  context "with run and a failed case" do
    let(:argv) { %w[run -m fake/one -d colors -c clear/001 --local] }

    before do
      allow(Dry::CLI::UI::Invocation).to receive(:root).and_return(Dir.mktmpdir)
      allow(configuration.adapter).to receive(:call).and_raise(IOError, "closed stream")
    end

    it { expect(run_cli).to include("IOError: closed stream") }
  end

  context "with compare over two datasets" do
    let(:argv) { %w[compare -m fake/a -d colors,animals -c clear/001 --local] }

    it { expect(run_cli).to include("colors", "animals", "best value overall", "$0.0020") }
  end

  context "with compare over an unknown dataset" do
    let(:argv) { %w[compare -n -d nope] }

    it { run_cli && expect(stderr.string).to(include('no dataset "nope"')) }
  end

  context "with compare --dry-run" do
    let(:argv) { %w[compare -n] }

    it { expect(run_cli).to include("max_tokens", "fake/echo", "low") }
  end

  context "with compare over explicit models" do
    let(:argv) { %w[compare -m fake/a,fake/b -c clear/001 -t 0 --local --concurrency 1] }

    it { expect(run_cli).to include("fake/a", "fake/b", "Term", "Description", "field_accuracy") }
  end

  context "with run and no model" do
    let(:argv) { %w[run -d colors -c clear --local] }

    it "runs every model in .agent-eval.config.yml, each with its breakdown" do
      expect(run_cli).to include("fake/echo effort=low t=0.2 [colors]", "fake/parrot effort=default t=0.2 [colors]", "clear/002")
    end
  end

  context "with run and the flags" do
    let(:argv) { %w[run -m fake/one -c clear/001 -e low -t default --max-tokens 100 -p 1 --local] }

    it "builds the model from the flags" do
      expect(run_cli).to include("fake/one effort=low t=default")
    end
  end

  context "with run and an unknown case" do
    let(:argv) { %w[run -m fake/one -c 99 --local] }

    it { run_cli && expect(stderr.string).to(include("no cases match 99")) }
  end

  context "with run and an unserved model" do
    let(:argv) { %w[run -m fake/one --local] }

    before { allow(configuration.providers).to receive(:for).and_raise(Agent::Evals::Error, "no provider serves") }

    it { run_cli && expect(stderr.string).to(include("no provider serves")) }
  end

  context "with run and another lineup" do
    let(:dir) { Dir.mktmpdir }
    let(:argv) { ["run", "--local", "-n", "--config", File.join(dir, "lineup.yml")] }

    after { FileUtils.remove_entry(dir) }

    it "reads it" do
      File.write(File.join(dir, "lineup.yml"), "request_types: [prompt]\nvendors:\n  fake:\n    - model: other\n")
      expect(run_cli).to include("fake/other")
    end

    it "fails on an empty one" do
      run_cli
      expect(stderr.string).to include("no models: list some under vendors")
    end
  end

  context "with --verbose and a failure" do
    let(:argv) { %w[run -m fake/one -c 99 --local -v] }

    it { run_cli && expect(stderr.string).to(include("launcher.rb")) }
  end

  context "with --helper" do
    let(:dir) { Dir.mktmpdir }
    let(:helper) { File.join(dir, "eval_helper.rb") }
    let(:argv) { ["version", "--helper", helper] }

    after do
      FileUtils.remove_entry(dir)
      ENV.delete("AGENT_EVALS_FLAG_HELPER")
    end

    it "loads the file before dispatching" do
      File.write(helper, "ENV['AGENT_EVALS_FLAG_HELPER'] = 'yes'\n")
      run_cli
      expect(ENV.fetch("AGENT_EVALS_FLAG_HELPER")).to eq("yes")
    end

    it "fails on a missing one" do
      run_cli
      expect(stderr.string).to include("no eval helper at #{helper}")
    end
  end

  context "without a suite" do
    let(:argv) { ["cases"] }

    before { allow(Agent::Evals).to receive(:configuration).and_return(Agent::Evals::Configuration.new) }

    it { run_cli && expect(stderr.string).to(include("no suite is configured")) }
  end

  context "with a run logged to Braintrust" do
    let(:argv) { %w[run -m fake/one -d colors -c clear/001] }
    let(:summary) do
      Agent::Evals::Experiment::Summary.new(
        model:     Agent::Evals::Testing::FakeModel.new(id: "fake/one"),
        dataset:   "colors",
        name:      "fake/one effort=default t=0.2 [colors]",
        means:     { "field_accuracy" => 1.0, "exact_match" => 1.0, "restraint" => nil, "score" => 1.0 },
        results:   [],
        errors:    [],
        duration:  1.0,
        permalink: "https://example.com/exp",
        usage:     Agent::Evals::Usage.zero
      )
    end
    let(:opened) { true }

    before do
      allow(runtime).to receive(:browse).and_return(opened)
      allow(Agent::Evals::Experiment).to receive(:new).and_return(
        instance_double(Agent::Evals::Experiment, name: "fake", cases: configuration.discovery.cases(dataset: "colors"), run: summary)
      )
    end

    it "sets the runtime up for Braintrust and shows the link" do
      expect(run_cli).to include("https://example.com/exp")
      expect(runtime).to have_received(:setup!).with(hash_including(braintrust: true))
    end

    it "opens the experiment" do
      run_cli
      expect(runtime).to have_received(:browse).with("https://example.com/exp")
    end

    context "when the browser cannot be opened" do
      let(:opened) { false }

      it { run_cli && expect(stderr.string).to(include("could not open")) }
    end

    context "with --no-open" do
      let(:argv) { %w[run -m fake/one -d colors -c clear/001 --no-open] }

      it "leaves the browser alone" do
        run_cli
        expect(runtime).not_to have_received(:browse)
      end
    end
  end
end
