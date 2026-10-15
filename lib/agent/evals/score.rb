# frozen_string_literal: true

module Agent
  module Evals
    # What a {Scorer} says about one reply. `value` is the case's overall
    # score in 0..1; `metrics` holds one entry per {Metric} the scorer
    # declares, nil where the case does not apply; `outcomes` and
    # `diagnostics` are free-form, keyed by field, and only ever displayed.
    Score = Data.define(:value, :metrics, :outcomes, :diagnostics) do
      def initialize(value:, metrics: {}, outcomes: {}, diagnostics: {})
        raise ArgumentError, "score value #{value.inspect} is not within 0..1" unless value.is_a?(Numeric) && (0..1).cover?(value)

        super(value: value.to_f, metrics: metrics.transform_keys(&:to_s), outcomes: outcomes, diagnostics: diagnostics)
      end

      # The score of a reply the model failed: 0 everywhere, the failure as a diagnostic.
      #
      # @param metrics [Array<Metric>]
      # @param error [String]
      # @return [Score]
      def self.failed(metrics, error)
        new(value: 0.0, metrics: metrics.to_h { [it.name, 0.0] }, diagnostics: { "error" => error })
      end
    end
  end
end
