# frozen_string_literal: true

require "yaml"

module Agent
  module Evals
    # The suite's `.agent-eval.config.yml`: which models to compare, at which
    # settings, and which kinds of request the suite can produce.
    #
    #   project: my-evals            # Braintrust project name
    #   request_types: [prompt]      # required: what the adapter sends; a provider must match
    #   defaults:
    #     effort: default
    #     temperature: 0.2
    #     max_tokens: 4096
    #     parallelism: 4
    #   vendors:                     # the OpenRouter list; every entry takes a prompt
    #     anthropic:
    #       - model: claude-haiku-5.5
    #         effort: [default, low]  # a list expands into one contender per value
    #   direct:                      # a vendor's own API, one request type each
    #     typesafe:
    #       - model: jev-latest
    #
    # Each entry becomes "<vendor>/<model>", the id a provider recognises. A
    # key under `direct:` names a provider; its entries carry that provider.
    class Config
      # The request types a suite may declare. `prompt` is a chat completion:
      # system and user text in, text out. `typesafe` is TypeSafe's typed
      # question API, whose request shape the first such suite will define.
      REQUEST_TYPES = %w[prompt typesafe].freeze

      BUILTIN = {
        "effort" => "default", "temperature" => 0.2, "max_tokens" => 4096, "parallelism" => 4
      }.freeze

      attr_reader :path, :direct_providers

      # @param path [String] read when it exists; an absent file is an empty lineup
      # @param direct_providers [Array<String>] the provider names `direct:` may use
      def initialize(path, direct_providers: Providers::Registry.default.direct_names)
        @path = path
        @direct_providers = direct_providers
        @data = File.exist?(path) ? (YAML.safe_load_file(path) || {}) : {}
      end

      # @return [String, nil] the Braintrust project name
      def project = @data["project"]

      # The kinds of request the suite's adapter produces. A provider whose
      # request type is not listed cannot serve this suite, whatever model it
      # names, so the list is required: without it every contender would be
      # admitted on faith and fail at the first call.
      #
      # @return [Array<Symbol>]
      # @raise [Error] when the key is missing, empty, or names an unknown type
      def request_types
        listed = Array(@data["request_types"]).map(&:to_s)
        raise Error, "#{path}: request_types is required; list one or more of #{REQUEST_TYPES.join(", ")}" if listed.empty?

        unknown = listed - REQUEST_TYPES
        raise Error, "#{path}: unknown request_types #{unknown.join(", ")}; known: #{REQUEST_TYPES.join(", ")}" if unknown.any?

        listed.map(&:to_sym)
      end

      # @return [Hash{String => Object}] the built-in defaults under the file's own
      def defaults = BUILTIN.merge(@data.fetch("defaults", nil) || {})

      # Every vendor/model/effort/temperature combination the file lists,
      # `vendors:` first, then `direct:`.
      #
      # @param overrides [Hash{String => Object}] values from the command line; nil entries are ignored
      # @return [Array<Contender>]
      # @raise [Error] on a key under `direct:` that names no provider
      def contenders(overrides = {})
        vendors = (@data["vendors"] || {}).flat_map do |vendor, entries|
          Array(entries).flat_map { expand("#{vendor}/#{it.fetch("model")}", it, overrides) }
        end
        direct = (@data["direct"] || {}).flat_map do |name, entries|
          unless direct_providers.include?(name.to_s)
            raise Error, "#{path}: unknown provider #{name.inspect} under direct:; known: #{direct_providers.join(", ")}"
          end

          Array(entries).flat_map { expand("#{name}/#{it.fetch("model")}", it, overrides, provider: name.to_sym) }
        end
        vendors + direct
      end

      # The models given on the command line, at the file's default settings.
      #
      # @param models [Array<String>] model ids
      # @param overrides [Hash{String => Object}]
      # @return [Array<Contender>]
      def contenders_for(models, overrides = {})
        models.flat_map { expand(it, {}, overrides) }
      end

      private

      def expand(model, entry, overrides, provider: nil)
        settings = defaults.merge(entry).merge(overrides.compact)
        Array(settings["effort"]).product(Array(settings["temperature"])).map do |effort, temperature|
          Contender.new(model: model,
            effort: effort.to_s,
            temperature: temperature,
            max_tokens: Integer(settings["max_tokens"]),
            provider: provider)
        end
      end
    end
  end
end
