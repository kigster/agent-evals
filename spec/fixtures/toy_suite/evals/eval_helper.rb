# frozen_string_literal: true

# The toy suite, the helper way: two datasets, two variants each, answered by
# the gem's own EchoAdapter against a fake provider, and scored field by
# field. The adapter and the scorer live in lib/toy_suite/evals.rb, as a
# consumer gem would ship them; spec/fixtures/config_only_suite is the same
# suite with no helper at all. This one exists to prove the executable end
# to end without a network, and to show a new suite what the two contracts
# look like.
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "toy_suite/evals"

LLM::Evals.configure do |c|
  c.suite "toy", root: __dir__, env_files: [".env"], description: "The toy suite that ships with llm-evals."
  c.cases "datasets/*/cases/**/input.txt"
  c.adapter ToySuite::Evals::Adapter.new
  c.scorer ToySuite::Evals::Scorer.new
  c.provider LLM::Evals::Testing::FakeProvider.new # also registered by the require above; the later one replaces it
  c.before_run { ENV["TOY_SUITE_HOOK_RAN"] = "1" }
end
