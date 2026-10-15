# agent-evals

A generic evaluation runner for LLM-backed code, for the engineer who has a folder of cases and wants to know which model, prompt or setting answers them best, without writing the runner, the lineup, the progress bars or the leaderboard again.

The gem has a one-way boundary. A consumer suite registers two objects:

- an **adapter**, which runs one case against a model and returns a `Reply`. It owns everything the model sees and everything done to its answer. It never scores.
- a **scorer**, which turns a case and a reply into a `Score`. It is pure and deterministic. It never calls anything.

Everything else is the gem's: case discovery, the model lineup (`.agent-eval.config.yml`), providers (OpenRouter through RubyLLM; TypeSafe's catalog), parallel execution, trackers (a local JSON log always; Braintrust or Logfire beside it), the per-case breakdown, the leaderboard, warnings held back from the screen, and the `agent-evals` command line. Nothing in `lib/` knows what is being evaluated.

## Install

```ruby
# Gemfile
gem "agent-evals"
gem "ruby_llm"    # only if a provider needs it (OpenRouter does)
gem "braintrust"  # only for the braintrust tracker
gem "opentelemetry-sdk"            # only for the logfire tracker
gem "opentelemetry-exporter-otlp"
```

Ruby 3.4 or later.

## A suite

The executable looks for `evals/eval_helper.rb` upward from the current directory (or `--helper PATH`, or `AGENT_EVALS_HELPER`), loads it, and dispatches. The helper calls `Agent::Evals.configure`:

```ruby
# evals/eval_helper.rb
require "bundler/setup"
require "agent/evals"
require "my_gem"

class MyAdapter < Agent::Evals::Adapter
  def prepare(dataset) = @schema = MyGem.schema_for(dataset)   # once per dataset, outside the threads

  def call(kase, model:)
    completion = model.complete(system: MyGem.system_prompt(@schema), user: kase.input, json: true)
    output = MyGem.parse(completion.text)                     # the production parser, so scores reflect production
    Agent::Evals::Reply.new(output: output, raw: completion.text, usage: completion.usage)
  rescue MyGem::NotJSON => e
    Agent::Evals::Reply.new(error: e.message, raw: completion&.text)   # the model's failure: scored 0
  end

  def context(kase) = { schema: @schema }                     # what the scorer needs beyond the case
  def verify(dataset) = MyGem.schema_problems(dataset)        # offline, for `agent-evals verify`
end

class MyScorer < Agent::Evals::Scorer
  def metrics
    [Agent::Evals::Metric.new(name: "field_accuracy", description: "Mean per-field score.", primary: true),
     Agent::Evals::Metric.new(name: "exact_match", description: "1 when every field is right."),
     Agent::Evals::Metric.new(name: "restraint", description: "Of the fields the text never answers, the share left null.")]
  end

  def call(kase, reply, context:)
    scores = MyGem.field_scores(context[:schema], kase.expected, reply.output)
    Agent::Evals::Score.new(
      value:       scores.values.sum / scores.size,
      metrics:     { "field_accuracy" => scores.values.sum / scores.size,
                     "exact_match"    => scores.values.all?(1.0) ? 1.0 : 0.0,
                     "restraint"      => nil },                      # nil: this case does not apply; it is skipped, not zeroed
      diagnostics: scores.reject { |_, v| v == 1.0 }.to_h { |f, _| [f, { want: kase.expected[f], got: reply.output[f] }] }
    )
  end

  def verify(kase, context:) = Agent::Evals::SchemaValidator.new(context[:schema]).problems(kase.expected)
  def summary(kase) = "#{kase.expected.count { |_, v| !v.nil? }}/#{kase.expected.size} answered"
end

Agent::Evals.configure do |c|
  c.suite "extract", root: __dir__, env_files: ["../.env"]
  c.cases "datasets/*/cases/**/input.txt"
  c.adapter MyAdapter.new
  c.scorer MyScorer.new
  c.before_run { MyGem.reset_configuration! }   # after the env files load, before any model is called
end
```

A complete, runnable suite lives in [`spec/fixtures/toy_suite/evals/`](spec/fixtures/toy_suite/evals/): two datasets, two variants, the gem's own `Testing::EchoAdapter` and a fake provider, so it runs without a network.

### A config-only suite

