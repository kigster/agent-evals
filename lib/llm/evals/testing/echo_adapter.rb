# frozen_string_literal: true

module LLM
  module Evals
    module Testing
      # The smallest honest adapter: sends the case's input as the user
      # prompt, parses the reply as a JSON object, and reports a reply that
      # is not one as the model's failure. The toy suite runs on it, and a
      # new suite can start from it.
      class EchoAdapter < Adapter
        SYSTEM = "Answer with a single JSON object and nothing else."
        FENCE = /\A```(?:json)?\s*|\s*```\z/

        # @param kase [Case]
        # @param model [Model]
        # @return [Reply]
        def call(kase, model:)
          completion = model.complete(system: SYSTEM, user: kase.input, json: true)
          output = JSON.parse(completion.text.strip.gsub(FENCE, ""))
          return Reply.new(error: "reply is not a JSON object", raw: completion.text, usage: completion.usage) unless output.is_a?(Hash)

          Reply.new(output: output, raw: completion.text, usage: completion.usage)
        rescue JSON::ParserError
          Reply.new(error: "reply is not JSON", raw: completion.text, usage: completion.usage)
        end
      end
    end
  end
end
