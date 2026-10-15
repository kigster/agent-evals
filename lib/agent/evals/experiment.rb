# frozen_string_literal: true

module Agent
  module Evals
    # One model at one setting over every case of one dataset: a single
    # Braintrust experiment when a project is given, a local run otherwise,
    # plus the per-case detail the terminal report needs.
    #
    # The adapter and the scorer are called the same way on both paths; the
    # Braintrust path only adds the recording. Local runs never load the
    # braintrust gem.
    class Experiment
      # What one finished experiment reports back. `means` holds one entry
      # per metric plus "score", the mean of each case's overall value;
      # `usage` is summed over the cases.
      Summary = Data.define(:model, :dataset, :name, :means, :results, :errors, :duration, :permalink, :usage) do
        # @return [Float, nil] the mean overall score
        def score = means["score"]

        # @param metric [Metric, String]
        # @return [Float, nil]
        def mean(metric) = means[metric.respond_to?(:name) ? metric.name : metric.to_s]
      end

      attr_reader :model, :adapter, :scorer, :cases, :dataset, :parallelism

      # @param model [Model]
      # @param cases [Array<Case>] all of one dataset
      # @param adapter [Adapter]
      # @param scorer [Scorer]
      # @param project [String, nil] Braintrust project name, created when missing
      # @param project_id [String, nil] Braintrust project UUID; wins over the name
      # @param parallelism [Integer] cases in flight at once
      # @param suite [String] tags the experiment
      # With neither project nor project_id the experiment runs locally.
      def initialize(model:, cases:, adapter:, scorer:, project: nil, project_id: nil, parallelism: 4, suite: "agent-evals")
        raise ArgumentError, "an experiment needs at least one case" if cases.empty?

        @model = model
        @cases = cases.sort_by { [it.variant, it.number || 0, it.id] }
        @by_key = @cases.to_h { [it.key, it] }
        @dataset = cases.first.dataset
        @adapter = adapter
        @scorer = scorer
        @project = project_id ? nil : project
        @project_id = project_id
        @parallelism = [parallelism.to_i, 1].max
        @suite = suite
        @results = {}
        @lock = Mutex.new
      end

      # @return [String] e.g. "anthropic/claude-haiku-5.5 effort=low t=0.0 [clear]"
      def name = "#{model} [#{dataset}]"

      # @return [Boolean] whether the run is recorded in Braintrust
      def braintrust? = !(@project.nil? && @project_id.nil?)

      # @param on_case [#call, nil] called once per finished case
      # @return [Summary]
      def run(on_case: nil)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        adapter.prepare(dataset)
        errors, permalink = braintrust? ? run_in_braintrust(on_case) : run_locally(on_case)
        summarize(errors, permalink, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
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
        remember RunResult.new(experiment: self,
          case: kase,
          reply: reply,
          score: score,
          duration: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      end

      # @return [Array<Hash>] Braintrust cases, one per case
      def braintrust_cases
        cases.map do |kase|
          { input: { case: kase.key, text: kase.input }, expected: kase.expected,
            metadata: { case: kase.key, difficulty: kase.difficulty, dataset: dataset, variant: kase.variant },
            tags: ["variant-#{kase.variant}", "dataset-#{dataset}"] }
        end
      end

      # The Braintrust task: the reply's output, or `_error` when the model failed.
      #
      # @return [#call]
      def task
        lambda do |input:|
          result = evaluate(@by_key.fetch(input[:case] || input["case"]))
          output = result.reply.output
          output = output.transform_keys(&:to_s) if output.is_a?(Hash)
          result.reply.error? ? { "_error" => result.reply.error } : output
        end
      end

      # One Braintrust scorer per metric, reading the {Score} the task already
      # computed, so Braintrust records exactly what the terminal shows. A nil
      # metric records nothing (not 0), so it does not drag the mean.
      #
      # @return [Array<Braintrust::Scorer>]
      def scorers
        scorer.metrics.map do |metric|
          Braintrust::Scorer.new(metric.name) do |metadata:|
            result = @lock.synchronize { @results[metadata[:case] || metadata["case"]] }
            value = result.score.metrics[metric.name] if result&.score
            value.nil? ? [] : { score: value, metadata: result.score.diagnostics }
          end
        end
      end

      private

      def remember(result)
        @lock.synchronize { @results[result.case.key] = result }
        result
      end

      # A fixed pool of threads over a queue: `parallelism` cases in flight,
      # as the Braintrust runner does it, so the two paths load a provider the same way.
      def run_locally(on_case)
        queue = Queue.new
        cases.each { queue << it }
        queue.close
        errors = Queue.new
        Array.new([parallelism, cases.size].min) do
          Thread.new do
            while (kase = queue.pop)
              begin
                evaluate(kase)
              rescue StandardError => e
                remember RunResult.new(experiment: self, case: kase, error: "#{e.class}: #{e.message}")
                errors << "#{kase.key}: #{e.class}: #{e.message}"
              end
              on_case&.call
            end
          end
        end.each(&:join)
        [Array.new(errors.size) { errors.pop }, nil]
      end

      def run_in_braintrust(on_case)
        Agent::Evals.optional!("braintrust", needed_for: "recording experiments in Braintrust")
        result = Braintrust::Eval.run(
          project:     @project,
          project_id:  @project_id,
          experiment:  name,
          cases:       braintrust_cases,
          task:        task,
          scorers:     scorers,
          parallelism: parallelism,
          quiet:       true,
          on_progress: ->(_) { on_case&.call },
          metadata:    { model: model.id, dataset: dataset, **model.settings, **adapter.metadata },
          tags:        [@suite, model.id, "dataset-#{dataset}"]
        )
        [result.errors, result.permalink]
      end

      def summarize(errors, permalink, duration)
        results = @lock.synchronize { @results.values }.sort_by { cases.index(it.case) }
        scored = results.filter_map(&:score)
        means = scorer.metrics.to_h { |metric| [metric.name, metric.combine(scored.map { it.metrics[metric.name] })] }
        means["score"] = scored.empty? ? nil : scored.sum(&:value).fdiv(scored.size)
        Summary.new(
          model:     model,
          dataset:   dataset,
          name:      name,
          means:     means,
          results:   results,
          errors:    Array(errors),
          duration:  duration,
          permalink: permalink,
          usage:     results.filter_map(&:reply).map(&:usage).reduce(Usage.zero, :+)
        )
      end
    end
  end
end
