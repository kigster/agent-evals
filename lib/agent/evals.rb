# frozen_string_literal: true

require "etc"
require "json"
require "dry/cli"
require "dry/cli/help"
require "dry/cli/ui"
require "dry/cli/autocomplete/command"
require "zeitwerk"

module Agent
  # A generic evaluation runner with a one-way boundary. The consumer suite
  # registers an {Adapter}, which runs one {Case} against a {Model} and
  # returns a {Reply} without scoring it, and a {Scorer}, which turns a reply
  # into a {Score} without calling anything. Everything else, from discovery
  # to the leaderboard, is this gem's, and none of it knows what is being
  # evaluated.
  module Evals
    class Error < StandardError; end

    # Raised by a command that needs an optional gem the bundle does not hold.
    class MissingDependency < Error; end

    class << self
      # The suite's settings, filled in by {.configure} from `evals/eval_helper.rb`.
      #
      # @return [Configuration]
      def configuration
        @configuration ||= Configuration.new
      end

      # Builds the suite's configuration. Called once from the eval helper.
      #
      # @example evals/eval_helper.rb
      #   Agent::Evals.configure do |c|
      #     c.suite "extract", root: __dir__, env_files: ["../.env"]
      #     c.cases "datasets/*/cases/**/input.txt"
      #     c.adapter ExtractAdapter.new
      #     c.scorer ExtractScorer.new
      #     c.before_run { MyGem.reset_configuration! }
      #   end
      #
      # @yieldparam configuration [Configuration]
      # @return [Configuration]
      def configure
        yield configuration
        configuration
      end

      # Forgets the configuration, so a spec that loads a second helper starts clean.
      #
      # @return [void]
      def reset!
        @configuration = nil
      end

      # @return [Boolean] whether a helper has registered an adapter and a scorer
      def configured? = configuration.complete?

      # Requires an optional gem the moment a command needs it, and names it
      # when it is missing, instead of letting a bare LoadError surface three
      # frames deep in a provider.
      #
      # @param feature [String] what to require, e.g. "ruby_llm"
      # @param gem_name [String] the gem to add to the Gemfile; the feature when they agree
      # @param needed_for [String] what the user was doing
      # @return [void]
      # @raise [MissingDependency]
      def optional!(feature, gem_name = feature, needed_for:)
        require feature
      rescue LoadError
        raise MissingDependency, "#{needed_for} needs the #{gem_name} gem: add `gem \"#{gem_name}\"` to your Gemfile"
      end
    end
  end
end

require_relative "evals/version"

loader = Zeitwerk::Loader.for_gem_extension(Agent)
loader.inflector.inflect("cli" => "CLI", "html" => "HTML", "json" => "JSON")
loader.ignore(File.expand_path("evals/version.rb", __dir__))
loader.setup
