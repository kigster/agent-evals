# frozen_string_literal: true

require "yaml"

module Agent
  module Evals
    # The suite's config.yml: which models to compare, and at which settings.
    #
    #   project: my-evals            # Braintrust project name
    #   defaults:
    #     effort: default
    #     temperature: 0.2
    #     max_tokens: 4096
    #     parallelism: 4
    #   vendors:
    #     anthropic:
    #       - model: claude-haiku-5.5
    #         effort: [default, low]  # a list expands into one contender per value
    #
    # Each entry becomes "<vendor>/<model>", the id a provider recognises.
    class Config
      BUILTIN = {
        "effort" => "default", "temperature" => 0.2, "max_tokens" => 4096, "parallelism" => 4
      }.freeze

      attr_reader :path

      # @param path [String] read when it exists; an absent file is an empty lineup
      def initialize(path)
        @path = path
        @data = File.exist?(path) ? (YAML.safe_load_file(path) || {}) : {}
      end

      # @return [String, nil] the Braintrust project name
      def project = @data["project"]

      # @return [Hash{String => Object}] the built-in defaults under the file's own
      def defaults = BUILTIN.merge(@data.fetch("defaults", nil) || {})

      # Every vendor/model/effort/temperature combination the file lists.
      #
      # @param overrides [Hash{String => Object}] values from the command line; nil entries are ignored
      # @return [Array<Contender>]
      def contenders(overrides = {})
        (@data["vendors"] || {}).flat_map do |vendor, entries|
          Array(entries).flat_map { expand("#{vendor}/#{it.fetch("model")}", it, overrides) }
        end
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

      def expand(model, entry, overrides)
        settings = defaults.merge(entry).merge(overrides.compact)
        Array(settings["effort"]).product(Array(settings["temperature"])).map do |effort, temperature|
          Contender.new(model: model, effort: effort.to_s, temperature: temperature, max_tokens: Integer(settings["max_tokens"]))
        end
      end
    end
  end
end
