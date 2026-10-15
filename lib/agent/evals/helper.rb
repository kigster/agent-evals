# frozen_string_literal: true

module Agent
  module Evals
    # Finds and loads the suite's `evals/eval_helper.rb`, the file that calls
    # {Agent::Evals.configure}. The executable looks for it before dispatching,
    # the way rspec finds spec_helper, so the suite's own directory needs no
    # wrapper script.
    module Helper
      FILE = File.join("evals", "eval_helper.rb")
      ENV_VAR = "AGENT_EVALS_HELPER"
      FLAG = "--helper"

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

      # The helper to load: the flag, then the variable, then the nearest
      # `evals/eval_helper.rb` from the directory upward.
      #
      # @param explicit [String, nil] what `--helper` was given
      # @param from [String] the directory to search up from
      # @param env [Hash] the environment
      # @return [String, nil] an absolute path, or nil when there is none
      def locate(explicit = nil, from: Dir.pwd, env: ENV)
        candidate = explicit || env[ENV_VAR]
        return File.expand_path(candidate, from) if candidate && !candidate.empty?

        Pathname(from).expand_path.ascend { |dir| return dir.join(FILE).to_s if dir.join(FILE).file? }
        nil
      end

      # Loads the helper, once.
      #
      # @param path [String, nil] nothing is loaded for nil
      # @return [Boolean] whether a helper was loaded
      # @raise [Error] when the path does not exist
      def load!(path)
        return false if path.nil?
        raise Error, "no eval helper at #{path}" unless File.file?(path)

        require File.expand_path(path)
        true
      end
    end
  end
end
