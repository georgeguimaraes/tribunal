defmodule Mix.Tasks.TribunalTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Tribunal.{Eval, Init}

  import ExUnit.CaptureIO

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    json_content = """
    [
      {
        "input": "What is the return policy?",
        "actual_output": "You can return items within 30 days.",
        "expected": {
          "contains": ["30 days"]
        }
      },
      {
        "input": "What are the hours?",
        "actual_output": "We are open 9am to 5pm.",
        "expected": {
          "contains": ["9am", "5pm"]
        }
      }
    ]
    """

    fixtures_path = Path.join(tmp_dir, "evals")
    File.mkdir_p!(fixtures_path)
    File.write!(Path.join(fixtures_path, "test_dataset.json"), json_content)

    {:ok, fixtures_path: fixtures_path}
  end

  describe "Eval" do
    test "has moduledoc with usage info" do
      {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(Eval)

      assert moduledoc =~ "--format"
      assert moduledoc =~ "console"
      assert moduledoc =~ "text"
      assert moduledoc =~ "json"
      assert moduledoc =~ "html"
      assert moduledoc =~ "junit"
      assert moduledoc =~ "github"
      assert moduledoc =~ "--provider"
      assert moduledoc =~ "Module.function"
      assert moduledoc =~ "--output"
      assert moduledoc =~ "--threshold"
      assert moduledoc =~ "--strict"
      assert moduledoc =~ "--concurrency"
    end

    test "module implements Mix.Task behaviour" do
      behaviours = Eval.__info__(:attributes)[:behaviour] || []
      assert Mix.Task in behaviours
    end
  end

  describe "Init" do
    test "creates directory structure", %{tmp_dir: tmp_dir} do
      output =
        capture_io(fn ->
          Init.run([], base_dir: tmp_dir)
        end)

      assert output =~ "Created"
      assert output =~ "test/evals"
      assert output =~ "example.json"
      assert output =~ "example.yaml"

      assert File.dir?(Path.join(tmp_dir, "test/evals/datasets"))
      assert File.exists?(Path.join(tmp_dir, "test/evals/datasets/example.json"))
      assert File.exists?(Path.join(tmp_dir, "test/evals/datasets/example.yaml"))

      # Verify JSON content is valid
      {:ok, json_content} = File.read(Path.join(tmp_dir, "test/evals/datasets/example.json"))
      {:ok, _} = Jason.decode(json_content)

      # Verify YAML content is valid
      {:ok, yaml_content} = File.read(Path.join(tmp_dir, "test/evals/datasets/example.yaml"))
      {:ok, _} = YamlElixir.read_from_string(yaml_content)
    end

    test "does not overwrite existing files", %{tmp_dir: tmp_dir} do
      # Create the directories and a file first
      File.mkdir_p!(Path.join(tmp_dir, "test/evals/datasets"))
      File.write!(Path.join(tmp_dir, "test/evals/datasets/example.json"), "existing content")

      capture_io(fn ->
        Init.run([], base_dir: tmp_dir)
      end)

      # Original file should be preserved
      content = File.read!(Path.join(tmp_dir, "test/evals/datasets/example.json"))
      assert content == "existing content"
    end
  end
end
