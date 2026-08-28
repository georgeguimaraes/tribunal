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

  def killing_provider(%Tribunal.TestCase{input: "kill"}), do: Process.exit(self(), :kill)
  def killing_provider(%Tribunal.TestCase{input: "pass"}), do: "ok"

  def slow_provider(%Tribunal.TestCase{input: "slow"}) do
    Process.sleep(500)
    "ok"
  end

  def slow_provider(%Tribunal.TestCase{input: "pass"}), do: "ok"
end
