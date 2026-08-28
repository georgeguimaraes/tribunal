defmodule Mix.Tasks.TribunalEvalIntegrationTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Tribunal.Eval

  @moduletag :tmp_dir

  test "reports a missing output as a failed case", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "missing_output.json")

    File.write!(
      path,
      ~s([{"input":"hello","expected":{"contains":["hello"]}}])
    )

    Mix.Task.reenable("tribunal.eval")
    Mix.Task.reenable("app.start")

    output =
      capture_io(fn ->
        assert_raise Mix.Error, "Evaluation failed", fn ->
          Eval.run([path, "--format", "text"])
        end
      end)

    assert output =~ "Failed:    1"
    assert output =~ "contains"
    assert output =~ "evaluation: Missing actual output"
    assert output =~ "FAILED"
  end

  test "reports a provider exception as a failed case", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "provider_error.json")

    File.write!(
      path,
      ~s([{"input":"hello","expected":{"contains":["hello"]}}])
    )

    Mix.Task.reenable("tribunal.eval")
    Mix.Task.reenable("app.start")

    output =
      capture_io(fn ->
        assert_raise Mix.Error, "Evaluation failed", fn ->
          Eval.run([
            path,
            "--format",
            "text",
            "--provider",
            "Mix.Tasks.TribunalEvalIntegrationTest.failing_provider"
          ])
        end
      end)

    assert output =~ "Failed:    1"
    assert output =~ "provider: provider exploded"
  end

  test "leaves threshold result unset for an ungated operational error", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "missing_output.json")
    report_path = Path.join(tmp_dir, "report.json")

    File.write!(path, ~s([{"input":"hello","expected":{"contains":["hello"]}}]))

    Mix.Task.reenable("tribunal.eval")
    Mix.Task.reenable("app.start")

    capture_io(fn ->
      assert_raise Mix.Error, "Evaluation failed", fn ->
        Eval.run([path, "--format", "json", "--output", report_path])
      end
    end)

    report = report_path |> File.read!() |> JSON.decode!()

    assert report["summary"]["gate_status"] == "error"
    assert report["summary"]["threshold_passed"] == nil
  end

  test "keeps ordinary quality failures report-only without a gate", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "quality_failure.json")

    File.write!(
      path,
      ~s([{"input":"hello","expected":{"contains":["hello"]}}])
    )

    Mix.Task.reenable("tribunal.eval")
    Mix.Task.reenable("app.start")

    output =
      capture_io(fn ->
        Eval.run([
          path,
          "--format",
          "text",
          "--provider",
          "Mix.Tasks.TribunalEvalIntegrationTest.wrong_provider"
        ])
      end)

    assert output =~ "Failed:    1"
    assert output =~ "COMPLETED (no gate)"
  end

  test "repeats provider execution and reduces attempts with the selected rule", %{
    tmp_dir: tmp_dir
  } do
    path = Path.join(tmp_dir, "sampled.json")
    report_path = Path.join(tmp_dir, "sampled_report.json")
    File.write!(path, ~s([{"input":"hello","expected":{"contains":["hello"]}}]))
    counter = start_supervised!({Agent, fn -> 0 end})
    Process.register(counter, Tribunal.SampledProviderCounter)

    Mix.Task.reenable("tribunal.eval")
    Mix.Task.reenable("app.start")

    capture_io(fn ->
      Eval.run([
        path,
        "--format",
        "json",
        "--output",
        report_path,
        "--repeat",
        "3",
        "--pass-rule",
        "any",
        "--threshold",
        "1.0",
        "--provider",
        "Mix.Tasks.TribunalEvalIntegrationTest.sampled_provider"
      ])
    end)

    report = report_path |> File.read!() |> JSON.decode!()
    assert Agent.get(Tribunal.SampledProviderCounter, & &1) == 3
    assert report["summary"]["passed"] == 1
    assert report["summary"]["attempts"]["total"] == 3
    assert report["cases"] |> hd() |> Map.fetch!("attempts") |> length() == 3
  end

  test "passes structured input unchanged to the Mix provider", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "structured.json")

    File.write!(
      path,
      JSON.encode!([
        %{
          "input" => %{"query" => "hello", "account_id" => 42},
          "evaluation_input" => "hello",
          "expected" => %{"contains" => ["hello"]}
        }
      ])
    )

    Mix.Task.reenable("tribunal.eval")
    Mix.Task.reenable("app.start")

    output =
      capture_io(fn ->
        Eval.run([
          path,
          "--format",
          "text",
          "--provider",
          "Mix.Tasks.TribunalEvalIntegrationTest.structured_provider"
        ])
      end)

    assert output =~ "Passed:    1"
  end

  test "loads sampling and gates from a versioned policy", %{tmp_dir: tmp_dir} do
    dataset = Path.join(tmp_dir, "policy_dataset.json")
    policy = Path.join(tmp_dir, "tribunal_eval.yaml")
    report_path = Path.join(tmp_dir, "policy_report.json")

    File.write!(
      dataset,
      JSON.encode!([
        %{
          "input" => "hello",
          "actual_output" => "hello",
          "metadata" => %{"kind" => "core"},
          "expected" => %{"contains" => ["hello"]}
        }
      ])
    )

    File.write!(
      policy,
      """
      version: 1
      datasets: [#{dataset}]
      sampling:
        repeat: 3
        pass_rule: all
      gates:
        overall: {pass_rate: 1.0}
        groups: {by: kind, pass_rate: 1.0}
      """
    )

    Mix.Task.reenable("tribunal.eval")
    Mix.Task.reenable("app.start")

    capture_io(fn ->
      Eval.run(["--config", policy, "--format", "json", "--output", report_path])
    end)

    report = report_path |> File.read!() |> JSON.decode!()
    assert report["summary"]["attempts"]["total"] == 3
    assert report["summary"]["gate_status"] == "passed"
    assert report["gates"]["groups"]["results"] |> hd() |> Map.fetch!("value") == "core"
  end

  test "positional datasets replace policy datasets", %{tmp_dir: tmp_dir} do
    dataset = Path.join(tmp_dir, "cli_dataset.json")
    policy = Path.join(tmp_dir, "tribunal_eval.yaml")

    File.write!(
      dataset,
      ~s([{"input":"hello","actual_output":"hello","expected":{"contains":["hello"]}}])
    )

    File.write!(policy, "version: 1\ndatasets: [missing.json]\n")

    Mix.Task.reenable("tribunal.eval")
    Mix.Task.reenable("app.start")

    output = capture_io(fn -> Eval.run([dataset, "--config", policy, "--format", "text"]) end)
    assert output =~ "Passed:    1"
    refute output =~ "missing.json"
  end

  test "rejects invalid group metadata before provider invocation", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "missing_group.json")
    File.write!(path, ~s([{"input":"hello","expected":{"contains":["hello"]}}]))
    counter = start_supervised!({Agent, fn -> 0 end})
    Process.register(counter, Tribunal.GroupProviderCounter)

    Mix.Task.reenable("tribunal.eval")
    Mix.Task.reenable("app.start")

    assert_raise Mix.Error, ~r/missing metadata group/, fn ->
      Eval.run([
        path,
        "--provider",
        "Mix.Tasks.TribunalEvalIntegrationTest.counting_provider",
        "--group-by",
        "kind",
        "--group-threshold",
        "1.0"
      ])
    end

    assert Agent.get(Tribunal.GroupProviderCounter, & &1) == 0
  end

  test "keeps dataset group membership when a provider returns authoritative metadata", %{
    tmp_dir: tmp_dir
  } do
    path = Path.join(tmp_dir, "provider_metadata.json")
    report_path = Path.join(tmp_dir, "provider_metadata_report.json")

    File.write!(
      path,
      ~s([{"input":"hello","metadata":{"kind":"core"},"expected":{"contains":["hello"]}}])
    )

    Mix.Task.reenable("tribunal.eval")
    Mix.Task.reenable("app.start")

    capture_io(fn ->
      Eval.run([
        path,
        "--provider",
        "Mix.Tasks.TribunalEvalIntegrationTest.metadata_replacing_provider",
        "--repeat",
        "2",
        "--group-by",
        "kind",
        "--group-threshold",
        "1.0",
        "--format",
        "json",
        "--output",
        report_path
      ])
    end)

    report = report_path |> File.read!() |> JSON.decode!()
    assert [%{"value" => "core", "total" => 1}] = report["gates"]["groups"]["results"]
  end

  test "fails when no eval files exist", %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      Mix.Task.reenable("tribunal.eval")

      assert_raise Mix.Error, ~r/No eval files found/, fn -> Eval.run([]) end
    end)
  end

  test "fails when a dataset contains no cases", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "empty.json")
    File.write!(path, "[]")

    Mix.Task.reenable("tribunal.eval")
    Mix.Task.reenable("app.start")

    output =
      capture_io(fn ->
        assert_raise Mix.Error, "Evaluation failed", fn ->
          Eval.run([path, "--format", "text"])
        end
      end)

    assert output =~ "Total:     0 test cases"
    assert output =~ "FAILED"
  end

  test "fails when offset skips every case", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "offset.json")

    File.write!(
      path,
      ~s([{"input":"hello","actual_output":"hello","expected":{"contains":["hello"]}}])
    )

    Mix.Task.reenable("tribunal.eval")
    Mix.Task.reenable("app.start")

    output =
      capture_io(fn ->
        assert_raise Mix.Error, "Evaluation failed", fn ->
          Eval.run([path, "--format", "text", "--offset", "1"])
        end
      end)

    assert output =~ "Total:     0 test cases"
    assert output =~ "FAILED"
  end

  @tag capture_log: true
  test "reports a killed concurrent provider without killing the run", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "killed_provider.json")

    File.write!(
      path,
      JSON.encode!([
        %{"input" => "kill", "expected" => %{"contains" => ["ok"]}},
        %{"input" => "pass", "expected" => %{"contains" => ["ok"]}}
      ])
    )

    output = run_eval(path, "killing_provider")

    assert output =~ "Passed:    1"
    assert output =~ "Failed:    1"
    assert output =~ "Evaluation task failed"
  end

  @tag capture_log: true
  test "isolates a killed provider with default concurrency", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "killed_sequential_provider.json")

    File.write!(
      path,
      JSON.encode!([
        %{"input" => "kill", "expected" => %{"contains" => ["ok"]}}
      ])
    )

    Mix.Task.reenable("tribunal.eval")
    Mix.Task.reenable("app.start")

    output =
      capture_io(fn ->
        assert_raise Mix.Error, "Evaluation failed", fn ->
          Eval.run([
            path,
            "--format",
            "text",
            "--provider",
            "Mix.Tasks.TribunalEvalIntegrationTest.killing_provider"
          ])
        end
      end)

    assert output =~ "Failed:    1"
    assert output =~ "Evaluation task failed"
  end

  @tag capture_log: true
  test "reports a concurrent provider timeout", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "timeout_provider.json")

    File.write!(
      path,
      JSON.encode!([
        %{"input" => "slow", "expected" => %{"contains" => ["ok"]}},
        %{"input" => "pass", "expected" => %{"contains" => ["ok"]}}
      ])
    )

    previous_timeout = Application.get_env(:tribunal, :eval_timeout)
    Application.put_env(:tribunal, :eval_timeout, 50)

    on_exit(fn ->
      if is_nil(previous_timeout) do
        Application.delete_env(:tribunal, :eval_timeout)
      else
        Application.put_env(:tribunal, :eval_timeout, previous_timeout)
      end
    end)

    output = run_eval(path, "slow_provider")

    assert output =~ "Passed:    1"
    assert output =~ "Failed:    1"
    assert output =~ "Evaluation task failed: :timeout"
  end

  defp run_eval(path, provider) do
    Mix.Task.reenable("tribunal.eval")
    Mix.Task.reenable("app.start")

    capture_io(fn ->
      assert_raise Mix.Error, "Evaluation failed", fn ->
        Eval.run([
          path,
          "--format",
          "text",
          "--concurrency",
          "2",
          "--provider",
          "Mix.Tasks.TribunalEvalIntegrationTest.#{provider}"
        ])
      end
    end)
  end

  def failing_provider(_test_case), do: raise("provider exploded")
  def wrong_provider(_test_case), do: "wrong answer"

  def sampled_provider(_test_case) do
    attempt = Agent.get_and_update(Tribunal.SampledProviderCounter, &{&1 + 1, &1 + 1})
    if attempt == 2, do: "hello", else: "goodbye"
  end

  def structured_provider(%Tribunal.TestCase{
        input: %{"query" => "hello", "account_id" => 42}
      }),
      do: "hello"

  def counting_provider(_test_case) do
    Agent.update(Tribunal.GroupProviderCounter, &(&1 + 1))
    "hello"
  end

  def metadata_replacing_provider(_test_case) do
    %Tribunal.TestCase{input: "returned", actual_output: "hello", metadata: %{"kind" => "edge"}}
  end

  def killing_provider(%Tribunal.TestCase{input: "kill"}), do: Process.exit(self(), :kill)
  def killing_provider(%Tribunal.TestCase{input: "pass"}), do: "ok"

  def slow_provider(%Tribunal.TestCase{input: "slow"}) do
    Process.sleep(500)
    "ok"
  end

  def slow_provider(%Tribunal.TestCase{input: "pass"}), do: "ok"
end
