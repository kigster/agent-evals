# frozen_string_literal: true

module Agent
  module Evals
    # What an {Adapter} returns for one case. `error` is the model's failure
    # (it did not answer the question: no JSON, a refusal) and scores 0; a
    # transport failure is not the model's and is raised instead, so it is
    # counted as an error of the run rather than a wrong answer.
    Reply = Data.define(:output, :raw, :usage, :error, :metadata) do
      def initialize(output: nil, raw: nil, usage: Usage.zero, error: nil, metadata: {})
        super(output: output, raw: raw, usage: Usage.from(usage), error: error, metadata: metadata)
      end

      # @return [Boolean] whether the model failed to answer
      def error? = !error.nil?
    end
  end
end
