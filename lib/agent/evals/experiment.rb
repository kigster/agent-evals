# frozen_string_literal: true

module Agent
  module Evals
    # One model at one setting over every case of one dataset, run on a
    # thread pool the gem owns, plus the per-case detail the terminal report
    # needs. Trackers only watch: {Trackers::Local} always, and at most one
    # remote tracker, each told when the experiment starts, when a case
    # finishes, and what the summary was.
    class Experiment
      # What one finished experiment reports back. `means` holds one entry
      # per metric plus "score", the mean of each case's overall value;
      # `usage` is summed over the cases; `permalink` is the remote tracker's
      # page, when it has one.
      Summary = Data.define(:model, :dataset, :name, :means, :results, :errors, :duration, :permalink, :usage) do
        # @return [Float, nil] the mean overall score
        def score = means["score"]

        # @param metric [Metric, String]
        # @return [Float, nil]
        def mean(metric) = means[metric.respond_to?(:name) ? metric.name : metric.to_s]

        # The same experiment over one variant's cases. Its duration is the sum
        # of those cases' own, since they overlapped with the others.
        #
        # @param variant [String]
        # @param metrics [Array<Metric>] the scorer's
        # @return [Summary]
        def for_variant(variant, metrics)
          chosen = results.select { it.case.variant == variant }
          with(means:    Experiment.means(metrics, chosen),
            results:  chosen,
            errors:   chosen.select(&:failed?).map { "#{it.case.key}: #{it.error}" },
            duration: chosen.sum(&:duration),
            usage:    Experiment.usage(chosen))
        end
      end

      # @param metrics [Array<Metric>]
      # @param results [Array<RunResult>]
      # @return [Hash{String => Float, nil}] one mean per metric, plus "score"
      def self.means(metrics, results)
        scored = results.filter_map(&:score)
        means = metrics.to_h { |metric| [metric.name, metric.combine(scored.map { it.metrics[metric.name] })] }
        means.merge("score" => scored.empty? ? nil : scored.sum(&:value).fdiv(scored.size))
      end

      # @param results [Array<RunResult>]
      # @return [Usage] summed over the results
      def self.usage(results) = results.filter_map(&:reply).map(&:usage).reduce(Usage.zero, :+)

      attr_reader :model, :adapter, :scorer, :cases, :dataset, :parallelism, :trackers

      # @param model [Model]
      # @param cases [Array<Case>] all of one dataset
      # @param adapter [Adapter]
      # @param scorer [Scorer]
      # @param parallelism [Integer] cases in flight at once
      # @param trackers [Array<Tracker>] told about the run, in this order
      def initialize(model:, cases:, adapter:, scorer:, parallelism: 4, trackers: [])
        raise ArgumentError, "an experiment needs at least one case" if cases.empty?

        @model = model
        @cases = cases.sort_by { [it.variant, it.number || 0, it.id] }
        @dataset = cases.first.dataset
        @adapter = adapter
        @scorer = scorer
        @parallelism = [parallelism.to_i, 1].max
        @trackers = trackers.select(&:enabled?)
        @results = {}
        @lock = Mutex.new
      end

      # @return [String] e.g. "anthropic/claude-haiku-5.5 effort=low t=0.0 [clear]"
      def name = "#{model} [#{dataset}]"

      # @param on_case [#call, nil] called once per finished case
      # @return [Summary]
      def run(on_case: nil)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        adapter.prepare(dataset)
        trackers.each { it.start(self) }
        errors = run_locally(on_case)
        summary = summarize(errors, nil, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
        urls = trackers.map { it.finish(self, summary)&.fetch(:url, nil) }
        summary.with(permalink: urls.compact.first)
      end

      # Runs one case: the adapter, then the scorer. A reply the model failed
      # (`Reply#error`) scores 0 without troubling the scorer; an exception is
      # the transport's and is left to the caller, which counts it as an error.
      #
      # @param kase [Case]
      # @return [RunResult]
      def evaluate(kase)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        reply = adapter.call(kase, model: model)
        raise Error, "#{adapter.class}#call returned #{reply.class}, not an Agent::Evals::Reply" unless reply.is_a?(Reply)

        score = reply.error? ? Score.failed(scorer.metrics, reply.error) : scorer.call(kase, reply, context: adapter.context(kase))
        RunResult.new(experiment: self,
          case: kase,
          reply: reply,
          score: score,
          duration: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      end

      private

      # Remembers a result and tells the trackers, under one lock, so a
      # tracker sees results one at a time and in the order they are kept.
      def remember(result)
        @lock.synchronize do
          @results[result.case.key] = result
          trackers.each { it.record(result) }
        end
        result
      end

      # A fixed pool of threads over a queue: `parallelism` cases in flight.
      def run_locally(on_case)
        queue = Queue.new
        cases.each { queue << it }
        queue.close
        errors = Queue.new
        Array.new([parallelism, cases.size].min) do
          Thread.new do
            while (kase = queue.pop)
              begin
                remember evaluate(kase)
              rescue StandardError => e
                remember RunResult.new(experiment: self, case: kase, error: "#{e.class}: #{e.message}")
                errors << "#{kase.key}: #{e.class}: #{e.message}"
              end
              on_case&.call
            end
          end
        end.each(&:join)
        Array.new(errors.size) { errors.pop }
      end

      def summarize(errors, permalink, duration)
        results = @lock.synchronize { @results.values }.sort_by { cases.index(it.case) }
        Summary.new(
          model:     model,
          dataset:   dataset,
          name:      name,
          means:     self.class.means(scorer.metrics, results),
          results:   results,
          errors:    Array(errors),
          duration:  duration,
          permalink: permalink,
          usage:     self.class.usage(results)
        )
      end
    end
  end
end
