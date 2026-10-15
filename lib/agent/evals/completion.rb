# frozen_string_literal: true

module Agent
  module Evals
    # What a {Model} returns from one call: the text, what it cost, and the
    # provider's raw response for an adapter that needs more than the text.
    Completion = Data.define(:text, :usage, :raw) do
      def initialize(text:, usage: Usage.zero, raw: nil) = super(text: text.to_s, usage: Usage.from(usage), raw: raw)
    end
  end
end
