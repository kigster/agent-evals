# frozen_string_literal: true

# The toy suite: two datasets, two variants each, answered by the gem's own
# EchoAdapter against a fake provider, and scored field by field. It exists
# to prove the executable end to end without a network, and to show a new
# suite what the two contracts look like.
require "agent/evals"

# Compares each expected field with the reply's, exactly. A null in the
# expected answer means the text never said, and the right reply leaves it
# null; `restraint` is how often the model did, on the cases that have one.
class ToyScorer < Agent::Evals::Scorer
  METRICS = [
    Agent::Evals::Metric.new(name: "field_accuracy",
      description: "Share of expected fields the reply matched exactly.",
      primary: true),
    Agent::Evals::Metric.new(name: "exact_match", description: "1 when every field matched."),
    Agent::Evals::Metric.new(name: "restraint",
      description: "Of the fields expected null, the share left null; " \
                   "nothing recorded when no field is null.")
  ].freeze

  def metrics = METRICS

  def call(kase, reply, **)
    output = reply.output.transform_keys(&:to_s)
    hits = kase.expected.to_h { |field, want| [field, output[field] == want ? 1.0 : 0.0] }
    open = kase.expected.select { |_, want| want.nil? }.keys
    wrong = hits.select { |_, hit| hit.zero? }.to_h { |field, _| [field, { want: kase.expected[field], got: output[field] }] }
    Agent::Evals::Score.new(
      value:       hits.values.sum / hits.size,
      metrics:     { "field_accuracy" => hits.values.sum / hits.size,
                     "exact_match"    => hits.values.all?(1.0) ? 1.0 : 0.0,
                     "restraint"      => open.empty? ? nil : open.count { output[it].nil? }.fdiv(open.size) },
      diagnostics: wrong
    )
  end

  def verify(kase, **)
    kase.expected.is_a?(Hash) ? [] : ["expected.json must hold an object"]
  end

  def summary(kase) = "#{kase.expected.count { |_, v| !v.nil? }}/#{kase.expected.size} answered"
end

Agent::Evals.configure do |c|
  c.suite "toy", root: __dir__, env_files: [".env"], description: "The toy suite that ships with agent-evals."
  c.cases "datasets/*/cases/**/input.txt"
  c.adapter Agent::Evals::Testing::EchoAdapter.new
  c.scorer ToyScorer.new
  c.provider Agent::Evals::Testing::FakeProvider.new
  c.before_run { ENV["TOY_SUITE_HOOK_RAN"] = "1" }
end
