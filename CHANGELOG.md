# Changelog

## 0.4.0 (2026-10-30)

Renamed from `agent-evals`. The version continues from `agent-evals` 0.3.1, and the old gem gets no further releases.

To upgrade a suite:

| Was                      | Now                                          |
| ------------------------ | -------------------------------------------- |
| `gem "agent-evals"`      | `gem "llm-evals"`                            |
| `require "agent/evals"`  | `require "llm/evals"`                        |
| `Agent::Evals`           | `LLM::Evals`                                 |
| `agent-evals`, `aeva`    | `llm-evals`, `evals` (identical executables) |
| `.agent-eval.config.yml` | `.llm-evals.config.yml`                      |
| `AGENT_EVALS_HELPER`     | `LLM_EVALS_HELPER`                           |
| `log/agent-evals/`       | `log/llm-evals/`                             |

The old names are not read as fallbacks, with one exception: JSON reports saved as `agent-evals-report` still render.

- Add `--format html` to `run` and `compare` for a standalone report with global and dataset rankings, coverage, sortable tables, case inputs, expected answers, scores and diagnostics. TUI remains the default; HTML writes to `log/` unless `-o` names a path. Provider and model names are color-coded, with effort and temperature in separate columns.
- Add `--totals overall|variant|both` to choose the TUI totals view; overall results are the default and per-variant tables remain available.
- Save every run as timestamped JSON by default and render browser and TUI output from the decoded JSON snapshot.
- Add input and output token totals to the HTML model summaries, including global and per-dataset aggregates.

## 0.1.0 (2026-10-14)

First release, extracted from the `extract-eval` suite of inquirex-llm and made generic.

- Two contracts a suite implements: `Adapter` (runs one case against a `Model`, returns a `Reply`, never scores) and `Scorer` (returns a `Score` with `Metric`s and per-field diagnostics, never calls anything).
- Value objects: `Case`, `Usage`, `Completion`, `Reply`, `Metric`, `Score`, `RunResult`, `Contender`.
- `Agent::Evals.configure` and `evals/eval_helper.rb`, found upward from the working directory (`--helper`, `AGENT_EVALS_HELPER`); or a config-only suite whose `.agent-eval.config.yml` names `require:`, `adapter:` and `scorer:`, the helper winning where both exist.
- `Discovery` of `datasets/<dataset>/cases/<variant>/[NNN/]input.txt` with `expected.json` beside; any layout through the glob.
- `Config`: the `.agent-eval.config.yml` lineup with effort and temperature lists expanded into contenders, and the required `request_types` list, and a `direct:` section for a vendor's own API (`typesafe`), keyed by provider name; a provider declares its `request_type` and a contender is admitted only when the suite declares it, else refused by name in the warnings.
- Providers: a registry asked last-registered first; `OpenRouter` through RubyLLM; `TypeSafe` as catalog, key and pricing with a transport stub; `Catalog` for model lists.
- `Experiment`: parallel runs on the gem's own thread pool, watched by trackers: `Trackers::Local` always writes `log/agent-evals/*.json`; one remote tracker, `braintrust` (eval rows through the gem's exporter) or `logfire` (OTLP traces through the OpenTelemetry SDK), is chosen by `--tracker`, `tracker:` or the one env key set. braintrust, ruby_llm and the OpenTelemetry gems are optional and named when missing.
- `Verify`: empty inputs and broken `expected.json`, then the adapter's and the scorer's own checks. `SchemaValidator` for typed, closed expected values.
- CLI: `cases`, `verify`, `run`, `compare`, `version`, `completion`; `-n/--dry-run` and `-o/--output`; leaderboard, glossary and best value derived from the scorer's metrics; warnings held off the screen and saved to `log/`.
- `Testing::EchoAdapter`, `Testing::FakeProvider` and `Testing::FakeModel`, and a toy suite under `spec/fixtures/toy_suite/`.