A suite needs no `eval_helper.rb` when its Ruby lives in its own gem. Three optional keys in `.agent-eval.config.yml` name it:

```yaml
# evals/.agent-eval.config.yml
require: my_gem/evals              # a require path, or a list; loaded through the bundle's load path
adapter: MyGem::Evals::Adapter     # constant names, instantiated with no arguments
scorer: MyGem::Evals::Scorer
```

The executable then finds `evals/.agent-eval.config.yml` upward from the working directory, roots the suite at `evals/`, requires what `require:` names and instantiates the two constants. `evals/` holds only the file and `datasets/`:

```text
lib/my_gem/evals/adapter.rb         # the Ruby, in the gem
lib/my_gem/evals/scorer.rb
evals/.agent-eval.config.yml        # the lineup, plus require/adapter/scorer
evals/datasets/...
```

When `evals/eval_helper.rb` exists it is loaded first and may register either object in code; the config keys fill whatever the helper left unset. Neither supplying an adapter and a scorer is a configuration error naming the file and the keys; a `require:` that fails or a constant that does not exist is an error naming the key and the value, not a bare `LoadError` or `NameError`. The required file may itself call `Agent::Evals.configure`, for instance to register a provider. [`spec/fixtures/config_only_suite/`](spec/fixtures/config_only_suite/) is the toy suite in this form.

### Cases on disk

```text
evals/
  eval_helper.rb
  .agent-eval.config.yml           # the lineup and the request types
  datasets/<dataset>/cases/<variant>/[NNN/]input.txt
  datasets/<dataset>/cases/<variant>/[NNN/]expected.json
  datasets/<dataset>/cases/<variant>/[NNN/]metadata.json   # optional; merged into Case#metadata
```

The folder after `datasets/` is the dataset; the folder holding `input.txt` is the variant, unless it is a number, in which case it is the case number and its parent is the variant. A case's id is `variant/NNN`; `-c clear` keeps a variant, `-c clear/003` one case. Another layout is a matter of the glob passed to `c.cases`.

### The lineup: `.agent-eval.config.yml`

The file at the suite root names the models to compare, their settings, and the kinds of request the suite can produce:

```yaml
# evals/.agent-eval.config.yml
project: my-evals            # Braintrust project name (BRAINTRUST_PROJECT_ID wins when set)
request_types: [prompt]      # required: what the suite's adapter sends

defaults:
  effort: default            # default sends none and leaves the model's own setting
  temperature: 0.1
  max_tokens: 8192           # covers the reasoning tokens a high effort spends
  parallelism: 4             # cases in flight per experiment; the default for -p

vendors:                     # the OpenRouter list; every entry takes a prompt
  anthropic:
    - model: claude-fable-5
    - model: claude-opus-5
    - model: claude-sonnet-5.5
    - model: claude-haiku-5.5
      effort: [default, low, high]   # a list expands into one contender per value
  openai:
    - model: gpt-4.1-mini
    - model: gpt-4o-mini
    - model: gpt-6.1-sol
  google:
    - model: gemini-2.5-flash
    - model: gemini-4-argon
  meta-llama:
    - model: llama-3.3-70b-instruct
  typesafe:
    - model: jev-router      # Jev on OpenRouter, a chat model
  moonshotai:
    - model: kimi-k3

direct:                      # a vendor's own API, one request type each
  typesafe:                  # request type "typesafe": noul, choice, score
    - model: jev-latest
```

Each entry under a vendor becomes `<vendor>/<model>`, the OpenRouter id. `effort` and `temperature` take one value or a list; a list expands into one contender per value, so `effort: [low, high]` with `temperature: [0.0, 0.7]` runs four experiments for that model. Anything left out falls back to `defaults`. Flags (`-e`, `-t`, `--max-tokens`, `-p`) beat both.

Each key under `direct:` names a provider the gem knows (today only `typesafe`); its entries take the same `{model:, effort:, temperature:, max_tokens:}` format and expand the same way, and render as `typesafe/jev-latest`. The contender carries its provider, so a direct `typesafe/jev-latest` and the OpenRouter chat model `typesafe/jev-router` can never be confused, whatever the ids look like. An unknown key under `direct:` is a configuration error naming the file and the known providers.

#### Request types

`request_types` is required. It says what the suite's adapter sends. The types, and what they mean, belong to the providers and show in `agent-evals --help`; a suite only names them:

