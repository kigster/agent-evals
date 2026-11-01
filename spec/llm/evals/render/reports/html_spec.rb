# frozen_string_literal: true

RSpec.describe LLM::Evals::Render::Reports::HTML do
  describe "the report template" do
    let(:template_paths) do
      %w[
        lib/llm/evals/templates/html_report.html.erb
        lib/llm/evals/templates/html_report.css
        lib/llm/evals/templates/html_report.js
      ]
    end
    let(:gem_specification) { Gem::Specification.load(File.expand_path("../../../../../llm-evals.gemspec", __dir__)) }

    it "includes the template and assets in the built gem" do
      expect(gem_specification.files).to include(*template_paths)
    end
  end

  describe "ranking and case details" do
    let(:configuration) { LLM::Evals.configuration }
    let(:metrics) { [LLM::Evals::Metric.new(name: "accuracy")] }
    let(:echo_model) { build_model("fake/echo") }
    let(:parrot_model) { build_model("fake/parrot") }
    let(:case_one) { build_case("partial/001", number: 1) }
    let(:case_two) { build_case("partial/002", number: 2) }
    let(:case_three) { build_case("partial/003", number: 3) }

    def build_model(id)
      LLM::Evals::Model.new(id:, provider: configuration.providers.for(id))
    end

    def build_case(id, number:, dataset: "coverage")
      LLM::Evals::Case.new(
        id:,
        dataset:,
        variant: "partial",
        input: "case input",
        expected: {},
        path: "",
        metadata: { number: }
      )
    end

    def build_run(model:, kase:, score: nil, reply: nil, error: nil)
      LLM::Evals::RunResult.new(
        experiment: instance_double(LLM::Evals::Experiment, model:),
        case:       kase,
        score:,
        reply:,
        error:
      )
    end

    def build_summary(model:, results:, usage: LLM::Evals::Usage.zero, dataset: "coverage")
      LLM::Evals::Experiment::Summary.new(
        model:,
        dataset:,
        name: "coverage experiment",
        means: {},
        results:,
        errors: [],
        duration: 0,
        permalink: nil,
        usage:
      )
    end

    def scored_run(model:, kase:, accuracy:, value: nil)
      build_run(
        model:,
        kase:,
        score: LLM::Evals::Score.new(value: value || accuracy, metrics: { "accuracy" => accuracy }),
        reply: LLM::Evals::Reply.new(output: { "value" => accuracy })
      )
    end

    def render_report(summaries, weighted_score: nil)
      json = LLM::Evals::Render::Reports::JSON.dump(summaries, metrics:, weighted_score:)
      decoded = LLM::Evals::Render::Reports::JSON.decode(json, providers: configuration.providers)
      described_class.render(decoded)
    end

    it "shows best coverage without naming a leader when no contender covers every case" do
      report = render_report([
                               build_summary(model: echo_model, results: [scored_run(model: echo_model, kase: case_one, accuracy: 0.8)]),
                               build_summary(model: parrot_model, results: [scored_run(model: parrot_model, kase: case_two, accuracy: 0.7)])
                             ])

      expect(report).to include(
        "No leader established",
        "Best coverage: 1/2",
        "No contender covered all 2 cases without failures"
      )
    end

    it "escapes transport and model reply errors and labels unscored cases" do
      report = render_report([
                               build_summary(model: echo_model,
                                 results: [
                                   build_run(model: echo_model, kase: case_one, error: "transport <script>alert(1)</script>"),
                                   build_run(model: echo_model,
                                     kase: case_two,
                                     reply: LLM::Evals::Reply.new(error: "reply <script>alert(2)</script>"),
                                     score: LLM::Evals::Score.failed(metrics, "reply <script>alert(2)</script>")),
                                   build_run(model: echo_model, kase: case_three)
                                 ])
                             ])

      expect(report).to include(
        "failed or unscored cases",
        "transport &lt;script&gt;alert(1)&lt;/script&gt;",
        "reply &lt;script&gt;alert(2)&lt;/script&gt;",
        "No score"
      )
      expect(report).not_to include("transport <script>", "reply <script>")
    end

    it "rounds recorded cost upward to the nearest cent" do
      summary = build_summary(
        model:   echo_model,
        results: [scored_run(model: echo_model, kase: case_one, accuracy: 0.8)],
        usage:   LLM::Evals::Usage.new(input_tokens: 1, output_tokens: 1, cost_usd: 0.001)
      )

      expect(render_report([summary])).to include("<b>$0.01</b>", "$0.01")
    end

    it "shows per-experiment token totals and aggregates them across datasets" do
      bookkeeping_case = build_case("partial/001", number: 1, dataset: "bookkeeping")
      therapy_case = build_case("partial/001", number: 1, dataset: "therapy")
      report = render_report([
                               build_summary(model: echo_model,
                                 dataset: "bookkeeping",
                                 results: [scored_run(model: echo_model, kase: bookkeeping_case, accuracy: 0.9)],
                                 usage: LLM::Evals::Usage.new(input_tokens: 1234, output_tokens: 321, cost_usd: 0.01)),
                               build_summary(model: echo_model,
                                 dataset: "therapy",
                                 results: [scored_run(model: echo_model, kase: therapy_case, accuracy: 0.8)],
                                 usage: LLM::Evals::Usage.new(input_tokens: 3456, output_tokens: 789, cost_usd: 0.02))
                             ])

      expect(report).to include("↓ Tokens in", "↑ Tokens out", "1,234", "321", "3,456", "789", "4,690", "1,110")
    end

    it "adds section navigation and opens dataset score sections by default" do
      kase = build_case("partial/001", number: 1, dataset: "bookkeeping")
      report = render_report([
                               build_summary(model: echo_model,
                                 dataset: "bookkeeping",
                                 results: [scored_run(model: echo_model, kase:, accuracy: 0.9)])
                             ])

      expect(report).to include('href="#overview"', 'href="#standings"', 'href="#coverage"', 'href="#dataset-1"')
      expect(report).to include('<details class="dataset" id="dataset-1" open>')
    end

    context "with a weighted score" do
      let(:weighted_score) { LLM::Evals::WeightedScore.new({ "accuracy" => 1.0 }, metrics: ["accuracy"]) }
      let(:weighted_summaries) do
        [
          build_summary(model: echo_model, results: [scored_run(model: echo_model, kase: case_one, accuracy: 0.9, value: 0.6)]),
          build_summary(model: parrot_model, results: [scored_run(model: parrot_model, kase: case_one, accuracy: 0.2, value: 0.95)])
        ]
      end
      let(:report) { render_report(weighted_summaries, weighted_score:) }

      it "uses the configured score to select and label the leader" do
        expect(report).to include(
          "Weighted score from the lineup",
          "ALL-CASE LEADER",
          '<span class="model-id">echo</span>',
          "90.0%"
        )
      end

      it "sorts the coverage table from highest weighted score to lowest" do
        leader_row = '<td><span class="provider">fake</span></td><td><span class="model-id">echo</span></td>'
        runner_up_row = '<td><span class="provider">fake</span></td><td><span class="model-id">parrot</span></td>'
        coverage_table = report[%r{<h3 id="coverage">Coverage by model</h3>\s*<div class="scroll">\s*<table class="sortable">(.*?)</table>}m, 1]

        expect(coverage_table.index(leader_row)).to be < coverage_table.index(runner_up_row)
      end

      it "shows weighted and primary scores as sortable columns beside the bars" do
        hero_table = report[%r{<table class="sortable standings-table"[^>]*>(.*?)</table>}m, 1]

        expect(hero_table).to include(
          "<th><span>Provider</span><span>(vendor)</span></th>",
          "<th><span>Model</span><span>(ID and settings)</span></th>",
          "<th><span>Weighted</span><span>score</span></th>",
          "<th><span>Primary score</span><span>(score)</span></th>",
          "<th class=\"standings-bar\"><span>Score</span><span>bar</span></th>",
          "90.0%",
          "60.0%",
          "20.0%",
          "95.0%"
        )
        expect(hero_table).to include('<span class="model-id">echo</span> <span class="standings-settings">(default, t=default)</span>')
        expect(hero_table.index('class="model-id">echo')).to be < hero_table.index('class="model-id">parrot')
      end
    end
  end

  describe "escaping values loaded from JSON" do
    let(:payload) { "<script>alert(1)</script>" }
    let(:document) do
      {
        format: LLM::Evals::Render::Reports::JSON::FORMAT, version: LLM::Evals::Render::Reports::JSON::VERSION,
        suite: "demo", metrics: [{ name: "accuracy", primary: true }],
        summaries: [{
          model: { id: "fake/echo", provider: "fake" }, dataset: "colors", name: "fake/echo",
          means: { "accuracy" => 1.0 }, errors: [payload],
          usage: { input_tokens: payload, output_tokens: payload },
          results: [{
            case: { id: "clear/001", dataset: "colors", variant: "clear", input: "in", expected: nil, metadata: { difficulty: payload } },
            reply: { output: {}, raw: "", usage: { input_tokens: payload, output_tokens: payload } },
            score: { value: 1, metrics: { "accuracy" => 1 } }, duration: 0.1
          }]
        }]
      }
    end
    let(:html) do
      providers = LLM::Evals.configuration.providers
      described_class.render(LLM::Evals::Render::Reports::JSON.decode(JSON.generate(document), providers:))
    end

    it "never emits the injected markup" do
      expect(html).not_to include(payload)
    end

    it "shows the difficulty escaped" do
      expect(html).to include("difficulty #{CGI.escapeHTML(payload)}")
    end
  end
end
