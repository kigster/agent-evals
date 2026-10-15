# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  root File.expand_path("..", __dir__)
  add_filter "/spec/"
  enable_coverage :branch
  minimum_coverage line: 95
end

# Assertions test content on every machine; the colored path is covered by
# stubbing `tty?` where a spec means to.
ENV["NO_COLOR"] = "1"

require "rspec/its"
require "stringio"
require "tmpdir"
require "fileutils"
require "open3"
require "agent/evals"

# The toy suite is the configured suite for the whole run: one adapter, one
# scorer, one fake provider. Specs that need another build a Configuration
# of their own rather than reconfiguring the global one.
TOY_SUITE = File.expand_path("fixtures/toy_suite", __dir__)
TOY_HELPER = File.join(TOY_SUITE, "evals", "eval_helper.rb")
require TOY_HELPER

Dir[File.join(__dir__, "support", "*.rb")].each { require it }

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { it.syntax = :expect }
  config.order = :random
  config.example_status_persistence_file_path = ".rspec_status"
  Kernel.srand config.seed
end
