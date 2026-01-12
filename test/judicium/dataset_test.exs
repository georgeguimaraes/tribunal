defmodule Judicium.DatasetTest do
  use ExUnit.Case, async: false

  alias Judicium.Dataset

  setup do
    fixtures_path =
      Path.join(System.tmp_dir!(), "judicium_dataset_test_#{:rand.uniform(100_000)}")

    File.mkdir_p!(fixtures_path)

    json_content = """
    [
      {
        "input": "What is the return policy?",
        "context": "Returns within 30 days.",
        "expected": {
          "contains": ["30 days"]
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
        contains:
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
  end

  describe "load!/1" do
    test "raises on error" do
      assert_raise RuntimeError, fn ->
        Dataset.load!("nonexistent.json")
      end
    end
  end

  describe "load_with_assertions/1" do
    test "extracts assertions from JSON", %{fixtures_path: fixtures_path} do
      {:ok, cases} = Dataset.load_with_assertions(Path.join(fixtures_path, "test_dataset.json"))

      assert length(cases) == 2

      {tc1, assertions1} = hd(cases)
      assert tc1.input == "What is the return policy?"
      assert {:contains, [value: ["30 days"]]} in assertions1
    end

    test "extracts multiple assertions", %{fixtures_path: fixtures_path} do
      {:ok, cases} = Dataset.load_with_assertions(Path.join(fixtures_path, "test_dataset.json"))

      {_tc2, assertions2} = Enum.at(cases, 1)
      types = Enum.map(assertions2, fn {type, _} -> type end)

      assert :contains_any in types
      assert :not_contains in types
    end
  end
end
