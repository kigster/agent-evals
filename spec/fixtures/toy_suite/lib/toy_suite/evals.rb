# frozen_string_literal: true

# The toy suite's Ruby, as a consumer gem would ship it: the adapter and the
# scorer under its own namespace, requirable from `.llm-evals.config.yml`
# (`require: toy_suite/evals`) with no eval_helper.rb at all. Requiring it
# also registers the fake provider, the way a consumer's require may add
# the transport its models need.
require "llm/evals"

module ToySuite
  module Evals
    # The gem's own EchoAdapter, under the consumer's name.
    class Adapter < LLM::Evals::Testing::EchoAdapter; end

    # Compares each expected field with the reply's, exactly. A null in the
    # expected answer means the text never said, and the right reply leaves
    # it null; `restraint` is how often the model did, on the cases that have one.
    class Scorer < LLM::Evals::Scorer
      METRICS = [
        LLM::Evals::Metric.new(name: "field_accuracy", description: "Share of expected fields the reply matched exactly.", primary: true),
        LLM::Evals::Metric.new(name: "exact_match", description: "1 when every field matched."),
        LLM::Evals::Metric.new(name: "restraint",
          description: "Of the fields expected null, the share left null; " \
                       "nothing recorded when no field is null.")
      ].freeze

      def metrics = METRICS

      def call(kase, reply, **)
        output = reply.output.transform_keys(&:to_s)
        hits = kase.expected.to_h { |field, want| [field, output[field] == want ? 1.0 : 0.0] }
        open = kase.expected.select { |_, want| want.nil? }.keys
        wrong = hits.select { |_, hit| hit.zero? }.to_h { |field, _| [field, { want: kase.expected[field], got: output[field] }] }
        LLM::Evals::Score.new(
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
  end
end

LLM::Evals.configure { |c| c.provider LLM::Evals::Testing::FakeProvider.new }