| Type       | Provider                                 | Meaning                                              |
| ---------- | ---------------------------------------- | ---------------------------------------------------- |
| `prompt`   | OpenRouter (everything under `vendors:`) | a chat completion: system and user text in, text out |
| `typesafe` | `direct: typesafe:`                      | typed questions: noul, choice, score                 |

A contender is **admitted** only when its provider's type is in the suite's list. A refused contender is named in the run's warnings (`typesafe/jev-latest refused: needs typesafe; this suite produces prompt`), left out of the matrix and the leaderboard, and never scored 0: a model the suite cannot ask did not answer wrongly. `cases` prints the refusals too, so the mismatch shows before anything runs. A missing, empty or unknown `request_types` is a configuration error naming the file. A `[prompt]` suite that lists `direct: typesafe:` entries runs its `vendors:` and refuses those by name.

## The command line

```bash
agent-evals cases                              # list the cases, no calls
agent-evals verify                             # offline checks: inputs, expected.json, adapter, scorer
agent-evals run -m openai/gpt-4.1-mini         # one model, every dataset, per-case breakdown
agent-evals run -m anthropic/claude-haiku-5.5 -e low -d vague -c vague/00
agent-evals run --local -o                     # no remote tracker; the breakdowns go to log/
agent-evals compare                            # everything the lineup lists, leaderboard only
agent-evals compare -n                         # show that matrix, call nothing
agent-evals completion zsh                     # shell completion (bash too)
```

| Command      | Does                                                                                                     | Calls models |
| ------------ | -------------------------------------------------------------------------------------------------------- | ------------ |
| `cases`      | One row per case: dataset, id, difficulty, the scorer's `summary`, word count; refused lineup entries.   | no           |
| `verify`     | Empty inputs, missing or unparsable `expected.json`, then `adapter.verify(dataset)` and `scorer.verify`. | no           |
| `run`        | One experiment per model and dataset, each with its breakdown, then the leaderboard.                     | yes          |
| `compare`    | The same experiments, only the leaderboard. `--concurrency N` limits models running at once.             | yes          |
| `version`    | The gem version (`-V`, `--version`).                                                                     | no           |
| `completion` | A bash or zsh completion script.                                                                         | no           |

Flags shared by `run` and `compare`: `-m/--models`, `-d/--dataset` (every dataset when omitted), `-c/--case`, `-e/--effort`, `-t/--temperature`, `--max-tokens`, `-p/--parallelism`, `--config FILE`, `--project NAME`, `--tracker NAME`, `--local`, `--no-open`, `-n/--dry-run`, `-o/--output [FILE]`.

Reserved short flags, the same in every CLI of this family: `-n` dry run, `-y` yes, `-o` report file, `-l` log file, `-L` log level. `-n` and `-o` are implemented; `-l` and `-L` are reserved and not taken by anything else.

The leaderboard has one column per metric the scorer declares, ranked by the `primary` one, with a glossary built from each metric's `description`. The best value per dataset is the cheapest experiment within two points of the best primary metric. STDOUT carries the tables; progress bars and warnings go to STDERR, and anything a library would have printed while the bars redraw is saved to `log/<command>.warnings.<stamp>.log` instead.

## Trackers

The gem always owns the run loop. Where results go besides the terminal is a **tracker**: the local JSON log always runs, and at most **one remote tracker** runs beside it, or none.

| Tracker      | Chosen by                                       | Needs                                                                                         | Sends                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ------------ | ----------------------------------------------- | --------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| local        | always                                          | nothing                                                                                       | `log/agent-evals/<experiment>.<stamp>.json`: settings, means, errors, usage, and one row per case (score, metrics, outcomes, diagnostics, error, usage).                                                                                                                                                                                                                                                                                                                                                   |
| `braintrust` | `--tracker braintrust`, or `BRAINTRUST_API_KEY` | the `braintrust` gem; `BRAINTRUST_API_KEY`; optionally `BRAINTRUST_PROJECT_ID` or `--project` | One experiment per run in the project; one eval row per case with input, expected, output (or `_error`), the scorer's metrics as scores, and diagnostics, outcomes and usage as metadata. `finish` returns the experiment page, which opens unless `--no-open`.                                                                                                                                                                                                                                            |
| `logfire`    | `--tracker logfire`, or `LOGFIRE_TOKEN`         | `opentelemetry-sdk` and `opentelemetry-exporter-otlp`; `LOGFIRE_TOKEN`                        | OTLP traces to `https://logfire-us.pydantic.dev/v1/traces` (per their docs, 2026-10-15; `LOGFIRE_BASE_URL` for another region): one span per experiment (suite, project, model, provider, settings, case count, means on finish) with one child span per case (id, dataset, variant, score, each metric, outcome counts, duration, tokens and cost, diagnostics as JSON cut at 4 KB, exceptions recorded). The raw reply is not sent unless `logfire: { include_replies: true }` is in the config. No URL. |

