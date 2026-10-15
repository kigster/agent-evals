# frozen_string_literal: true

require "dotenv"

module Agent
  module Evals
    # One-time process setup: secrets from the suite's env files, a check that
    # every key the run needs is there, the suite's own hooks, the providers'
    # clients, and Braintrust tracing when the run logs there.
    class Runtime
      attr_reader :env_files, :hooks, :app_name

      # @param env_files [Array<String>] absolute paths; those that exist load
      # @param hooks [Array<Proc>] the suite's `before_run` blocks
      # @param app_name [String] what a provider tells its API the caller is
      def initialize(env_files: [], hooks: [], app_name: "agent-evals")
        @env_files = env_files
        @hooks = hooks
        @app_name = app_name
      end

      # Loads the env files that exist, without overriding what is already
      # set, so an exported variable beats the file.
      #
      # @return [void]
      def load_env
        files = env_files.select { File.exist?(it) }
        Dotenv.load(*files) unless files.empty?
      end

      # Fails before anything is called when a key the run needs is neither
      # exported nor in an env file.
      #
      # @param names [Array<String>]
      # @return [void]
      # @raise [Error] naming every missing variable
      def require_env!(names)
        missing = names.uniq.select { ENV[it].to_s.strip.empty? }
        return if missing.empty?

        found = env_files.select { File.exist?(it) }
        where = if found.empty?
                  env_files.empty? ? "no env files are configured" : "there is no #{env_files.join(" or ")}"
                else
                  "checked the environment, then #{found.join(", ")}"
                end
        raise Error,
          "missing #{missing.join(", ")}: export them or add them to an env file (#{where}); " \
          "an exported blank value wins over the file"
      end

      # @param providers [Array<Providers::Base>] the providers the run's models use
      # @param braintrust [Boolean] false runs locally: no login, no experiment
      # @return [void]
      # @raise [Error] when a needed variable is missing
      def setup!(providers: [], braintrust: true)
        load_env
        require_env!(providers.flat_map(&:env_keys) + (braintrust ? ["BRAINTRUST_API_KEY"] : []))
        hooks.each(&:call) # after load_env: a hook usually re-reads ENV
        providers.each { it.setup!(app_name: app_name) }
        return unless braintrust

        Agent::Evals.optional!("braintrust", needed_for: "logging to Braintrust")
        Braintrust.init(blocking_login: true, auto_instrument: false)
        Braintrust.instrument!(:ruby_llm) if defined?(RubyLLM)
      end

      # Opens a URL in the desktop browser.
      #
      # @param url [String]
      # @return [Boolean] whether the opener ran
      def browse(url)
        opener = RUBY_PLATFORM.include?("darwin") ? "open" : "xdg-open"
        system(opener, url, out: File::NULL, err: File::NULL) || false
      end
    end
  end
end
