# frozen_string_literal: true

# The executable, as a user runs it: a fresh process in the toy suite's
# directory, with no --helper, finding evals/eval_helper.rb on its own. These
# do not count toward coverage; the Launcher specs do that in-process.
RSpec.describe "exe/llm-evals" do
  let(:exe) { File.expand_path("../../../exe/llm-evals", __dir__) }

  def run_exe(*, from: TOY_SUITE, env: {})
    Open3.capture3({ "BUNDLE_GEMFILE" => File.expand_path("../../../Gemfile", __dir__), "NO_COLOR" => "1", **env },
      "bundle",
      "exec",
      exe,
      *,
      chdir: from)
  end

  it "ships evals as a byte-identical regular file" do
    twin = File.expand_path("../../../exe/evals", __dir__)
    expect(File.symlink?(twin)).to be(false)
    expect(File.read(twin)).to eq(File.read(exe))
    expect(File.executable?(twin)).to be(true)
  end

  it "prints help from a directory without a suite" do
    stdout, _stderr, status = run_exe("--help", from: Dir.tmpdir)
    expect(status.exitstatus).to eq(0)
    expect(stdout).to include("run", "compare", "cases", "verify")
  end

  it "lists the cases" do
    stdout, _stderr, status = run_exe("cases")
    expect(status.exitstatus).to eq(0)
    expect(stdout).to include("colors", "vague/002", "answered")
  end

  it "verifies the suite" do
    stdout, _stderr, status = run_exe("verify")
    expect(status.exitstatus).to eq(0)
    expect(stdout).to include("8 cases verified")
  end

  it "previews a run" do
    stdout, _stderr, status = run_exe("run", "--local", "-n")
    expect(status.exitstatus).to eq(0)
    expect(stdout).to include("fake/echo", "fake/parrot")
  end

  it "runs the fake model end to end" do
    stdout, stderr, status = run_exe("run", "--local", "-m", "fake/echo", "-d", "colors", "--no-open", "--scores")
    expect(status.exitstatus).to eq(0), stderr
    expect(stdout).to include("fake/echo", "colors", "100.0%", "field_accuracy", "url")
    expect(stderr).to include("Running 1 experiment")
  end

  it "runs a config-only suite, with the Ruby it names on the load path" do
    stdout, stderr, status = run_exe("verify", from: CONFIG_ONLY_SUITE, env: { "RUBYLIB" => File.join(TOY_SUITE, "lib") })
    expect(status.exitstatus).to eq(0), stderr
    expect(stdout).to include("8 cases verified")
  end

  it "says what is missing without a suite" do
    _stdout, stderr, status = run_exe("cases", from: Dir.tmpdir)
    expect(status.exitstatus).to eq(1)
    expect(stderr).to include("no suite is configured")
  end
end
