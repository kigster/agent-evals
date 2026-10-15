# frozen_string_literal: true

module Agent
  module Evals
    # Where a run's results go besides the terminal. The gem always owns the
    # run loop; a tracker only receives callbacks: {#start} once per
    # experiment, {#record} once per finished case, {#finish} once with the
    # summary. The local JSON log ({Trackers::Local}) always runs; at most
    # one remote tracker runs beside it, chosen by `--tracker`, the
    # `tracker:` key, or the environment (see {Trackers::Registry#choose}).
    #
    # A tracker for another framework (W&B Weave, an OTLP backend) subclasses
    # this in a consumer or a plugin gem and is registered with `c.tracker`.
    #
    # @abstract Override the three callbacks; declare {.env_key} and {.gems}.
    class Tracker
      class << self
        # @return [String] the name `--tracker` and `tracker:` use; the class name, dasherized, by default
        def tracker_name = (name || "Tracker").split("::").last.gsub(/([a-z\d])([A-Z])/, '\1-\2').downcase

        # @return [String, nil] the environment variable whose presence selects this tracker when nothing else does
        def env_key = nil

        # @return [Array<String>] the optional gems this tracker requires when chosen
        def gems = []

        # @param env [Hash] the environment
        # @return [Boolean] whether the environment names this tracker
        def detect?(env = ENV) = !env_key.nil? && !env[env_key].to_s.strip.empty?

        # Loads the gems and checks the key, with an error that names both, so
        # a chosen tracker that cannot run says so before any model is called.
        #
        # @param env [Hash]
        # @return [void]
        # @raise [MissingDependency, Error]
        def requirements!(env = ENV)
          gems.each do |gem_name|
            Agent::Evals.optional!(gem_name.tr("-", "/"), gem_name, needed_for: "the #{tracker_name} tracker")
          end
          return if env_key.nil? || detect?(env)

          raise Error, "the #{tracker_name} tracker needs #{env_key} in the environment (gems: #{gems.join(", ")})"
        end
      end

      attr_reader :context

      # @param context [Hash] `suite:`, `project:`, `project_id:` and `options:` (the tracker's own key in the config file)
      def initialize(**context)
        @context = context
      end

      # @return [String]
      def name = self.class.tracker_name

      # @return [Boolean] false turns every callback into a no-op
      def enabled? = true

      # @return [String] one line for `--verbose`: where this tracker sends things, and why
      def describe = name

      # @param experiment [Experiment]
      # @return [void]
      def start(_experiment) = nil

      # @param result [RunResult]
      # @return [void]
      def record(_result) = nil

      # @param experiment [Experiment]
      # @param summary [Experiment::Summary]
      # @return [Hash] `url:` to the experiment when one is known, else nil
      def finish(_experiment, _summary) = { url: nil }

      # @return [Hash] the tracker's own section of the config file
      def options = context.fetch(:options, nil) || {}
    end
  end
end
