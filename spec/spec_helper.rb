# frozen_string_literal: true

require "simplecov"
require "coverage/badge"
require "fileutils"

SimpleCov.start do
  # `cover` (replacing the deprecated `track_files`) is what makes the number
  # mean anything: without it SimpleCov only counts files some example happened
  # to load, so a library nobody requires reports 100% of nothing. With it, an
  # untested file counts as 0% AND the report is restricted to this pattern —
  # which is also why `spec/` and `bin/` need no separate exclusion below.
  root File.expand_path("..", __dir__)
  cover "lib/**/*.rb"

  skip "/spec/"

  enable_coverage :branch

  self.formatters = [
    SimpleCov::Formatter::HTMLFormatter,
    Coverage::Badge::Formatter
  ]

  minimum_coverage line: 95
end

BADGE_DIR = File.expand_path("../docs/badges", __dir__)

SimpleCov.at_exit do
  SimpleCov.result.format!
  # rubocop: disable-next RSpec/Output
  puts "Coverage: #{SimpleCov.result.covered_percent.round(2)}%"
  FileUtils.mkdir_p(BADGE_DIR)
  FileUtils.mv(File.join(SimpleCov.coverage_path, "badge.svg"), File.join(BADGE_DIR, "coverage-badge.svg"))
end

# Assertions test content on every machine; the colored path is covered by
# stubbing `tty?` where a spec means to.
ENV["NO_COLOR"] = "1"

require "rspec/its"
require "stringio"
require "tmpdir"
require "open3"
require "llm/evals"

# The toy suite is the configured suite for the whole run: one adapter, one
# scorer, one fake provider. Specs that need another build a Configuration
# of their own rather than reconfiguring the global one.
TOY_SUITE = File.expand_path("fixtures/toy_suite", __dir__)
TOY_HELPER = File.join(TOY_SUITE, "evals", "eval_helper.rb")
$LOAD_PATH.unshift(File.join(TOY_SUITE, "lib"))
CONFIG_ONLY_SUITE = File.expand_path("fixtures/config_only_suite", __dir__)

require TOY_HELPER

Dir[File.join(__dir__, "support", "*.rb")].each { require it }

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { it.syntax = :expect }
  config.order = :random
  config.example_status_persistence_file_path = ".rspec_status"
  Kernel.srand config.seed
end
