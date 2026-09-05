defmodule Tribunal.DatasetTest do
  use ExUnit.Case, async: false

  alias Tribunal.{Dataset, TestCase}

  setup do
    fixtures_path =
      Path.join(System.tmp_dir!(), "tribunal_dataset_test_#{:rand.uniform(100_000)}")

    File.mkdir_p!(fixtures_path)

    json_content = """
    [
      {
        "input": "What is the return policy?",
        "context": "Returns within 30 days.",
        "expected": {
          "contains_all": ["30 days"]
        }
      },
      {
        "input": "Do you ship internationally?",
        "context": "US and Canada only.",
        "expected": {
          "contains_any": ["US", "Canada"],
          "not_contains": ["worldwide"]
        }
      }
    ]
    """

    yaml_content = """
    - input: What is the return policy?
      context: Returns within 30 days.
      expected:
        contains_all:
          - 30 days

    - input: Do you ship internationally?
      context: US and Canada only.
      expected:
        contains_any:
          - US
          - Canada
    """

    File.write!(Path.join(fixtures_path, "test_dataset.json"), json_content)
    File.write!(Path.join(fixtures_path, "test_dataset.yaml"), yaml_content)

    on_exit(fn ->
      File.rm_rf!(fixtures_path)
    end)

    {:ok, fixtures_path: fixtures_path}
  end

  describe "load/1" do
    test "loads JSON dataset", %{fixtures_path: fixtures_path} do
      {:ok, cases} = Dataset.load(Path.join(fixtures_path, "test_dataset.json"))

      assert length(cases) == 2
      assert hd(cases).input == "What is the return policy?"
      assert hd(cases).context == ["Returns within 30 days."]
    end

    test "loads YAML dataset", %{fixtures_path: fixtures_path} do
      {:ok, cases} = Dataset.load(Path.join(fixtures_path, "test_dataset.yaml"))

      assert length(cases) == 2
      assert hd(cases).input == "What is the return policy?"
    end

    test "returns error for missing file" do
      assert {:error, _} = Dataset.load("nonexistent.json")
    end

    test "returns error for unsupported format", %{fixtures_path: fixtures_path} do
      File.write!(Path.join(fixtures_path, "test.txt"), "hello")
      assert {:error, _} = Dataset.load(Path.join(fixtures_path, "test.txt"))
    end

    test "returns errors for structurally invalid datasets", %{fixtures_path: fixtures_path} do
      top_level = Path.join(fixtures_path, "top_level_object.json")
      invalid_case = Path.join(fixtures_path, "invalid_case.json")
      missing_input = Path.join(fixtures_path, "missing_input.json")
      invalid_expected = Path.join(fixtures_path, "invalid_expected.json")
      invalid_expected_list = Path.join(fixtures_path, "invalid_expected_list.json")
      invalid_context = Path.join(fixtures_path, "invalid_context.json")
      invalid_evaluation_input = Path.join(fixtures_path, "invalid_evaluation_input.json")
      invalid_options = Path.join(fixtures_path, "invalid_options.yaml")
      invalid_case_keys = Path.join(fixtures_path, "invalid_case_keys.yaml")

      File.write!(top_level, JSON.encode!(%{"input" => "hello"}))
      File.write!(invalid_case, JSON.encode!([42]))
      File.write!(missing_input, JSON.encode!([%{"expected" => %{}}]))
      File.write!(invalid_expected, JSON.encode!([%{"input" => "hello", "expected" => 42}]))

      File.write!(
        invalid_expected_list,
        JSON.encode!([%{"input" => "hello", "expected" => [%{"contains" => "x"}]}])
      )

      File.write!(invalid_context, JSON.encode!([%{"input" => "hello", "context" => 42}]))

      File.write!(
        invalid_evaluation_input,
        JSON.encode!([%{"input" => 42, "evaluation_input" => 42}])
      )

      File.write!(invalid_options, "- input: hello\n  expected:\n    contains:\n      1: hello\n")
      File.write!(invalid_case_keys, "- input: hello\n  1: ignored\n")

      assert {:error, {:invalid_dataset, _}} = Dataset.load(top_level)
      assert {:error, {:invalid_case, 0, "case must be an object"}} = Dataset.load(invalid_case)
      assert {:error, {:invalid_case, 0, "input is required"}} = Dataset.load(missing_input)

      assert {:error, {:invalid_case, 0, "expected must be an object or list"}} =
               Dataset.load(invalid_expected)

      assert {:error, {:invalid_case, 0, "expected list items must be assertion names" <> _}} =
               Dataset.load(invalid_expected_list)

      assert {:error, {:invalid_case, 0, "context must be a string or list of strings"}} =
               Dataset.load(invalid_context)

      assert {:error, {:invalid_case, 0, "evaluation_input must be a string"}} =
               Dataset.load(invalid_evaluation_input)

      assert {:error,
              {:invalid_case, 0,
               "expected assertions must use string or atom names and valid options"}} =
               Dataset.load(invalid_options)

      assert {:error, {:invalid_case, 0, "case field names must be strings or atoms"}} =
               Dataset.load(invalid_case_keys)
    end
  end

  describe "load!/1" do
    test "raises on error" do
      assert_raise RuntimeError, fn ->
        Dataset.load!("nonexistent.json")
      end
    end
  end

  describe "load_with_assertions/1" do
    test "list contains fails evaluation while contains_all evaluates every substring", %{
      fixtures_path: fixtures_path
    } do
      for extension <- ["json", "yaml"] do
        path = Path.join(fixtures_path, "contains_contract.#{extension}")

        content =
          if extension == "json" do
            ~s([{"input":"hello","expected":{"contains":["hello","world"],"contains_all":["hello","world"]}}])
          else
            """
            - input: hello
              expected:
                contains: [hello, world]
                contains_all: [hello, world]
            """
          end

        File.write!(path, content)
        assert {:ok, [{test_case, assertions}]} = Dataset.load_with_assertions(path)

        results =
          Tribunal.Assertions.evaluate_all(assertions, %{test_case | actual_output: "hello world"})

        assert {:error, reason} = results[:contains]
        assert reason =~ "single string"
        assert {:pass, _} = results[:contains_all]

        missing =
          Tribunal.Assertions.evaluate_all(assertions, %{test_case | actual_output: "hello"})

        assert {:fail, %{missing: ["world"]}} = missing[:contains_all]
      end
    end

    test "loads structured input and judge-facing evaluation text", %{
      fixtures_path: fixtures_path
    } do
      path = Path.join(fixtures_path, "structured_input.json")

      File.write!(
        path,
        JSON.encode!([
          %{
            "input" => %{"query" => "hello", "account_id" => 42},
            "evaluation_input" => "hello for account 42",
            "expected" => %{"contains" => "hello"}
          }
        ])
      )

      assert {:ok, [{test_case, [{:contains, [value: "hello"]}]}]} =
               Dataset.load_with_assertions(path)

      assert test_case.input == %{"query" => "hello", "account_id" => 42}
      assert TestCase.evaluation_input(test_case) == "hello for account 42"
    end

    test "extracts assertions from JSON", %{fixtures_path: fixtures_path} do
      {:ok, cases} = Dataset.load_with_assertions(Path.join(fixtures_path, "test_dataset.json"))

      assert length(cases) == 2

      {tc1, assertions1} = hd(cases)
      assert tc1.input == "What is the return policy?"
      assert {:contains_all, [value: ["30 days"]]} in assertions1
    end

    test "extracts multiple assertions", %{fixtures_path: fixtures_path} do
      {:ok, cases} = Dataset.load_with_assertions(Path.join(fixtures_path, "test_dataset.json"))

      {_tc2, assertions2} = Enum.at(cases, 1)
      types = Enum.map(assertions2, fn {type, _} -> type end)

      assert :contains_any in types
      assert :not_contains in types
    end

    test "does not create atoms for unknown assertion names", %{fixtures_path: fixtures_path} do
      name = "unknown_#{System.unique_integer([:positive])}"
      path = Path.join(fixtures_path, "unknown_assertion.json")
      File.write!(path, JSON.encode!([%{"input" => "hello", "expected" => %{name => %{}}}]))

      refute existing_atom?(name)
      assert {:ok, [{_test_case, [{^name, []}]}]} = Dataset.load_with_assertions(path)
      refute existing_atom?(name)
    end

    test "resolves registered custom judge names", %{fixtures_path: fixtures_path} do
      path = Path.join(fixtures_path, "custom_judge.json")

      File.write!(
        path,
        JSON.encode!([
          %{
            "input" => "hello",
            "expected" => %{"dataset_custom_judge" => %{"rules" => "be concise"}}
          }
        ])
      )

      previous = Application.get_env(:tribunal, :custom_judges, [])
      Application.put_env(:tribunal, :custom_judges, [Tribunal.DatasetCustomJudge])
      on_exit(fn -> Application.put_env(:tribunal, :custom_judges, previous) end)

      assert {:ok, [{_test_case, [{:dataset_custom_judge, [rules: "be concise"]}]}]} =
               Dataset.load_with_assertions(path)
    end

    test "resolves built-in judge option keys explicitly", %{fixtures_path: fixtures_path} do
      path = Path.join(fixtures_path, "judge_options.json")

      File.write!(
        path,
        JSON.encode!([
          %{
            "input" => "hello",
            "expected" => %{
              "faithful" => %{
                "model" => "anthropic:claude-haiku-4-5-20251001",
                "threshold" => 0.9
              }
            }
          }
        ])
      )

      assert {:ok,
              [
                {_test_case,
                 [
                   {:faithful, [model: "anthropic:claude-haiku-4-5-20251001", threshold: 0.9]}
                 ]}
              ]} = Dataset.load_with_assertions(path)
    end
  end

  defp existing_atom?(value) do
    _atom = String.to_existing_atom(value)
    true
  rescue
    ArgumentError -> false
  end
end

defmodule Tribunal.DatasetCustomJudge do
  @behaviour Tribunal.Judge

  @impl true
  def name, do: :dataset_custom_judge

  @impl true
  def prompt(_test_case, opts), do: Keyword.fetch!(opts, :rules)
end
