# frozen_string_literal: true

module LLM
  module Evals
    # Every command the executable answers to. The help's title and
    # description come from the suite's configuration, which the executable
    # loads before this module is first referenced.
    module CLI
      extend Dry::CLI::Registry

      PROGRAM = "llm-evals"

      Dry::CLI::Help.configure do
        configuration = LLM::Evals.configuration
        title configuration.name == PROGRAM ? PROGRAM : "#{PROGRAM} (#{configuration.name})"
        types = configuration.providers.uniq(&:request_type).map { "#{it.request_type} (#{it.request_type_description})" }
        description "#{configuration.description} Request types: #{types.join("; ")}."

        columns = IO.console&.winsize&.last || 80
        width columns.clamp(60, 120)
        exit_code_without_arguments 0

        styles do
          heading :bold, :cyan, case: :UPPERCASE
          usage :yellow
          example :yellow
          option :green
          example_comment :bright_black
        end
      end

      register "run", Run
      register "compare", Compare
      register "render", Render
      register "cases", Cases
      register "verify", Verify
      register "version", Version, aliases: ["-V", "--version"]
      register "completion", Dry::CLI::Autocomplete::Command[self, program_name: PROGRAM]
    end
  end
end
