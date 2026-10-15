# frozen_string_literal: true

module Agent
  module Evals
    # Checks a Hash of answers against a field map, for scorers and verifiers
    # whose expected values are typed and closed. Nothing here is specific to
    # what the fields mean.
    #
    # The map is `{ "name" => { type:, enum:, nullable: } }`; `type` is one of
    # {TYPES}, `enum` lists the allowed values for enum and multi_enum, and a
    # nullable field accepts nil (the text never answered it).
    class SchemaValidator
      TYPES = %i[boolean integer number string enum multi_enum].freeze

      attr_reader :fields

      # @param fields [Hash{String, Symbol => Hash}]
      # @raise [ArgumentError] on a type outside {TYPES}, since a typo there would pass everything
      def initialize(fields)
        @fields = fields.to_h { |name, spec| [name.to_s, normalize(name, spec)] }.freeze
      end

      # @return [Array<String>] the field names
      def names = fields.keys

      # @param values [Hash] String or Symbol keys
      # @return [Array<String>] every problem found; empty when the values fit the map
      def problems(values)
        return ["#{values.inspect} is not a Hash"] unless values.is_a?(Hash)

        actual = values.transform_keys(&:to_s)
        missing = names - actual.keys
        extra = actual.keys - names
        problems = []
        problems << "missing #{missing.join(", ")}" if missing.any?
        problems << "unknown fields #{extra.join(", ")}" if extra.any?
        fields.each do |name, spec|
          next unless actual.key?(name)

          problem = value_problem(spec, actual[name])
          problems << "#{name}: #{problem}" if problem
        end
        problems
      end

      # @param values [Hash]
      # @return [Boolean]
      def valid?(values) = problems(values).empty?

      # @param spec [Hash] one field's normalized spec
      # @param value [Object]
      # @return [String, nil] what is wrong with the value, or nil
      def value_problem(spec, value)
        return (spec[:nullable] ? nil : "is null") if value.nil?

        case spec[:type]
        when :boolean then "#{value.inspect} is not a boolean" unless [true, false].include?(value)
        when :integer then "#{value.inspect} is not an integer" unless value.is_a?(Integer)
        when :number then "#{value.inspect} is not a number" unless value.is_a?(Numeric)
        when :string then "#{value.inspect} is not a string" unless value.is_a?(String)
        when :enum then "#{value.inspect} is not one of #{spec[:enum].join("|")}" unless spec[:enum].include?(value)
        when :multi_enum then multi_enum_problem(spec, value)
        end
      end

      private

      def multi_enum_problem(spec, value)
        return "#{value.inspect} is not an array" unless value.is_a?(Array)

        stray = value - spec[:enum]
        "#{stray.join(", ")} not in #{spec[:enum].join("|")}" if stray.any?
      end

      def normalize(name, spec)
        spec = spec.transform_keys(&:to_sym)
        type = spec.fetch(:type).to_sym
        raise ArgumentError, "#{name}: unknown type #{type.inspect}, expected one of #{TYPES.join(", ")}" unless TYPES.include?(type)

        { type: type, enum: Array(spec[:enum] || spec[:values]).map(&:to_s), nullable: spec.fetch(:nullable, false) }
      end
    end
  end
end
