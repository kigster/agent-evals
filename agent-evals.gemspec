# frozen_string_literal: true

require_relative "lib/agent/evals/version"

Gem::Specification.new do |spec|
  spec.name = "agent-evals"
  spec.version = Agent::Evals::VERSION
  spec.authors = ["Konstantin Gredeskoul"]
  spec.email = ["kigster@gmail.com"]

  spec.summary = "A generic evaluation runner for LLM-backed code: adapters run, scorers score, the CLI reports"
  spec.description =
    "Runs a suite of cases against one or more models through an adapter the consumer writes, scores each " \
    "reply with a scorer the consumer writes, and prints leaderboards, per-case breakdowns and Braintrust " \
    "experiments. The gem knows nothing about what is being evaluated: it owns discovery, the model lineup, " \
    "providers, parallel execution, reporting and the command line."

  spec.homepage = "https://github.com/kigster/agent-evals"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Dir-based (not `git ls-files`) so the gemspec evaluates in contexts
  # without git, such as a path gem vendored into a slim Docker image.
  spec.files = Dir.chdir(__dir__) do
    Dir.glob("{lib,exe}/**/*", File::FNM_DOTMATCH).select { |f| File.file?(f) } +
      %w[README.md CHANGELOG.md LICENSE.txt].select { |f| File.exist?(f) }
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "dotenv", "~> 3.2"
  spec.add_dependency "dry-cli", "~> 1.4"
  spec.add_dependency "dry-cli-autocomplete", "~> 0.6"
  spec.add_dependency "dry-cli-help", "~> 0.6"
  spec.add_dependency "dry-cli-ui", "~> 0.7"
  spec.add_dependency "zeitwerk", "~> 2.8"

  # Already in the bundle through dry-cli-ui; named because the CLI draws its
  # own right-aligned tables and colored status boxes with them.
  spec.add_dependency "pastel", "~> 0.8"
  spec.add_dependency "tty-box", "~> 0.7"
  spec.add_dependency "tty-table", "~> 0.12"

  # Bundled gems since Ruby 3.5 are not loadable under Bundler unless declared;
  # Warnings builds a Logger, so a consumer without this line would raise LoadError.
  spec.add_dependency "logger", "~> 1.6"

  # ruby_llm and braintrust are deliberately NOT runtime dependencies: a suite
  # that brings its own transport, or scores locally, never loads them. The
  # commands that need one require it lazily and name the gem when it is missing.
end
