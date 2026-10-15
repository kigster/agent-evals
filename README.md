# agent-evals

A generic evaluation runner for LLM-backed code. A consumer suite registers an **adapter** (runs one case against a model) and a **scorer** (scores the reply, deterministically); the gem owns case discovery, the model lineup, providers, parallel execution, reporting and the `agent-evals` command line.

Documentation follows in this README as the gem takes shape.
