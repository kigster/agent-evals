# frozen_string_literal: true

module Agent
  module Evals
    # What a suite implements to score one reply. Pure and deterministic: it
    # reads the case, the reply and the adapter's context, and calls nothing.
    #
    # @abstract Subclass and override {#metrics} and {#call}.
    class Scorer
      # The metrics every {Score} this scorer returns carries. The CLI builds
      # its columns, its glossary and its Braintrust scorers from this list,
      # so a metric missing here is a metric nobody sees.
      #
      # @return [Array<Metric>]
      def metrics
        raise NotImplementedError, "#{self.class}#metrics must return an Array of Agent::Evals::Metric"
      end

      # @return [Metric] the one flagged primary, else the first
      def primary = metrics.find(&:primary) || metrics.first

      # @param kase [Case]
      # @param reply [Reply] never one with `error` set; the runner scores those 0 itself
      # @param context [Hash] what {Adapter#context} returned for the case
      # @return [Score]
      def call(kase, reply, context:)
        raise NotImplementedError, "#{self.class}#call(kase, reply, context:) must return an Agent::Evals::Score"
      end

      # Offline checks of one case against what the scorer will demand of it,
      # so a typo in expected.json is caught before it is billed as a model's mistake.
      #
      # @param kase [Case]
      # @param context [Hash] what {Adapter#context} returned for the case
      # @return [Array<String>] problems; empty when the case is sound
      def verify(kase, context:) = [] # rubocop:disable Lint/UnusedMethodArgument -- the signature is the contract

      # One short cell describing the case in `agent-evals cases`, e.g. "5/8 answered".
      #
      # @param kase [Case]
      # @return [String, nil] nil for the generic fallback
      def summary(_kase) = nil
    end
  end
end
