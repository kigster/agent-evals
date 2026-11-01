# frozen_string_literal: true

module LLM
  module Evals
    module Testing
      # Serves every "fake/..." model without a network: a call answers with
      # the expected JSON of the case whose input matches the user prompt, so
      # a suite's own plumbing can be run end to end through the executable.
      #
      # `junk` names cases (by id or key) that get a non-JSON reply, and
      # `wrong` maps a case to fields to answer wrongly. `answers`, a callable
      # taking the user prompt, replaces the lookup altogether.
      class FakeProvider < Providers::Base
        PREFIX = "fake/"
        USAGE = Usage.new(input_tokens: 100, output_tokens: 10, cost_usd: 0.001)
        JUNK = "Sure! Here is my answer, in prose rather than JSON."

        attr_reader :calls

        # @param junk [Array<String>] case ids or keys to answer with prose
        # @param wrong [Hash{String => Hash}] case id or key => fields to override
        # @param answers [#call, nil] user prompt => reply text; replaces the lookup
        # @param discovery [Discovery, nil] where to look cases up; the configured suite's when nil
        def initialize(junk: [], wrong: {}, answers: nil, discovery: nil)
          super()
          @junk = junk
          @wrong = wrong
          @answers = answers
          @discovery = discovery
          @calls = []
          @lock = Mutex.new
        end

        def name = "fake"
        def request_type = :prompt
        def prefix = PREFIX
        def env_keys = []

        # @return [nil] any id passes verification
        def catalog = nil

        # @param model [Model]
        # @param system [String, nil]
        # @param user [String]
        # @param json [Boolean]
        # @return [Completion]
        def complete(model, system:, user:, json: true)
          @lock.synchronize { @calls << { model: model.id, system: system, user: user, json: json } }
          Completion.new(text: @answers ? @answers.call(user) : answer(user), usage: USAGE)
        end

        private

        def answer(user)
          kase = discovery.all.find { it.input == user }
          return "{}" if kase.nil?
          return JUNK if @junk.include?(kase.id) || @junk.include?(kase.key)

          wrong = @wrong[kase.id] || @wrong[kase.key] || {}
          JSON.generate(kase.expected.is_a?(Hash) ? kase.expected.merge(wrong) : kase.expected)
        end

        def discovery = @discovery || LLM::Evals.configuration.discovery
      end
    end
  end
end
