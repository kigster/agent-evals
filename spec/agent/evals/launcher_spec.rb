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
    it("lists the request types the providers own") { expect(run_cli.gsub(/\s+/, " ")).to include("typesafe (typed questions: noul, choice, score)") }
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
      expect(stderr.string).to include("typesafe/jev-latest refused: needs typesafe; this suite produces prompt")
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
      expect(run_cli).not_to include("typesafe/jev-latest")
      expect(stderr.string.delete("│\n ")).to include('1Warningwasrecordedin')
      expect(File.read(Dir[File.join(log, "log", "*.warnings.*")].first))
        .to eq("typesafe/jev-latest refused: needs typesafe; this suite produces prompt\n")
    end
  end

  context "with run on a refused model alone" do
    let(:dir) { Dir.mktmpdir }
    let(:path) { File.join(dir, "lineup.yml") }
    let(:argv) { ["run", "--local", "--config", path] }

    before { File.write(path, "request_types: [prompt]\ndirect:\n  typesafe:\n    - model: jev-latest\n") }

    after { FileUtils.remove_entry(dir) }

    it "stops with the refusal, before anything is set up" do
      run_cli
      expect(stderr.string).to include("no admitted models: typesafe/jev-latest refused: needs typesafe; this suite produces prompt")
      expect(runtime).not_to have_received(:setup!)
      expect(kernel).to have_received(:exit).with(1)
    end
  end

  context "with run on a refused model and an admitted one" do
    let(:argv) { %w[run -d colors -c clear/001 --local] }
    let(:log) { Dir.mktmpdir }

    before { allow(Dry::CLI::UI::Invocation).to receive(:root).and_return(log) }

    after { FileUtils.remove_entry(log) }

    it "runs the admitted one and records the refusal" do
      expect(run_cli).to include("fake/echo", "fake/parrot").and(satisfy { !it.include?("typesafe") })
      expect(File.read(Dir[File.join(log, "log", "*.warnings.*")].first)).to include("typesafe/jev-latest refused")
    end
  end

  context "with run and a lineup naming an unknown direct provider" do
    let(:dir) { Dir.mktmpdir }
    let(:path) { File.join(dir, "lineup.yml") }
    let(:argv) { ["run", "--local", "-n", "--config", path] }

    before { File.write(path, "request_types: [prompt]\ndirect:\n  ollama:\n    - model: llama3\n") }

    after { FileUtils.remove_entry(dir) }

    it { run_cli && expect(stderr.string).to(include("#{path}: unknown provider \"ollama\" under direct:; known: typesafe")) }
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

    it "runs, sets the runtime up without a remote tracker, and reports" do
      expect(run_cli).to include("fake/one", "vague/001", "100.0%", "field_accuracy")
      expect(runtime).to have_received(:setup!).with(providers: [configuration.providers.for("fake/one")], tracker: nil)
    end
  end

  context "with run over two datasets" do
    let(:argv) { %w[run -m fake/one -d colors,animals -c clear/001 --local] }

    it { expect(run_cli).to include("fake/one effort=default t=0.2 [colors]", "fake/one effort=default t=0.2 [animals]", "tok_in") }
  end

  context "with run writing its report to a file" do
    let(:dir) { Dir.mktmpdir }
    let(:path) { File.join(dir, "report.log") }
    let(:argv) { ["run", "-m", "fake/one,fake/two", "-c", "clear/001", "--local", "--scores", "-o", path] }

    after { FileUtils.remove_entry(dir) }

    it "keeps the breakdowns off the screen" do
      expect(run_cli).not_to include("diagnostics")
    end

    it "keeps the leaderboard, glossary and scores on the screen" do
      expect(run_cli).to include("restraint", "Description", "url")
    end

    it "writes all of it to the file, in color, ending with the time" do
      run_cli
      expect(File.read(path)).to include("diagnostics", "Description", "url", "\e[1m").and(match(/Closed at .+\n\z/))
    end
  end

  context "with compare writing an HTML report" do
    let(:dir) { Dir.mktmpdir }
    let(:path) { File.join(dir, "report.html") }
    let(:argv) { ["compare", "--format", "html", "-m", "fake/echo", "-d", "colors", "--local", "--no-open", "-o", path] }

    before { allow(Dry::CLI::UI::Invocation).to receive(:root).and_return(dir) }

    after { FileUtils.remove_entry(dir) }

    it "writes the case results as an HTML artifact and reports its path" do
      run_cli

      expect(stderr.string).to include(path)
      expect(File.read(path)).to include(
        "<!doctype html>",
        "Global standings",
        "clear/001",
        "field_accuracy",
        '<th>Provider</th><th>Model</th><th>Effort</th><th>Temperature</th>',
        'table class="sortable"',
        'table class="sortable standings-table"',
        'aria-sort',
        'max-width: 1520px',
        'overscroll-behavior-inline: contain',
        '<th><span>Weighted</span><span>score</span></th>',
        '<th><span>Primary score</span><span>(field_accuracy)</span></th>',
        '<th class="standings-bar"><span>Score</span><span>bar</span></th>',
        '.standings-table .standings-bar { min-width: 300px; }',
        'class="provider">fake',
        'class="model-id">echo'
      )
    end

    it "does not print the TUI leaderboard" do
      expect(run_cli).not_to include("Best value:", "Description")
    end

    context "without an explicit report path" do
      let(:argv) { ["compare", "--format", "html", "-m", "fake/echo", "-d", "colors", "--local", "--no-open"] }

      it "writes the timestamped HTML report under log/" do
        run_cli

        report_path = Dir[File.join(dir, "log", "*.html")].fetch(0)
        expect(File.read(report_path)).to include("<!doctype html>", "clear/001")
        expect(stderr.string).to include("HTML report written to")
      end
    end
  end

  context "with compare writing a JSON report" do
    let(:dir) { Dir.mktmpdir }
    let(:path) { File.join(dir, "results.json") }
    let(:argv) { ["compare", "--format", "json", "-m", "fake/echo", "-d", "colors", "-e", "high", "-t", "0.2", "--local", "--no-open", "-o", path] }

    before { allow(Dry::CLI::UI::Invocation).to receive(:root).and_return(dir) }

    after { FileUtils.remove_entry(dir) }

    it "writes a reusable JSON report with case inputs and model outputs" do
      run_cli
      document = JSON.parse(File.read(path))

      expect(document).to include("format" => "agent-evals-report", "version" => 1)
      expect(document.dig("summaries", 0, "results", 0)).to include("case", "reply", "score")
      expect(document.dig("summaries", 0, "results", 0, "case")).to include("input", "expected")
      expect(document.dig("summaries", 0, "results", 0, "reply")).to include("output", "raw")
      expect(stderr.string).to include("JSON report written to")
    end
  end

  context "with render of a saved JSON report" do
    let(:dir) { Dir.mktmpdir }
    let(:json_path) { File.join(dir, "results.json") }
    let(:html_path) { File.join(dir, "report.html") }
    let(:argv) { ["render", json_path, "-o", html_path] }
    let(:render_runtime) { instance_double(Agent::Evals::Runtime, setup!: nil, browse: true) }

    before do
      allow(Dry::CLI::UI::Invocation).to receive(:root).and_return(dir)
      described_class.new(["compare", "--format", "json", "-m", "fake/echo", "-d", "colors", "-e", "high", "-t", "0.2", "--local", "--no-open", "-o", json_path], StringIO.new, StringIO.new, StringIO.new, kernel).execute!
    end

    after { FileUtils.remove_entry(dir) }

    it "renders the saved run without calling a model" do
      allow(configuration).to receive(:runtime).and_return(render_runtime)
      run_cli
      expect(stderr.string).to include("HTML report written to")
      expect(File.read(html_path)).to include("<!doctype html>", "clear/001", "clear/002", "(high, t=0.2)", ".standings-settings { color: var(--text);")
      expect(render_runtime).not_to have_received(:setup!)
    end
  end

  context "with compare writing an HTML report to stdout" do
    let(:argv) { ["compare", "--format", "html", "-m", "fake/echo", "-d", "colors", "--local", "--no-open", "-o", "-"] }

    it "writes the standalone document to stdout without a file path message" do
      expect(run_cli).to start_with("<!doctype html>")
      expect(stderr.string).not_to include("HTML report written to")
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

  describe "experiments at once" do
    let(:concurrent) { [] }

    before do
      allow(Etc).to receive(:nprocessors).and_return(3)
      allow(Agent::Evals::CLI::ProgressBars).to receive(:for).and_wrap_original do |build, *args, **options|
        build.call(*args, **options).tap do |bars|
          allow(bars).to receive(:run).and_wrap_original do |original, *rest, **kwargs, &block|
            concurrent << kwargs[:concurrent]
            original.call(*rest, **kwargs, &block)
          end
        end
      end
    end

    context "with run and no -j" do
      let(:argv) { %w[run -d colors -c clear/001 --local] }

      it("runs one per CPU") { run_cli && expect(concurrent).to(eq([3])) }
    end

    context "with compare and no -j" do
      let(:argv) { %w[compare -c clear/001 --local] }

      it("runs one per CPU") { run_cli && expect(concurrent).to(eq([3])) }
    end

    context "with run -j 1" do
      let(:argv) { %w[run -d colors -c clear/001 --local -j 1] }

      it("runs them one at a time") { run_cli && expect(concurrent).to(eq([1])) }
    end

    context "with compare --concurrency 0" do
      let(:argv) { %w[compare -c clear/001 --local --concurrency 0] }

      it("runs them all together") { run_cli && expect(concurrent).to(eq([true])) }
    end

    context "with a -j that is not a number" do
      let(:argv) { %w[run -d colors -c clear/001 --local -j many] }

      it "exits 1 and says why, before anything runs" do
        run_cli
        expect(kernel).to have_received(:exit).with(1)
        expect(stderr.string).to include('--concurrency must be a whole number, got "many"')
        expect(concurrent).to be_empty
      end
    end

    context "with a negative -j" do
      let(:argv) { %w[run -d colors -c clear/001 --local -j -2] }

      it "exits 1 and says why" do
        run_cli
        expect(kernel).to have_received(:exit).with(1)
        expect(stderr.string).to include("--concurrency must be 0 or more, got -2")
      end
    end
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

  context "with a lineup that sets weights" do
    let(:dir) { Dir.mktmpdir }
    let(:lineup) { File.join(dir, "lineup.yml") }
    let(:weights) { "field_accuracy: 0.7\n    cost: -0.2\n    time: -0.1\n    errors: -0.1\n" }
    let(:argv) { ["compare", "--local", "--no-open", "-m", "fake/echo,fake/parrot", "--config", lineup] }

    before { File.write(lineup, "request_types: [prompt]\nweighted_score:\n  weights:\n    #{weights}") }
    after { FileUtils.remove_entry(dir) }

    it "adds the column, the winners and the formula" do
      expect(run_cli).to include("wscore", "Best wscore", "best wscore overall", "Σ(|weight| × goodness)")
    end

    context "when a weight names tokens" do
      let(:weights) { "tok_in: -1\n" }

      it "refuses it, with no experiment run" do
        run_cli
        expect(stderr.string).to include("unknown columns tok_in")
        expect(stdout.string).not_to include("best value")
      end
    end
  end

  context "with a run in color" do
    let(:argv) { %w[compare --local --no-open -m fake/echo,fake/parrot -d colors] }

    before { allow(Pastel).to(receive(:new).and_wrap_original { |original, **options| original.call(**options, enabled: true) }) }

    it "labels the value and draws the model last, in a bright color" do
      expect(run_cli).to match(%r{Best value.*\[colors\] +effort=default +field_accuracy=100\.0% +\$0\.\d+ +(\e\[9[1-7]m)?fake/(echo|parrot)}m)
    end
  end

  context "with a metric named like one of the gem's columns" do
    let(:argv) { %w[compare --local --no-open -m fake/echo -d colors] }

    before do
      metric = Agent::Evals::Metric.new(name: "score", description: "The scorer's own score.", primary: true)
      allow(configuration.scorer).to receive(:metrics).and_return([metric])
    end

    it "lists it once in the glossary" do
      expect(run_cli.scan(/^│ score +│ (.{10})/).flatten).to eq(["The scorer"])
    end
  end

  context "with compare over two datasets, by default" do
    let(:argv) { %w[compare --local --no-open -m fake/one] }

    it "prints the contenders' totals for each case variant" do
      expect(run_cli).to match(/^\[clear\]\n┌.*│ model .*^\[vague\]\n┌.*│ model /m)
    end

    it "leaves out every experiment by score" do
      expect(run_cli).not_to include('│ url ')
    end

    it "ends on the conclusions, the overall ones last" do
      lines = run_cli.strip.lines
      expect(lines.last).to start_with("best value overall")
      expect(lines[-2]).to include("[colors]")
    end
  end

  context "with compare over one dataset's two variants" do
    let(:argv) { %w[compare --local --no-open -m fake/one -d colors] }

    it("still compares the variants") { expect(run_cli).to match(/^\[clear\]\n.*^\[vague\]\n/m) }
    it("has no overall conclusions") { expect(run_cli).not_to include("best value overall") }
  end

  context "with one variant of one dataset" do
    let(:argv) { %w[compare --local --no-open -m fake/one -d colors -c clear] }

    it("leaves the leaderboard to say it") { expect(run_cli).not_to include("[clear]\n") }
  end

  context "with --scores" do
    let(:argv) { %w[compare --local --no-open -m fake/one --scores] }

    it("prints every experiment by score, before the conclusions") { expect(run_cli).to match(/│ url .*Best value/m) }
  end

  context "with a lineup that sets no weights" do
    let(:argv) { %w[compare --local --no-open -m fake/echo] }

    it("leaves the leaderboard as it was") { expect(run_cli).not_to include("wscore") }
  end

  context "with run and another lineup" do
    let(:dir) { Dir.mktmpdir }
    let(:argv) { ["run", "--local", "-n", "--config", File.join(dir, "lineup.yml")] }

    after { FileUtils.remove_entry(dir) }

    it "reads it" do
      File.write(File.join(dir, "lineup.yml"), "request_types: [prompt]\nvendors:\n  fake:\n    - model: other\n")
      expect(run_cli).to include("fake/other")
    end

    context "when given as -C" do
      let(:argv) { ["run", "--local", "-n", "-C", File.join(dir, "lineup.yml")] }

      it "reads it" do
        File.write(File.join(dir, "lineup.yml"), "request_types: [prompt]\nvendors:\n  fake:\n    - model: other\n")
        expect(run_cli).to include("fake/other")
      end
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

  context "with a config-only suite" do
    let(:argv) { ["cases"] }
    let(:fresh) { Agent::Evals::Configuration.new }

    before { allow(Agent::Evals).to receive(:configuration).and_return(fresh) }

    def run_from_suite
      Dir.chdir(CONFIG_ONLY_SUITE) { run_cli }
    end

    it "finds the config upward, loads the Ruby it names, and lists the cases" do
      expect(run_from_suite).to include("colors", "3/3 answered")
      expect(fresh).to have_attributes(name: "config_only_suite", root: File.join(CONFIG_ONLY_SUITE, "evals"))
      expect(fresh.adapter).to be_a(ToySuite::Evals::Adapter)
    end

    context "when running a model" do
      let(:argv) { %w[run --local -d colors -c clear/001 --no-open] }

      # toy_suite/evals registers the fake provider when first required, which
      # happened on the spec run's own configuration; a fresh process would get it.
      before do
        allow(fresh).to receive(:runtime).and_return(runtime)
        fresh.provider Agent::Evals::Testing::FakeProvider.new
      end

      it { expect(run_from_suite).to include("fake/echo", "100.0%") }
    end
  end

  context "without a suite" do
    let(:argv) { ["cases"] }

    before { allow(Agent::Evals).to receive(:configuration).and_return(Agent::Evals::Configuration.new) }

    it { run_cli && expect(stderr.string).to(include("no suite is configured")) }
  end

  context "with a remote tracker" do
    let(:argv) { %w[run -m fake/one -d colors -c clear/001 --tracker recording-tracker --scores] }
    let(:opened) { true }

    before do
      configuration.trackers.register(RecordingTracker)
      allow(RecordingTracker).to(receive(:new).and_wrap_original { |m, **kw| m.call(url: "https://example.com/exp", **kw) })
      allow(runtime).to receive(:browse).and_return(opened)
    end

    it "checks the tracker in setup, shows the link and opens it" do
      expect(run_cli).to include("https://example.com/exp")
      expect(runtime).to have_received(:setup!).with(hash_including(tracker: RecordingTracker))
      expect(runtime).to have_received(:browse).with("https://example.com/exp")
      expect(RecordingTracker).to have_received(:new).with(hash_including(suite: "toy", project: "toy-suite", options: {}))
    end

    context "when the browser cannot be opened" do
      let(:opened) { false }

      it { run_cli && expect(stderr.string).to(include("could not open")) }
    end

    context "with --no-open" do
      let(:argv) { %w[run -m fake/one -d colors -c clear/001 --tracker recording-tracker --no-open] }

      it "leaves the browser alone" do
        run_cli
        expect(runtime).not_to have_received(:browse)
      end
    end

    context "with --verbose" do
      let(:argv) { %w[run -m fake/one -d colors -c clear/001 --tracker recording-tracker -v] }

      it { run_cli && expect(stderr.string).to(include("tracker: recording-tracker, because --tracker")) }
    end
  end

  context "with an unknown tracker" do
    let(:argv) { %w[run -m fake/one --tracker weave] }

    it { run_cli && expect(stderr.string).to(include('no tracker named "weave"')) }
  end

  context "with two trackers in the environment and none chosen" do
    let(:argv) { %w[run -m fake/one -d colors -c clear/001] }

    around do |example|
      ENV["BRAINTRUST_API_KEY"] = "k"
      ENV["LOGFIRE_TOKEN"] = "t"
      example.run
    ensure
      ENV.delete("BRAINTRUST_API_KEY")
      ENV.delete("LOGFIRE_TOKEN")
    end

    it { run_cli && expect(stderr.string).to(include("more than one tracker is configured in the environment")) }

    context "with --local" do
      let(:argv) { %w[run -m fake/one -d colors -c clear/001 --local] }

      it { expect(run_cli).to include("100.0%") }
    end
  end
end
