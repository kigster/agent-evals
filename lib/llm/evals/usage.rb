# frozen_string_literal: true

module LLM
  module Evals
    # What one call cost, as the provider counted it. Summed over a run.
    Usage = Data.define(:input_tokens, :output_tokens, :cost_usd) do
      # @return [Usage] zero of everything
      def self.zero = new(input_tokens: 0, output_tokens: 0, cost_usd: 0.0)

      # Reads a Hash with Symbol or String keys, missing keys as zero.
      #
      # @param hash [Hash, Usage, nil]
      # @return [Usage]
      def self.from(hash)
        return hash if hash.is_a?(Usage)
        return zero if hash.nil?

        h = hash.transform_keys(&:to_sym)
        new(input_tokens: h.fetch(:input_tokens, 0).to_i,
          output_tokens: h.fetch(:output_tokens, 0).to_i,
          cost_usd: h.fetch(:cost_usd, 0.0).to_f)
      end

      # @param other [Usage]
      # @return [Usage]
      def +(other)
        with(input_tokens: input_tokens + other.input_tokens,
          output_tokens: output_tokens + other.output_tokens,
          cost_usd: cost_usd + other.cost_usd)
      end
    end
  end
end
