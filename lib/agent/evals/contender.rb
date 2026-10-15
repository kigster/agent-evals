# frozen_string_literal: true

module Agent
  module Evals
    # One model at one setting: what a single experiment runs. Built by
    # {Config} from the lineup file, or from `-m` on the command line.
    Contender = Data.define(:model, :effort, :temperature, :max_tokens) do
      # The settings as a {Model} takes them: "default" means nil, send nothing.
      #
      # @return [Hash{Symbol => Object}]
      def settings
        { effort:      effort.to_s == "default" || effort.nil? ? nil : effort.to_s,
          temperature: temperature.to_s == "default" || temperature.nil? ? nil : Float(temperature),
          max_tokens:  max_tokens.nil? ? nil : Integer(max_tokens) }
      end
    end
  end
end
