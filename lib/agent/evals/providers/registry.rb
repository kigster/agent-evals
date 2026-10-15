# frozen_string_literal: true

module Agent
  module Evals
    module Providers
      # The providers in use, asked in order which one serves a model id. A
      # provider registered later is asked first, so a suite's own transport
      # beats the defaults for the ids it claims; OpenRouter, which claims
      # everything, is always last.
      class Registry
        include Enumerable

        # @return [Registry] TypeSafe, then OpenRouter for everything else
        def self.default = new([OpenRouter.new, TypeSafe.new])

        # @param providers [Array<Base>] the last one is asked first
        def initialize(providers = [])
          @providers = providers.dup
        end

        # @param provider [Base]
        # @return [Base] the provider
        def register(provider)
          @providers << provider
          provider
        end

        def each(&) = @providers.reverse.each(&)

        # @param model_id [String]
        # @return [Base]
        # @raise [Error] when no provider serves the id
        def for(model_id)
          find { it.serves?(model_id) } || raise(Error, "no provider serves #{model_id.inspect}; have #{map(&:name).join(", ")}")
        end

        # @param contenders [Array<Contender>]
        # @return [Array<Base>] each provider the contenders use, once
        def used_by(contenders) = contenders.map { self.for(it.model) }.uniq

        # @param contenders [Array<Contender>]
        # @return [Array<String>] the API keys the contenders' providers need
        def keys_for(contenders) = used_by(contenders).flat_map(&:env_keys).uniq

        # @param contender [Contender]
        # @return [Model]
        def model_for(contender) = self.for(contender.model).model_for(contender)

        # @return [Array<String>] every effort any provider accepts, for the flag's help
        def efforts = flat_map(&:efforts).uniq

        # Asks each provider in use for its catalog, and names every model it
        # does not list.
        #
        # @param contenders [Array<Contender>]
        # @return [void]
        # @raise [Error] naming every unknown model
        def verify!(contenders)
          unknown = contenders.map(&:model).uniq.group_by { self.for(it) }.flat_map { |provider, ids| provider.unknown(ids) }
          return if unknown.empty?

          raise Error,
            "unknown model#{"s" if unknown.size > 1} #{unknown.join(", ")}: not listed by its provider; " \
            "check the id in config.yml or -m"
        end
      end
    end
  end
end
