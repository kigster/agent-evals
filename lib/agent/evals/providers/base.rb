# frozen_string_literal: true

module Agent
  module Evals
    module Providers
      # What answers a {Model}'s calls: one API, the ids it serves, the keys it
      # needs and the models it lists. A suite with its own transport
      # subclasses this and registers it through `c.provider`.
      #
      # @abstract Override {#serves?}, {#env_keys}, {#catalog} and {#complete}.
      class Base
        # The reasoning efforts this provider's API accepts.
        EFFORTS = %w[none minimal low medium high xhigh max].freeze

        # @return [String] short name, for messages and the leaderboard
        def name = self.class.name.split("::").last.gsub(/([a-z\d])([A-Z])/, '\1-\2').downcase

        # @param model_id [String] as the lineup names it
        # @return [Boolean] whether this provider serves the model
        def serves?(model_id) = model_id.start_with?(prefix)

        # @return [String] the id prefix this provider claims; "" claims everything
        def prefix = ""

        # @param model_id [String]
        # @return [String] the id as the provider's API knows it
        def model_name(model_id) = model_id.delete_prefix(prefix)

        # @return [Array<String>] environment variables a run through this provider needs
        def env_keys = []

        # @return [Array<String>] the efforts the `-e` flag accepts for this provider's models
        def efforts = EFFORTS

        # Lists the model ids the provider serves, from the network, so a
        # misspelled id aborts the run before any experiment starts instead
        # of failing every case and showing up as a row of errors.
        #
        # @return [Array<String>, nil] ids as the lineup names them; nil when the provider cannot list them
        def catalog = nil

        # Prepares the client once per process, after the env files loaded.
        #
        # @option options [String] :app_name what the client tells the API the caller is
        # @return [void]
        def setup!(**) = nil

        # @param model [Model]
        # @param system [String, nil]
        # @param user [String]
        # @param json [Boolean]
        # @return [Completion]
        def complete(model, system:, user:, json: true)
          raise NotImplementedError, "#{self.class}#complete must return an Agent::Evals::Completion"
        end

        # @param contender [Contender]
        # @return [Model]
        def model_for(contender) = Model.new(id: contender.model, provider: self, settings: contender.settings)

        # Every id in `model_ids` the provider does not list.
        #
        # @param model_ids [Array<String>]
        # @return [Array<String>]
        def unknown(model_ids)
          listed = catalog
          listed.nil? ? [] : model_ids - listed
        end
      end
    end
  end
end