Selection, in this order: `--tracker NAME` on the command line, then `tracker:` in `.agent-eval.config.yml`, then the environment, where exactly one tracker's key being set selects it. Two keys set and nothing chosen is an error asking for `--tracker` or `tracker:`; `--local` (or `--tracker none`) means no remote tracker. A chosen tracker whose gem or key is missing fails before any model is called, naming both. `-v` prints which tracker was chosen and why.

Logfire has no Ruby gem of its own: it is an OTLP backend for the standard OpenTelemetry Ruby SDK, so the tracker builds its own tracer provider and exporter and leaves the global one alone. When `OTEL_EXPORTER_OTLP_ENDPOINT` or `OTEL_EXPORTER_OTLP_HEADERS` is already set, those win over `LOGFIRE_TOKEN`, and `-v` says so. Traces only; Logfire's metrics and logs SDKs are pre-1.0.

### Writing a tracker

A tracker is a class with three callbacks. Register it with `c.tracker` in the helper (or name it in a plugin gem's `require:`), and choose it by name:

```ruby
class Weave < Agent::Evals::Tracker
  def self.env_key = "WANDB_API_KEY"                 # selects it when set and nothing else is chosen
  def self.gems = ["wandb"]                          # lazily required; named in the error when missing

  def start(experiment)                              # once, before the first case
    @run = Wandb.init(project: context[:project], name: experiment.name,
      config: { model: experiment.model.id, **experiment.model.settings })
  end

  def record(result)                                 # once per finished case, in order, under a lock
    @run.log("case" => result.case.key, "score" => result.score&.value, **(result.score&.metrics || {}),
      "error" => result.error, "cost_usd" => result.reply&.usage&.cost_usd)
  end

  def finish(experiment, summary)                    # once, with the summary
    @run.summary.update(summary.means)
    @run.finish
    { url: @run.url }                                # or { url: nil } when there is no page to open
  end
end

Agent::Evals.configure { |c| c.tracker Weave }
```

`context` holds `suite:`, `project:`, `project_id:` and `options:` (the tracker's own section of the config file, e.g. `weave: { entity: "team" }`). Return `false` from `enabled?` to turn every callback into a no-op. A tracker for another OTLP backend is a subclass of `Trackers::Logfire` with different credentials.

## Environment

| Variable                                                    | Needed when                                                                                                           |
| ----------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `OPENROUTER_API_KEY`                                        | any contender is served by OpenRouter (the default provider)                                                          |
| `TYPESAFE_API_KEY`                                          | a `direct: typesafe:` contender runs                                                                                  |
| `BRAINTRUST_API_KEY`                                        | optional; selects the braintrust tracker when nothing else is chosen, and is required by it                           |
| `BRAINTRUST_PROJECT_ID`                                     | optional; the Braintrust project UUID, beating the lineup's `project`                                                 |
| `LOGFIRE_TOKEN`                                             | optional; selects the logfire tracker when nothing else is chosen, and is required by it (a write token)              |
| `LOGFIRE_BASE_URL`                                          | optional; Logfire's region, default `https://logfire-us.pydantic.dev`                                                 |
| `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_HEADERS` | optional; when set, the logfire tracker uses them instead of `LOGFIRE_TOKEN`                                          |
| `AGENT_EVALS_HELPER`                                        | optional; the helper to load instead of searching upward for `evals/eval_helper.rb` or `evals/.agent-eval.config.yml` |

The suite's `env_files` load first, without overriding what is already exported. A missing key fails the run before any model is called, naming the variable.

## Writing a provider

A provider is one API: the request type it answers, the keys it needs, the models it lists, and `complete`. A provider that serves `vendors:` ids also says which (`prefix`); a `direct?` provider is reached only through a `direct:` key with its `name`. Register it with `c.provider`; the last registered is asked first for a `vendors:` id, and OpenRouter, which claims every id, is always last.

```ruby
class Ollama < Agent::Evals::Providers::Base
  def name = "ollama"
  def request_type = :prompt                          # admitted by a suite declaring prompt
  def request_type_description = "a chat completion"  # shown in --help; a suite never spells it
  def prefix = "ollama/"                              # serves "ollama/<model>"
  def env_keys = []                                   # local, no key
  def efforts = []                                    # takes no reasoning effort
  def catalog = JSON.parse(Net::HTTP.get(URI("http://localhost:11434/api/tags"))).fetch("models").map { "ollama/#{it["name"]}" }

  def complete(model, system:, user:, json: true)
    body = { model: model.name, system: system, prompt: user, format: (json ? "json" : nil), stream: false }.compact
    response = JSON.parse(Net::HTTP.post(URI("http://localhost:11434/api/generate"), JSON.generate(body)).body)
    Agent::Evals::Completion.new(
      text:  response.fetch("response"),
      usage: { input_tokens: response["prompt_eval_count"], output_tokens: response["eval_count"], cost_usd: 0.0 },
      raw:   response
    )
  end
end

Agent::Evals.configure { |c| c.provider Ollama.new }
```

`model.effort`, `model.temperature` and `model.max_tokens` carry the contender's settings; nil means "send nothing". A transport failure should raise: the run counts it as an error, not as a wrong answer.

`Providers::TypeSafe` is a direct provider (`direct: typesafe:`, request type `typesafe`): it ships with the model list, the key and the pricing of TypeSafe's API, enough for `verify` and the cost column. Its `complete` raises "no typesafe consumer yet": the typed request shape will be defined by the first suite that declares `request_types: [typesafe]`.

## Public API

```ruby
module Agent::Evals
  Case       = Data.define(:id, :dataset, :variant, :input, :expected, :path, :metadata)
  Usage      = Data.define(:input_tokens, :output_tokens, :cost_usd)
  Completion = Data.define(:text, :usage, :raw)
  Reply      = Data.define(:output, :raw, :usage, :error, :metadata)   # error = the model failed, scored 0; raise = transport
  Metric     = Data.define(:name, :description, :aggregate, :primary)  # aggregate :mean, skipping nil
  Score      = Data.define(:value, :metrics, :outcomes, :diagnostics)  # value 0..1; metrics { name => Float | nil }
  RunResult  = Data.define(:experiment, :case, :reply, :score, :duration, :error)
  Contender  = Data.define(:model, :effort, :temperature, :max_tokens, :provider)  # provider nil for vendors:, a name for direct:

  class Model;   attr_reader :id, :provider, :settings; def complete(system: nil, user:, json: true) = Completion; end
  class Adapter; def prepare(dataset); def call(kase, model:); def context(kase); def verify(dataset); def metadata; end
  class Scorer;  def metrics; def call(kase, reply, context:); def verify(kase, context:); def summary(kase); end
  class SchemaValidator  # { name => { type:, enum:, nullable: } }; boolean integer number string enum multi_enum
  class Experiment       # one model over one dataset, on the gem's own thread pool; trackers watch
  class Tracker          # start(experiment), record(run_result), finish(experiment, summary) -> { url: }
  module Trackers        # Local (always), Braintrust, Logfire (OTLP), Registry (choose)
  class Discovery, Config, Configuration, Runtime, Verify, Warnings, Launcher
  Config#request_types   # required in .agent-eval.config.yml; Config::REQUEST_TYPES = %w[prompt typesafe]
  module Providers       # Base (request_type, direct?), Registry (for, direct, admit), OpenRouter, TypeSafe, Catalog
  module Testing         # EchoAdapter, FakeProvider, FakeModel
end
```

## Development

```bash
just install     # bundle
just ci          # rubocop, rspec (coverage >= 95%), the toy suite through the executable; no network
just toy         # agent-evals cases && agent-evals verify, in spec/fixtures/toy_suite
lefthook install # the pre-commit hooks
```

Specs build real directories under `Dir.mktmpdir` and never reach the network; `RubyLLM`, the Braintrust API classes and `Net::HTTP` are stubbed, and the trackers are asserted through OpenTelemetry's in-memory span exporter.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
