# frozen_string_literal: true

module LLM
  module Evals
    # What a suite implements to run one case: everything the model sees, and
    # everything done to its answer before it is scored. An adapter never
    # scores; that is the {Scorer}'s, and keeping them apart is what lets one
    # suite compare prompts and another compare models with the same runner.
    #
    # @abstract Subclass and override {#call}.
    class Adapter
      # Called once per dataset before its cases run; load what the dataset
      # shares (a schema, a flow definition) here, outside the threads.
      #
      # @param dataset [String]
      # @return [void]
      def prepare(_dataset) = nil

      # Runs one case against one model.
      #
      # @param kase [Case]
      # @param model [Model]
      # @return [Reply] with `error:` set when the model failed to answer; raise for a transport failure
      def call(kase, model:)
        raise NotImplementedError, "#{self.class}#call(kase, model:) must return an LLM::Evals::Reply"
      end

      # What the scorer needs to know about a case beyond the case itself: a
      # schema, field types, the prompt. Passed to {Scorer#call} as `context:`.
      #
      # @param kase [Case]
      # @return [Hash]
      def context(_kase) = {}

      # Offline checks of a dataset's shared files. `llm-evals verify` prints them.
      #
      # @param dataset [String]
      # @return [Array<String>] problems; empty when the dataset is sound
      def verify(_dataset) = []

      # Recorded with each Braintrust experiment, e.g. which prompt version ran.
      #
      # @return [Hash]
      def metadata = {}
    end
  end
end
