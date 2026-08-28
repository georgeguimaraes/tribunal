# Test mode and evaluation mode

Tribunal shares assertion, execution, and sampling semantics across two interfaces. Pick the interface based on who should own execution and policy.

| | ExUnit test mode | Mix evaluation mode |
|---|---|---|
| Best for | Hard requirements and focused regression tests | Benchmarks and aggregate quality tracking |
| Execution owner | ExUnit | `mix tribunal.eval` |
| Provider input | Dataset provider receives `test_case.input` | Provider receives the full `Tribunal.TestCase` |
| Sampling | Per user-owned or generated test | Per selected batch case |
| Aggregate gates | None | Overall and metadata-group pass rates |
| Output | Native ExUnit failures and errors | Console, text, JSON, HTML, GitHub, or JUnit |

## ExUnit test mode

Use ordinary assertion macros when output has already been computed:

```elixir
test "answer follows policy" do
  answer = MyApp.Chat.reply("Can I return an opened laptop?")

  assert_faithful answer, context: @returns_policy
  refute_policy_violation answer, policy: @policy
end
```

Use `tribunal_assert` when Tribunal should rerun a user-owned callback and reduce repeated attempts:

```elixir
test "answer is stable" do
  tribunal_assert fn -> MyApp.Chat.reply(question) end,
    input: question,
    context: @context,
    expected: [faithful: [threshold: 0.85]],
    repeat: 5,
    pass_rule: {:rate, 0.8}
end
```

Use `tribunal_dataset` to generate one native ExUnit test per dataset case:

```elixir
tribunal_dataset "test/evals/safety.yaml",
  provider: {MyApp.Chat, :reply},
  repeat: 3,
  pass_rule: :all,
  timeout: 120_000
```

Quality failures are ExUnit assertion failures. Provider failures, invalid returns, missing output, assertion errors, exceptions, throws, and catchable exits are operational errors. ExUnit reports them through `Tribunal.ExUnit.OperationalError`. `exit(:kill)` remains native and terminates the ExUnit test process because there is no hidden task isolation.

ExUnit deliberately has no cross-test percentage gate. Its scheduler may run tests independently, filter them, or stop them through native timeout behavior.

## Mix evaluation mode

Use the Mix task to evaluate a selected dataset as one batch:

```bash
mix tribunal.eval test/evals/benchmark.yaml \
  --provider MyApp.BatchProvider.reply \
  --repeat 5 \
  --pass-rule majority \
  --threshold 0.9 \
  --concurrency 10
```

The provider receives the full test case:

```elixir
def reply(%Tribunal.TestCase{input: input, context: context}) do
  MyApp.Chat.reply(input, context: context)
end
```

It may return a binary, `{:ok, binary}`, `{:error, reason}`, a populated `Tribunal.TestCase`, or `{:ok, test_case}`.

Without `--threshold`, `--strict`, or a group gate, quality failures are report-only. The run completes with `gate_status: :not_configured`. Operational errors and zero-case runs still exit nonzero.

Use an overall host-owned gate when the batch pass rate matters:

```bash
mix tribunal.eval --threshold 0.9
mix tribunal.eval --strict
```

`--strict` is the zero-tolerance gate and cannot be combined with `--threshold`.

Use a group gate to prevent one metadata category from hiding behind the aggregate:

```bash
mix tribunal.eval \
  --group-by category \
  --group-threshold 0.8
```

Every selected case must have a scalar value for `metadata.category`, and every observed category must meet the threshold. Tribunal captures that value before providers run, so a provider-returned test case cannot change its gate group. Overall and group gates can be combined.

## Policy files

Store repeat and gate policy outside datasets with `--config`:

```yaml
version: 1
datasets:
  - test/evals/benchmark.yaml
sampling:
  repeat: 5
  pass_rule: majority
gates:
  overall:
    threshold: 0.9
  groups:
    by: category
    threshold: 0.8
```

```bash
mix tribunal.eval --config config/evaluation_policy.yaml
```

Explicit CLI values override policy values, and policy values override defaults. Positional datasets replace the policy dataset list. Paths are resolved from the current working directory.

## Operational errors and sampling

Sampling rules combine quality outcomes, not infrastructure health:

- `all` requires every attempt to pass
- `any` requires one attempt to pass
- `majority` requires strictly more than half
- `rate:0.8` requires an 80% attempt pass rate

Any operational attempt fails the reduced case. In Mix, any operational case makes the batch gate status `error` and exits nonzero. In ExUnit, it raises an operational test error. This keeps a permissive sampling rule from masking a provider timeout or judge failure.

## A common split

Run critical safety cases as ExUnit tests on every pull request. Run a broader batch with host-owned thresholds on a schedule or before release:

```bash
mix test --only eval
mix tribunal.eval --config config/evaluation_policy.yaml --format json --output results.json
```
