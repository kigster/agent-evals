# frozen_string_literal: true

module Agent
  module Evals
    module CLI
      class Version < Command
        desc "Print the version"

        def call(**)
          out.puts Agent::Evals::VERSION
        end
      end
    end
  end
end
