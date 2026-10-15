# Changelog

## 0.1.0 (2026-10-14)

First release, extracted from the `extract-eval` suite of inquirex-llm and made generic.

- Two contracts a suite implements: `Adapter` (runs one case against a `Model`, returns a `Reply`, never scores) and `Scorer` (returns a `Score` with `Metric`s and per-field diagnostics, never calls anything).
- Value objects: `Case`, `Usage`, `Completion`, `Reply`, `Metric`, `Score`, `RunResult`, `Contender`.
- `Agent::Evals.configure` and `evals/eval_helper.rb`, found upward from the working directory (`--helper`, `AGENT_EVALS_HELPER`).
- `Discovery` of `datasets/<dataset>/cases/<variant>/[NNN/]input.txt` with `expected.json` beside; any layout through the glob.
- `Config`: the `.agent-eval.config.yml` lineup with effort and temperature lists expanded into contenders, and the required `request_types` list, and a `direct:` section for a vendor's own API (`typesafe`), keyed by provider name; a provider declares its `request_type` and a contender is admitted only when the suite declares it, else refused by name in the warnings.
- Providers: a registry asked last-registered first; `OpenRouter` through RubyLLM; `TypeSafe` as catalog, key and pricing with a transport stub; `Catalog` for model lists.
- `Experiment`: parallel local runs, or Braintrust experiments when a project is given; the braintrust and ruby_llm gems are optional and named when missing.
- `Verify`: empty inputs and broken `expected.json`, then the adapter's and the scorer's own checks. `SchemaValidator` for typed, closed expected values.
- CLI: `cases`, `verify`, `run`, `compare`, `version`, `completion`; `-n/--dry-run` and `-o/--output`; leaderboard, glossary and best value derived from the scorer's metrics; warnings held off the screen and saved to `log/`.
- `Testing::EchoAdapter`, `Testing::FakeProvider` and `Testing::FakeModel`, and a toy suite under `spec/fixtures/toy_suite/`.
