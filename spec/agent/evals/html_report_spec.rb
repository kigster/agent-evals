# frozen_string_literal: true

RSpec.describe Agent::Evals::HtmlReport do
  describe "the report template" do
    let(:template_paths) do
      %w[
        lib/agent/evals/templates/html_report.html.erb
        lib/agent/evals/templates/html_report.css
        lib/agent/evals/templates/html_report.js
      ]
    end
    let(:gem_specification) { Gem::Specification.load(File.expand_path("../../../agent-evals.gemspec", __dir__)) }

    it "includes the template and assets in the built gem" do
      expect(gem_specification.files).to include(*template_paths)
    end
  end

  describe "ranking and case details" do
    let(:configuration) { Agent::Evals.configuration }
    let(:metrics) { [Agent::Evals::Metric.new(name: "accuracy", primary: true)] }
    let(:echo_model) { build_model("fake/echo") }
    let(:parrot_model) { build_model("fake/parrot") }
    let(:case_one) { build_case("partial/001", number: 1) }
    let(:case_two) { build_case("partial/002", number: 2) }
    let(:case_three) { build_case("partial/003", number: 3) }

    def build_model(id)
      Agent::Evals::Model.new(id:, provider: configuration.providers.for(id))
    end

    def build_case(id, number:)
      Agent::Evals::Case.new(
        id:,
        dataset: "coverage",
        variant: "partial",
        input: "case input",
        expected: {},
        path: "",
        metadata: { number: }
      )
    end

    def build_run(model:, kase:, score: nil, reply: nil, error: nil)
      Agent::Evals::RunResult.new(
        experiment: instance_double(Agent::Evals::Experiment, model:),
        case:       kase,
        score:,
        reply:,
        error:
      )
    end

    def build_summary(model:, results:)
      Agent::Evals::Experiment::Summary.new(
        model:,
        dataset: "coverage",
        name: "coverage experiment",
        means: {},
        results:,
        errors: [],
        duration: 0,
        permalink: nil,
        usage: Agent::Evals::Usage.zero
      )
    end

    def scored_run(model:, kase:, accuracy:)
      build_run(
        model:,
        kase:,
        score: Agent::Evals::Score.new(value: accuracy, metrics: { "accuracy" => accuracy }),
        reply: Agent::Evals::Reply.new(output: { "value" => accuracy })
      )
    end

    def render_report(summaries, weighted_score: nil)
      described_class.render(summaries, metrics:, weighted_score:)
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
                                     reply: Agent::Evals::Reply.new(error: "reply <script>alert(2)</script>"),
                                     score: Agent::Evals::Score.failed(metrics, "reply <script>alert(2)</script>")),
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

    it "uses the configured weighted score to select and label the leader" do
      weighted_score = Agent::Evals::WeightedScore.new({ "accuracy" => 1.0 }, metrics: ["accuracy"])
      report = render_report([
                               build_summary(model: echo_model, results: [scored_run(model: echo_model, kase: case_one, accuracy: 0.9)]),
                               build_summary(model: parrot_model, results: [scored_run(model: parrot_model, kase: case_one, accuracy: 0.2)])
                             ],
        weighted_score:)

      expect(report).to include(
        "Weighted score from the lineup",
        "ALL-CASE LEADER",
        '<span class="model-id">echo</span>',
        "90.0%"
      )
    end
  end
end
