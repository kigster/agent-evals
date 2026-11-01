# frozen_string_literal: true

module LLM
  module Evals
    # One eval case, as {Discovery} found it on disk: the text the model is
    # given, the answer a perfect reply would produce, and where it came from.
    #
    # @!attribute [r] id
    #   @return [String] unique within its dataset, e.g. "clear/003"
    # @!attribute [r] dataset
    #   @return [String] the folder under datasets/, e.g. "colors"
    # @!attribute [r] variant
    #   @return [String] the folder under cases/, e.g. "clear" or "vague"
    # @!attribute [r] input
    #   @return [String] input.txt, stripped
    # @!attribute [r] expected
    #   @return [Object, nil] expected.json parsed; nil when missing or unparsable
    # @!attribute [r] path
    #   @return [String] the case's directory
    # @!attribute [r] metadata
    #   @return [Hash{Symbol => Object}] number, difficulty, and any `expected_error`
    Case = Data.define(:id, :dataset, :variant, :input, :expected, :path, :metadata) do
      # @return [Integer, nil] the NNN/ level as a number, when the case has one
      def number = metadata[:number]

      # @return [Integer] the number, else 0; what the tables sort and show difficulty by
      def difficulty = metadata.fetch(:difficulty, number || 0)

      # @return [String] "dataset/id", unique across the suite
      def key = "#{dataset}/#{id}"

      # @return [Boolean] whether expected.json was there and parsed
      def expected? = !expected.nil?
    end
  end
end
