# frozen_string_literal: true

module LLM
  module Evals
    # Finds and loads the suite: `evals/eval_helper.rb`, the file that calls
    # {LLM::Evals.configure}, or, for a config-only suite, the directory
    # holding `evals/.llm-evals.config.yml`. The executable looks before
    # dispatching, the way rspec finds spec_helper, so the suite's own
    # directory needs no wrapper script.
    module Helper
      FILE = File.join("evals", "eval_helper.rb")
      ENV_VAR = "LLM_EVALS_HELPER"
      FLAG = "--helper"

      # What {.locate} found: a helper to load, a config file to read, or neither.
      Found = Data.define(:helper, :config) do
        def initialize(helper: nil, config: nil) = super

        # @return [Boolean] whether there is anything to load
        def any? = !helper.nil? || !config.nil?

        # @return [Boolean]
        def none? = !any?
      end

      module_function

      # Pulls `--helper PATH` (or `--helper=PATH`) out of argv, so dry-cli
      # never sees a flag no command declares.
      #
      # @param argv [Array<String>]
      # @return [Array(Array<String>, String, nil)] the remaining arguments and the path, if given
      def extract(argv)
        rest = []
        path = nil
        skip = false
        argv.each_with_index do |arg, index|
          next skip = false if skip

          if arg == FLAG
            path = argv[index + 1]
            skip = true
          elsif arg.start_with?("#{FLAG}=")
            path = arg.delete_prefix("#{FLAG}=")
          else
            rest << arg
          end
        end
        [rest, path]
      end

      # The suite to load: the flag, then the variable, then, from the
      # directory upward, the nearest `evals/eval_helper.rb` or, failing
      # that, the nearest `evals/.llm-evals.config.yml` (also found from
      # inside `evals/` itself).
      #
      # @param explicit [String, nil] what `--helper` was given
      # @param from [String] the directory to search up from
      # @param env [Hash] the environment
      # @return [Found] absolute paths; empty when there is none
      def locate(explicit = nil, from: Dir.pwd, env: ENV)
        candidate = explicit || env[ENV_VAR]
        return Found.new(helper: File.expand_path(candidate, from)) if candidate && !candidate.empty?

        Pathname(from).expand_path.ascend do |dir|
          helper = dir.join(FILE)
          config = [dir.join("evals", Configuration::DEFAULT_CONFIG), dir.join(Configuration::DEFAULT_CONFIG)].find(&:file?)
          return Found.new(helper: helper.to_s, config: config&.to_s) if helper.file?
          return Found.new(config: config.to_s) if config
        end
        Found.new
      end

      # Loads the helper, once, or roots the configuration at a config-only
      # suite's directory so {Configuration#resolve_from_config!} can read it.
      # A helper is loaded first and wins; the config fills what it left unset.
      #
      # @param found [Found, String, nil] nothing is loaded for nil or an empty Found
      # @param configuration [Configuration]
      # @return [Boolean] whether anything was loaded
      # @raise [Error] when the helper does not exist
      def load!(found, configuration: LLM::Evals.configuration)
        found = Found.new(helper: found) if found.is_a?(String)
        return false if found.nil? || found.none?

        if found.helper
          raise Error, "no eval helper at #{found.helper}" unless File.file?(found.helper)

          require File.expand_path(found.helper)
        else
          root = File.dirname(found.config)
          configuration.suite(File.basename(File.dirname(root)), root: root) unless configuration.complete?
        end
        true
      end
    end
  end
end
