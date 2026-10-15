# frozen_string_literal: true

module Agent
  module Evals
    # One model at one setting, reached through its provider. Adapters call
    # {#complete}; the settings an experiment is named by are read here.
    class Model
      # The settings every provider understands; a provider may accept more.
      SETTINGS = %i[effort temperature max_tokens].freeze

      attr_reader :id, :provider, :settings

      # @param id [String] the model id as the lineup names it, e.g. "anthropic/claude-haiku-5.5"
      # @param provider [Providers::Base] what answers {#complete}
      # @param settings [Hash{Symbol => Object}] effort, temperature, max_tokens; nil leaves the model's default
      def initialize(id:, provider:, settings: {})
        @id = id
        @provider = provider
        @settings = settings.transform_keys(&:to_sym).freeze
      end

      # @return [String, nil] reasoning effort; nil sends none
      def effort = settings[:effort]

      # @return [Float, nil] sampling temperature; nil sends none
      def temperature = settings[:temperature]

      # @return [Integer, nil] output token cap
      def max_tokens = settings[:max_tokens]

      # @return [String] the id without the provider's prefix, as the provider's API knows it
      def name = provider.model_name(id)

      # @return [String] "provider:id", unique where two providers render the same id
      def key = "#{provider.name}:#{id}"

      # One call. Transport failures raise; they are the run's errors, not the model's.
      #
      # @param system [String, nil]
      # @param user [String]
      # @param json [Boolean] ask the provider for a JSON object reply where it supports that
      # @return [Completion]
      def complete(user:, system: nil, json: true)
        provider.complete(self, system: system, user: user, json: json)
      end

      # @return [String] e.g. "effort=low t=0.2"
      def label
        "effort=#{effort || "default"} t=#{temperature.nil? ? "default" : temperature}"
      end

      def to_s = "#{id} #{label}"
    end
  end
end
