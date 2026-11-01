# frozen_string_literal: true

module LLM
  module Evals
    module CLI
      # Each model's bright color for one run, chosen at random and kept, so a
      # model looks the same in its progress bars and in the tables after them.
      class ModelColors
        # What a model can be drawn in. More models than these share them.
        COLORS = %i[bright_red bright_green bright_yellow bright_blue bright_magenta bright_cyan bright_white].freeze

        def initialize
          palette = COLORS.shuffle
          @colors = Hash.new { |colors, model| colors[model] = palette[colors.size % palette.size] }
        end

        # @param model [String] the model's id
        # @return [Symbol] a Pastel style
        def [](model) = @colors[model]
      end
    end
  end
end
