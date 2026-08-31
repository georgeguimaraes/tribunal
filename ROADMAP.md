# Tribunal roadmap

## Current evaluation foundation

Tribunal 2.0 has a shared evaluation core across ExUnit and `mix tribunal.eval`:

- JSON-compatible structured inputs with an optional textual `evaluation_input`
- user-owned `tribunal_assert` callbacks
- one native ExUnit test per `tribunal_dataset` case
- repeated sampling with `all`, `any`, `majority`, and rate rules
- version 1 batch policy files through `mix tribunal.eval --config`
- host-owned overall and metadata group gates
- schema v3 reports with ordered attempt evidence
- operational errors kept separate from quality failures

The implemented contracts and examples live in [`EVALUATION_PLAN.md`](EVALUATION_PLAN.md).

## Current red-team foundation

Red-team generation and evaluation stay separate. Generation writes ordinary Tribunal dataset YAML, then the existing `tribunal_dataset` or `mix tribunal.eval` path runs it. Generated attacks remain reviewable and committable, and Tribunal does not need a separate red-team runner.

Implemented pieces include:

- deterministic encoding, injection, and jailbreak templates
- the `Tribunal.RedTeam.Plugin` behavior and custom plugin configuration
- the `Tribunal.RedTeam.Attacker` behavior with ReqLLM and stub implementations
- LLM-driven policy, excessive-agency, prompt-extraction, imitation, hijacking, and hallucination plugins
- policy-violation and related judges
- `Tribunal.RedTeam.generate/1`
- `mix tribunal.redteam.generate` YAML output
- telemetry around generation, plugins, attacker calls, and emitted cases

Generated rows use the normal dataset shape with `input`, assertion configuration, and metadata such as plugin, goal, and severity. Metadata provenance can feed Mix group gates without a red-team-specific aggregation path:

```bash
mix tribunal.eval test/evals/redteam.yaml \
  --group-by plugin \
  --group-threshold 0.8
```

Mix is the discovery and batch-gating interface. ExUnit enforces reviewed cases promoted into committed regression datasets.

## Red-team implementation plan

### Current milestone

- [x] reject invalid generation inputs and incomplete or duplicate attacker output
- [x] preserve generated prompts and policies exactly through YAML
- [x] include stable attack ids, strategy, and basic attacker provenance in generated rows
- [x] document candidate generation, Mix exploration, and manual ExUnit promotion
- [x] verify the complete generate, serialize, and reload path

## Next red-team work

### Static and hybrid corpora

Start with small ordinary YAML corpora. Preserve source and license metadata when importing third-party cases. Add no importer until a real corpus requires one. Optional LLM retargeting should still produce concrete reviewable dataset rows.

### Multi-turn strategies

Crescendo and iterative jailbreaks need a target response feedback loop. The current callback contract represents one invocation, so a multi-turn design must define conversation state, attacker visibility, target invocation, attempt evidence, and timeout behavior before implementation.

Prototype one strategy in tribunal-juror with plain functions, an explicit transcript, a turn limit, and a timeout. Extract a Tribunal API only after that host implementation proves a reusable contract. One complete conversation is one sampling attempt.

### Host application integration

Host applications can already provide their own Tribunal providers and group on red-team metadata. Application-specific orchestration, tool-trace assertions, multi-store sweeps, and notifications belong in the host unless a second general consumer establishes a reusable Tribunal API.

## Deferred evaluation controls

These are not implemented today:

- classified infrastructure retries
- provider-output or assertion-result caching
- resume from partial batch results
- usage and cost budgets
- confidence-interval gates
- per-value custom group thresholds
- required-group declarations
- a public batch runner

Sampling remains separate from retries. Sampling deliberately invokes the application more than once to measure nondeterminism. A future retry feature would recover only classified transient operational failures and would need separate accounting.

A public batch runner should only be extracted when there is a real programmatic consumer beyond the Mix task. The private Mix orchestration can continue to evolve without freezing a hypothetical public API.

## Design constraints

- Keep ExUnit native. ExUnit owns tests, scheduling, tags, setup, and timeouts.
- Keep batch gates host-owned. Dataset rows own assertion metric configuration, not suite policy.
- Keep every operational error visible through sampling and reporting.
- Keep generated red-team datasets concrete. Provider and host configuration stay in Elixir or the batch policy.
- Keep attempt order stable and preserve complete evidence in reports.
- Avoid a second test runner or hidden long-running process.
