# frozen_string_literal: true

module Agent
  module Evals
    module Trackers
      # The tracker classes a run may choose from, by name, and the choice
      # itself: exactly one remote tracker, or none. A consumer or a plugin
      # gem registers its own with `c.tracker`.
      class Registry
        include Enumerable

        # Spellings of "no remote tracker" on the command line and in the config.
        NONE = %w[none local off].freeze

        # @return [Registry] Braintrust and Logfire
        def self.default = new([Braintrust, Logfire])

        # @param classes [Array<Class<Tracker>>]
        def initialize(classes = [])
          @classes = classes.dup
        end

        # @param klass [Class<Tracker>] replaces one registered under the same name
        # @return [Class<Tracker>]
        def register(klass)
          @classes.reject! { it.tracker_name == klass.tracker_name }
          @classes << klass
          klass
        end

        def each(&) = @classes.each(&)

        # @return [Array<String>]
        def names = map(&:tracker_name)

        # @param name [String, Symbol]
        # @return [Class<Tracker>]
        # @raise [Error] naming the known trackers
        def named(name)
          find { it.tracker_name == name.to_s } || raise(Error, "no tracker named #{name.to_s.inspect}; known: #{names.join(", ")}")
        end

        # The one remote tracker to run, in this precedence: `--tracker`,
        # then the config's `tracker:`, then the environment, where a single
        # tracker's key being set selects it and two or more is an ambiguity
        # to be settled by naming one. `--local` is none.
        #
        # @param flag [String, nil] what `--tracker` was given
        # @param config [String, nil] the config file's `tracker:`
        # @param env [Hash]
        # @param local [Boolean] `--local`
        # @return [Array(Class<Tracker>, String), nil] the class and why it was chosen; nil for none
        # @raise [Error] on an unknown name or an ambiguous environment
        def choose(flag: nil, config: nil, env: ENV, local: false)
          return nil if local
          return choice(flag, "--tracker") if present?(flag)
          return choice(config, "tracker: in the config file") if present?(config)

          detected = @classes.select { it.detect?(env) }
          case detected.size
          when 0 then nil
          when 1 then [detected.first, "#{detected.first.env_key} is set (pass --tracker or set tracker: to choose explicitly)"]
          else
            raise Error,
              "more than one tracker is configured in the environment (#{detected.map(&:env_key).join(", ")}); " \
              "choose one with --tracker #{detected.map(&:tracker_name).join("|")} or tracker: in the config file"
          end
        end

        private

        def present?(value) = !value.nil? && !value.to_s.strip.empty?

        def choice(name, from)
          return nil if NONE.include?(name.to_s)

          [named(name), from]
        end
      end
    end
  end
end
