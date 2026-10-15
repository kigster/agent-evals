# frozen_string_literal: true

module Agent
  module Evals
    module Providers
      # TypeSafe's own API, which serves Jev as typed questions rather than
      # chat. The gem knows its model list, its key and its pricing, enough
      # for `verify` and the cost column; the request itself is the suite's,
      # since it is shaped by the suite's fields. Register a subclass that
      # overrides {#complete}, or have the adapter call TypeSafe directly.
      class TypeSafe < Base
        PREFIX = "typesafe-api/"
        URL = "https://api.typesafe.ai/v1/models"
        KEY = "TYPESAFE_API_KEY"

        # TypeSafe bills input tokens only: $0.042 per million for jev-latest
        # and jev-preview (docs.typesafe.ai/models, read 2026-10-14). Output is free.
        USD_PER_INPUT_TOKEN = 0.042 / 1_000_000

        def name = "typesafe"
        def prefix = PREFIX
        def env_keys = [KEY]

        # Jev takes no reasoning effort.
        def efforts = []

        # @return [Array<String>] the models, as "typesafe-api/<name>"
        def catalog
          Catalog.fetch(URL, "Authorization" => "Bearer #{ENV.fetch(KEY, nil)}").fetch("models").map { "#{PREFIX}#{it.fetch("name")}" }
        end

        # @param input_tokens [Integer]
        # @return [Usage] with the cost at TypeSafe's input rate
        def usage(input_tokens:, output_tokens: 0)
          Usage.new(input_tokens: input_tokens, output_tokens: output_tokens, cost_usd: input_tokens * USD_PER_INPUT_TOKEN)
        end

        # @raise [Error] always: the typed request is the suite's to build
        def complete(model, system:, user:, json: true) # rubocop:disable Lint/UnusedMethodArgument
          raise Error,
            "#{model.id}: TypeSafe serves typed questions, not chat; the adapter calls it directly, " \
            "or a provider subclass overrides #complete"
        end
      end
    end
  end
end
