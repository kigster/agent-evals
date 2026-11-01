# frozen_string_literal: true

# A library the gem requires at load time must be a declared runtime
# dependency. Bundled gems (logger, ostruct, prism since Ruby 3.5/4.1) reach a
# development bundle through other gems, so the suite stays green while every
# consumer's `require "agent/evals"` raises LoadError.
RSpec.describe "agent-evals.gemspec" do
  let(:gemspec) { Gem::Specification.load(File.expand_path("../../../agent-evals.gemspec", __dir__)) }
  let(:runtime) { gemspec.runtime_dependencies.map(&:name) }
  let(:required) do
    Dir[File.expand_path("../../../lib/**/*.rb", __dir__)].flat_map { File.read(it).scan(%r{^\s*require "([^"/]+)(?:/[^"]*)?"}).flatten }.uniq
  end
  let(:bundled) { Gem::BUNDLED_GEMS::SINCE.keys }

  it "declares every bundled gem lib/ requires" do
    expect(runtime).to include(*(required & bundled))
  end

  it { expect(runtime).to include("logger", "dry-cli", "dry-cli-ui", "zeitwerk", "dotenv", "ruby_llm") }
  it { expect(runtime).not_to include("braintrust") }
  it { expect(gemspec.executables).to eq(["aeva", "agent-evals"]) }
end
