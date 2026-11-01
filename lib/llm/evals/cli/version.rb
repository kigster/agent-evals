# frozen_string_literal: true

module LLM
  module Evals
    module CLI
      class Version < Command
        desc "Print the version"

        def call(**)
          out.puts LLM::Evals::VERSION
        end
      end
    end
  end
end
