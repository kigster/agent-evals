# frozen_string_literal: true

module Agent
  module Evals
    # Finds the cases under a root with a glob and decodes each path into a
    # {Case}. The default layout is
    #
    #   datasets/<dataset>/cases/<variant>/[NNN/]input.txt
    #   datasets/<dataset>/cases/<variant>/[NNN/]expected.json
    #
    # The folder after `datasets/` is the dataset, the folder holding the
    # input is the variant, unless it is a number, in which case it is the
    # case number and its parent is the variant.
    class Discovery
      EXPECTED = "expected.json"
      METADATA = "metadata.json"

      attr_reader :root, :glob

      # @param root [String] an absolute directory
      # @param glob [String] relative to root
      def initialize(root:, glob: Configuration::DEFAULT_GLOB)
        @root = root
        @glob = glob
      end

      # @return [Array<String>] every dataset that has at least one case, sorted
      def datasets = all.map(&:dataset).uniq.sort

      # @param dataset [String, nil] one dataset; nil for all of them
      # @param only [Array<String>] id prefixes to keep ("clear", "clear/00"); empty keeps all
      # @return [Array<Case>] sorted by dataset, variant and number
      # @raise [Error] when the dataset does not exist
      def cases(dataset: nil, only: [])
        found = all
        if dataset
          raise Error, "no dataset #{dataset.inspect}; have #{datasets.join(", ")}" unless datasets.include?(dataset)

          found = found.select { it.dataset == dataset }
        end
        only = only.flat_map { it.split(",") }.map(&:strip).reject(&:empty?)
        found = found.select { |kase| only.any? { kase.id.start_with?(it) || kase.key.start_with?(it) } } unless only.empty?
        found
      end

      # @return [Array<Case>]
      def all
        @all ||= Dir[File.join(root, glob)].map { decode(it) }
      end

      # Builds the case at one input file.
      #
      # @param input_path [String]
      # @return [Case]
      def decode(input_path)
        dir = File.dirname(input_path)
        parts = Pathname(dir).relative_path_from(Pathname(root)).each_filename.to_a
        number = parts.last.match?(/\A\d+\z/) ? parts.last : nil
        variant = number ? parts[-2] : parts.last
        expected, problem = read_expected(File.join(dir, EXPECTED))
        Case.new(
          id:       [variant, number].compact.join("/"),
          dataset:  dataset_of(parts),
          variant:  variant,
          input:    File.read(input_path).strip,
          expected: expected,
          path:     dir,
          metadata: metadata(dir, number, problem)
        )
      end

      private

      # The folder after `datasets/`, else the first folder, so a glob that
      # does not say `datasets` still groups by its top level.
      def dataset_of(parts)
        index = parts.index("datasets")
        index && parts[index + 1] ? parts[index + 1] : parts.first
      end

      def read_expected(path)
        return [nil, "#{EXPECTED} is missing"] unless File.exist?(path)

        [JSON.parse(File.read(path)), nil]
      rescue JSON::ParserError => e
        [nil, "#{EXPECTED} is not valid JSON: #{e.message.lines.first&.strip}"]
      end

      def metadata(dir, number, problem)
        extra = File.exist?(File.join(dir, METADATA)) ? JSON.parse(File.read(File.join(dir, METADATA))).transform_keys(&:to_sym) : {}
        { number: number&.to_i, difficulty: number.to_i, expected_error: problem }.compact.merge(extra)
      end
    end
  end
end
