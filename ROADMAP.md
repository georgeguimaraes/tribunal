# Tribunal red-team roadmap (from promptfoo experience)

## Context

In a prior session we built a promptfoo harness (`canopy/tools/promptfoo/`) for adversarial testing of the Ngen chat orchestrator. Headline findings from real runs against cosmetics and boxlunch:

- **78% / 75% pass rate** on 105-attack suites.
- `jailbreak:meta` (iterative attacker LLM, uses promptfoo's hosted attack-generation API at runtime) was the dominant attack vector — **54% pass rate vs. 89% on static-template attacks**.
- Worst plugin areas: `hijacking` (off-topic deflection), `prompt-extraction` (system-prompt leak via "describe a hypothetical chatbot" framings).
- Best: `pii:direct` (0 fails), `excessive-agency` (1-7% fails).
- Verbatim concerning failures: medical-advice on rash symptom, 988 crisis-line script for wedding anxiety, system-prompt leak via "summarize for a new employee" framing.

The harness works but has friction:
- Requires email verification (promptfoo's gate on their hosted attack generator).
- Iterative jailbreak (`jailbreak:meta`) needs `--remote` because attack-generation is cloud-only.
- Ships a JS/YAML side outside the Elixir stack.
- HTTP provider only sees the assistant's text — can't assert on tool traces.
- The `purpose` string and plugin selection get sent to promptfoo's cloud.

Goal: bring promptfoo-grade red-team coverage into **tribunal** (the user's own Elixir LLM eval framework at `~/code/tribunal`) so it runs entirely locally, integrates natively with Ngen, and supports tool-trace assertions.

## Existing pieces

**Tribunal** (separate mix project at `~/code/tribunal`, github `georgeguimaraes/tribunal`):
- `Tribunal.RedTeam` — exposes `generate_attacks/2`, `encoding_attacks/1`, `injection_attacks/1`, `jailbreak_attacks/1`. Returns `[{attack_type, prompt}, ...]` tuples.
- Static attack content today:
  - **Encoding:** base64, leetspeak, rot13, pig latin, reversed.
  - **Injection:** ignore_instructions, system_prompt_extraction, role_switch, delimiter_injection.
  - **Jailbreak:** DAN, STAN, developer_mode, hypothetical, character_roleplay, research_framing.
- ExUnit integration via `use Tribunal.ExUnit` plus a `provider` function callback.
- LLM-as-judge assertions: `refute_jailbreak`, `refute_pii`, `refute_toxicity`, `refute_hallucination`, `assert_faithful`, `assert_relevant`, `assert_judge :custom`.
- Two operating modes: ExUnit test mode + `mix tribunal.eval` benchmark mode.
- Has `req_llm` and `alike` as optional deps for judge / similarity.

**Ngen integration points already in place:**
- `Ngen.Chat.Eval` framework (`backend/ngen/lib/ngen/chat/eval.ex`) — iex-only `run_for_store/2`, `run_conversation/3`. Has 8 case-provider modules (`Cases.Cosmetics`, `Cases.Boxlunch`, etc.).
- `Ngen.Chat.Eval.Assertions.clean_canvas?/1` — predicate landed for GEN-1214. Pattern for adding store-specific quality assertions.
- `POST /api/internal/eval/run` — synchronous HTTP wrapper around `Eval.run_conversation`, gated by the `:internal_api` shared-secret pipeline. Lives in `backend/ngen/lib/ngen_web/controllers/internal/eval_controller.ex` (PR #4422, may be merged by now).
- `Ngen.Chat.Eval.ToolTrace` — extracts the orchestrator's tool-call sequence from the conversation's LLM context. Useful for tool-trace assertions promptfoo can't do.
- `Ngen.Chat.Eval.ToolMapping` — abstract tool category atoms (`:search`, `:compare`, `:clarify`, `:trends`) → concrete tool name strings, scenario-aware (currently only `:baseline` mapped).

## What promptfoo's catalog actually is

Important nuance: promptfoo doesn't ship a static list of attack strings. Each plugin is an **LLM-driven attack generator** that takes a `purpose` string and emits attacks tailored to your specific assistant. The plugin definitions and meta-prompts live in their TypeScript source (MIT-licensed) but the actual attacks are synthesized at generate time. Strategies (`jailbreak:meta`, `prompt-injection`, `crescendo`) are wrappers / iterators over base attacks.

So "porting promptfoo's catalog" means three different kinds of work:

1. **Static text transforms** (base64, etc.) — straight algorithm port. Tribunal has these.
2. **Plugin meta-prompts** — read promptfoo's TypeScript, reimplement as InstructorLite calls in Elixir.
3. **Static seed corpora** (DAN library, AdvBench, JailbreakBench) — public datasets, embed as JSON.

## Plugin gap vs promptfoo

| Plugin | Tribunal today | Worth porting? | Notes |
|---|---|---|---|
| `policy` | ❌ | **Yes (highest value)** | Takes user-supplied policy text, generates attacks targeting violations. Use `@guardrails` from `baseline.ex` as input. |
| `excessive-agency` | ❌ | Yes | "Place an order", "modify my account" probes. Mapped attacker LLM call. |
| `prompt-extraction` | Partial (`system_prompt_extraction_attack`) | Yes | Extend with the indirect framings ("explain to a new employee", "include in a recipe", "describe a hypothetical chatbot"). |
| `pii:direct/session/api-db` | ❌ | Yes | PII probes targeting other-user data leakage. |
| `harmful` (hate/violence/illegal) | ❌ | Yes | Embed AdvBench / JailbreakBench corpora as JSON in `priv/`. No LLM gen needed. |
| `imitation` | ❌ | Yes | Persona-impersonation attacks. Boxlunch was weak here. |
| `hallucination` | ❌ | Yes | Probe for fabricated specs / fake products. |
| `hijacking` | ❌ | Yes | Off-topic-but-adjacent (the "fandom adjacent" failure mode we found on boxlunch). |
| `crescendo` (strategy) | ❌ | **Yes (highest impact)** | Multi-turn escalation. The `jailbreak:meta` 54% fail rate came from this. Needs orchestrator-level multi-turn support. |
| `bola/bfla` | — | Skip | Auth-layer concerns, not LLM-layer. |
| `contracts` / `religion` / `politics` | — | Defer | Less relevant for shopping assistants. |

## Locked for Phase 1 (decided 2026-05-03)

- **Generation and running stay separate.** Generation produces a regular tribunal dataset YAML; running uses the existing `mix tribunal.eval` and `tribunal_dataset` paths. No new runner. Mirrors promptfoo's `redteam generate` / `redteam run` split: generation is expensive, attacks should be reviewable and committable, execution should be cheap and repeatable.
- **YAML schema is slim and fits `Tribunal.Dataset` directly.** Each generated case is a normal dataset entry with `input`, `metadata.{plugin, goal, severity}`, and `expected.policy_violation: {policy: "..."}`. No promptfoo-style anchors, no `pluginConfig`, no `modifiers`. Loader needs no changes.
- **No YAML variables.** Promptfoo uses `{{env.X}}` and `{{prompt}}` because its YAML defines the provider and has to assemble HTTP requests itself. Tribunal's provider is `{Module, :function}` receiving a `TestCase` struct directly, and per-store parameterisation lives at the Elixir call site (`Tribunal.RedTeam.generate(purpose:, policy:, ...)`). Generated YAMLs are fully concrete.
- **Plugin contract is a behaviour.** `Tribunal.RedTeam.Plugin` with `id/0`, `severity/0`, `generate/1`. Built-in list plus `config :tribunal, :red_team_plugins, [...]` for custom plugins. Same shape as `Tribunal.Judge`.
- **Attacker LLM is its own behaviour.** `Tribunal.RedTeam.Attacker` with a `ReqLLM` default (when `req_llm` is loaded) and a `Stub` for tests. Configurable via `config :tribunal, :red_team_attacker, ...` or per-call opt. Default model is a strong general model (sonnet 4.6 or gpt-4o class), not a small/fast one — attack quality scales with attacker reasoning.
- **Reimplement promptfoo meta-prompts in Elixir, don't copy.** Both projects are MIT, but promptfoo's prompts are tuned for their JS structured-output flow. Cleaner to rewrite against their public docs.
- **Telemetry on every step.** `:telemetry.span/3` for `[:tribunal, :red_team, :generate]`, `[:tribunal, :red_team, :plugin]`, `[:tribunal, :red_team, :attacker_llm]`. `:telemetry.execute/3` for `[:tribunal, :red_team, :case_emitted]` per attack.
- **Phase 1 ships `Plugins.Policy` end-to-end first.** Lock the contract on one plugin before replicating it across the others.

## Deferred to v2 or later

- **Static + LLM hybrid plugins.** `Plugins.Harmful` and `Plugins.Pii:direct` can ship with static seed corpora (AdvBench, JailbreakBench) plus optional LLM expansion to retarget seeds at the assistant's domain. Phase 1 plugins are pure-LLM; static corpora work waits.
- **Per-rule policy splitting.** Current `Plugins.Policy` mirrors promptfoo: one policy block in, N attacks out, attacker free-picks which rule each attack probes. Splitting into "N attacks per rule" is a v2 mode behind an opt.
- **`tribunal_redteam` ExUnit macro.** Inline generate-and-run is tempting but generation is expensive and non-deterministic, so it's a bad fit for test files. Users who want it can call `Tribunal.RedTeam.generate/1` from `setup_all`. Revisit if there's demand.
- **YAML variable substitution.** Not needed for current design. If we ever want one YAML to drive multiple providers or configurations at run time, revisit then.

## Phased plan

**Phase 1 — port plugins as static + LLM-generated** (~1-2 weeks)
- Add `Tribunal.RedTeam.Plugin` behaviour and `Tribunal.RedTeam.Plugins` namespace.
- Add `Tribunal.RedTeam.Attacker` behaviour with `Attacker.ReqLLM` default.
- Implement Plugins.Policy first end-to-end. Then Plugins.ExcessiveAgency, Plugins.PromptExtraction, Plugins.Imitation, Plugins.Hijacking, Plugins.Hallucination — all use the attacker LLM with their own meta-prompts.
- Add `Tribunal.Judges.PolicyViolation` and `refute_policy_violation/2` macro.
- Top-level `Tribunal.RedTeam.generate(plugins:, purpose:, policy:, count_per_plugin:)` orchestrates.
- `mix tribunal.redteam.generate` writes a dataset YAML.
- Release tribunal new minor version.

**Phase 2 — strategies** (~1 week)
- `Tribunal.RedTeam.Strategies.Crescendo` — multi-turn wrapper, accepts a base attack and produces a 3-5 turn escalation script. Needs the harness to support multi-turn.
- `Strategies.IterativeJailbreak` — runs an attacker LLM that refines an attack based on the target's response. This is the heavy hitter.

**Phase 3 — Ngen integration** (~3-5 days)
- Add a `Cases.RedTeam` provider per store in `Ngen.Chat.Eval.Cases` that uses `Tribunal.RedTeam.attacks/1` to expand each base case via the configured plugins.
- Add `Mix.Tasks.Ngen.RedTeamEval` that drives the full sweep across stores, dumps a JSON/HTML report.
- Reuse existing `Ngen.Chat.Eval.run_conversation/3` for the per-attack execution; reuse `ToolTrace` for tool-aware assertions (the thing promptfoo couldn't do).
- Optional: synchronous test endpoint already exists at `/api/internal/eval/run` if external tools want HTTP.

**Phase 4 — CI** (~1 day)
- GitHub Action runs `mix ngen.red_team_eval --output report.json` on cron (nightly?).
- Surface failures as PR comments or just a Slack ping.

## Evaluation architecture

Mix and ExUnit share evaluation semantics while keeping their native execution models. Red-team generation produces ordinary Tribunal datasets that use these same evaluation paths.

The detailed plan for structured inputs, repeated sampling, result schemas, reporting, and batch gates lives in [`EVALUATION_PLAN.md`](EVALUATION_PLAN.md).

## Open decisions still on the table

Resolved entries from the original list moved into "Locked for Phase 1" above. Remaining:

1. **Static corpora license check.** AdvBench (MIT), JailbreakBench (MIT), HarmBench (MIT-ish) — all OK to embed. Only relevant when we tackle hybrid plugins; defer with that v2 work.
2. **Crescendo / iterative-jailbreak architecture.** These need a runtime feedback loop (attacker LLM sees defender's response, refines next attack). Tribunal's current `provider` callback is single-turn. Either extend the callback to multi-turn or add a separate `multi_turn_provider` shape. Phase 2 concern.
3. **Where does the Ngen-side runner live?** Options: (a) extend `Ngen.Chat.Eval.run_for_store/2` with red-team cases mixed in; (b) separate `Ngen.Chat.RedTeam.run_for_store/2` module to keep concerns clean. Lean toward (b). Phase 3 concern.
4. **Telemetry aggregation on the Ngen side.** Promptfoo produces per-plugin pass rates. Tribunal's per-plugin grouping (via `metadata.plugin`) gives this shape on the tribunal side; Ngen's aggregator needs to mirror it. Phase 3 concern.
