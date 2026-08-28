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

    output = capture_io(fn -> Eval.run([path, "--format", "text"]) end)

    assert output =~ "Failed:    1"
    assert output =~ "evaluation: Missing actual output"
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
        Eval.run([
          path,
          "--format",
          "text",
          "--provider",
          "Mix.Tasks.TribunalEvalIntegrationTest.failing_provider"
        ])
      end)

    assert output =~ "Failed:    1"
    assert output =~ "provider: provider exploded"
  end

  test "fails when no eval files exist", %{tmp_dir: tmp_dir} do
    File.cd!(tmp_dir, fn ->
      Mix.Task.reenable("tribunal.eval")

      assert_raise Mix.Error, ~r/No eval files found/, fn -> Eval.run([]) end
    end)
  end

  def failing_provider(_test_case), do: raise("provider exploded")
end
