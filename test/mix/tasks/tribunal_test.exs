defmodule Mix.Tasks.TribunalTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Tribunal.{Eval, Init}

  import ExUnit.CaptureIO

  @fixtures_path "test/fixtures/evals"

  setup_all do
    File.mkdir_p!(@fixtures_path)

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

    File.write!(Path.join(@fixtures_path, "test_dataset.json"), json_content)

    on_exit(fn ->
      File.rm_rf!(@fixtures_path)
    end)

    :ok
  end

  describe "Eval" do
    test "has moduledoc with usage info" do
      {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(Eval)

      assert moduledoc =~ "--format"
      assert moduledoc =~ "console"
      assert moduledoc =~ "json"
      assert moduledoc =~ "junit"
      assert moduledoc =~ "github"
      assert moduledoc =~ "--provider"
      assert moduledoc =~ "Module:function"
      assert moduledoc =~ "--output"
      assert moduledoc =~ "--threshold"
      assert moduledoc =~ "--strict"
    end

    test "module implements Mix.Task behaviour" do
      behaviours = Eval.__info__(:attributes)[:behaviour] || []
      assert Mix.Task in behaviours
    end
  end

  describe "Init" do
    test "creates directory structure" do
      # Use a temp directory
      tmp_dir = Path.join(System.tmp_dir!(), "tribunal_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(tmp_dir)

      try do
        # Change to temp dir for the test
        original_dir = File.cwd!()
        File.cd!(tmp_dir)

        output =
          capture_io(fn ->
            Init.run([])
          end)

        assert output =~ "Created test/evals/"
        assert output =~ "Created test/evals/datasets/"
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

        File.cd!(original_dir)
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "does not overwrite existing files" do
      tmp_dir = Path.join(System.tmp_dir!(), "tribunal_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(tmp_dir)

      try do
        original_dir = File.cwd!()
        File.cd!(tmp_dir)

        # Create the directories and a file first
        File.mkdir_p!("test/evals/datasets")
        File.write!("test/evals/datasets/example.json", "existing content")

        capture_io(fn ->
          Init.run([])
        end)

        # Original file should be preserved
        content = File.read!("test/evals/datasets/example.json")
        assert content == "existing content"

        File.cd!(original_dir)
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end
end
