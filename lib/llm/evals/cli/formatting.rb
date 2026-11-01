# frozen_string_literal: true

module LLM
  module Evals
    module CLI
      # How a command prints the numbers every report shares.
      module Formatting
        private

        def percent(value) = value.nil? ? "-" : format("%.1f%%", value * 100)

        def dollars(value) = format("$%.4f", value.to_f)
      end
    end
  end
end
