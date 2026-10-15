# frozen_string_literal: true

module Agent
  module Evals
    # Everything a suite tells the gem, through {Agent::Evals.configure}.
    # Paths are relative to `root`, the directory the eval helper lives in.
    class Configuration
      DEFAULT_GLOB = "datasets/*/cases/**/input.txt"
      DEFAULT_CONFIG = ".agent-eval.config.yml"

      attr_writer :adapter, :scorer
      attr_reader :name, :root, :env_files, :cases_glob, :hooks, :providers, :description

      def initialize
        @name = "agent-evals"
        @root = Dir.pwd
        @env_files = []
        @cases_glob = DEFAULT_GLOB
        @config_path = DEFAULT_CONFIG
        @hooks = []
        @providers = Providers::Registry.default
        @description = "Run a suite of cases against one or more models and score the replies."
        @project = nil
      end

      # Names the suite. The name titles the help and tags the experiments.
      #
      # @param name [String]
      # @param root [String] where .agent-eval.config.yml and datasets/ live; the helper's directory
      # @param env_files [Array<String>] dotenv files to load, relative to root; the first that exists wins nothing,
      #   all that exist load, and an exported variable beats them all
      # @param description [String, nil] one line for the help's header
      # @return [void]
      def suite(name, root:, env_files: [], description: nil)
        @name = name
        @root = File.expand_path(root)
        @env_files = env_files.map { File.expand_path(it, @root) }
        @description = description if description
      end

      # Where the cases are: a glob relative to root ending in the input file.
      # Each match is a case; the expected answer is `expected.json` beside it.
      #
      # @param glob [String]
      # @return [void]
      def cases(glob)
        @cases_glob = glob
      end

      # @param object [Adapter]
      # @return [void]

      # @param object [Adapter, nil] setting; reading when nil
      # @return [Adapter]
      def adapter(object = nil)
        @adapter = object unless object.nil?
        @adapter
      end

      # @param object [Scorer, nil] setting; reading when nil
      # @return [Scorer]
      def scorer(object = nil)
        @scorer = object unless object.nil?
        @scorer
      end

      # @param object [Scorer]
      # @return [void]

      # Runs once, after the env files are loaded and before any model is
      # called. The place to reset a library that read ENV at require time.
      #
      # @yield
      # @return [void]
      def before_run(&block)
        @hooks << block
      end

      # Adds a provider, ahead of the defaults, so a suite's own transport
      # wins the ids it claims.
      #
      # @param provider [Providers::Base]
      # @return [void]
      def provider(provider)
        @providers.register(provider)
      end

      # @param path [String, nil] setting, relative to root; reading when nil
      # @return [String] the absolute path of the lineup file, `.agent-eval.config.yml` at the root by default
      def config(path = nil)
        @config_path = path unless path.nil?
        File.expand_path(@config_path, root)
      end

      # @param name [String, nil] setting; reading when nil
      # @return [String, nil] the Braintrust project, when .agent-eval.config.yml does not name one
      def project(name = nil)
        @project = name unless name.nil?
        @project
      end

      # @return [Discovery] the cases, as the glob finds them
      def discovery = Discovery.new(root: root, glob: cases_glob)

      # @return [Config] the lineup file
      def lineup = Config.new(config, direct_providers: providers.direct_names)

      # @return [Runtime]
      def runtime = Runtime.new(env_files: env_files, hooks: hooks, app_name: name)

      # @return [Boolean] whether an adapter and a scorer are registered
      def complete? = !adapter.nil? && !scorer.nil?

      # Fails a command that needs the suite when no helper was loaded, with
      # the fix in the message, instead of a NoMethodError on nil.
      #
      # @return [self]
      # @raise [Error]
      def require_suite!
        return self if complete?

        raise Error,
          "no suite is configured: create evals/eval_helper.rb calling Agent::Evals.configure " \
          "with an adapter and a scorer, or pass --helper PATH (or set AGENT_EVALS_HELPER)"
      end
    end
  end
end
