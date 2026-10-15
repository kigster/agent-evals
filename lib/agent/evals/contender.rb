# frozen_string_literal: true

module Agent
  module Evals
    # One model at one setting: what a single experiment runs. Built by
    # {Config} from the lineup file, or from `-m` on the command line.
    #
    # `provider` is nil for a `vendors:` entry, which OpenRouter serves, and
    # the provider's name for a `direct:` entry. It travels with the
    # contender rather than being read back out of the id, so `typesafe/jev-router`
    # (Jev on OpenRouter) and a direct `typesafe/jev-latest` can never be confused.
    Contender = Data.define(:model, :effort, :temperature, :max_tokens, :provider) do
      def initialize(model:, effort: "default", temperature: "default", max_tokens: nil, provider: nil) = super

      # @return [Boolean] whether the entry came from `direct:`
      def direct? = !provider.nil?

      # @return [String] unique across the lineup: "typesafe:typesafe/jev-latest" for a direct entry
      def key = direct? ? "#{provider}:#{model}" : model

      # The settings as a {Model} takes them: "default" means nil, send nothing.
      #
      # @return [Hash{Symbol => Object}]
      def settings
        { effort:      effort.to_s == "default" || effort.nil? ? nil : effort.to_s,
          temperature: temperature.to_s == "default" || temperature.nil? ? nil : Float(temperature),
          max_tokens:  max_tokens.nil? ? nil : Integer(max_tokens) }
      end
    end
  end
end
