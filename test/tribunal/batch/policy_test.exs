defmodule Tribunal.Batch.PolicyTest do
  use ExUnit.Case, async: true

  alias Tribunal.Batch.Policy

  describe "parse/2" do
    test "normalizes a complete version 1 policy without atomizing metadata fields" do
      cwd = Path.join(System.tmp_dir!(), "tribunal-policy-cwd")

      yaml = """
      version: 1
      datasets:
        - test/evals/first.yaml
        - ../shared/second.yaml
      sampling:
        repeat: 5
        pass_rule:
          rate: 0.8
      gates:
        overall:
          pass_rate: 0.9
        groups:
          by: error_case
          threshold: 0.75
      """

      assert {:ok, policy} = Policy.parse(yaml, cwd: cwd)

      assert policy == %{
               version: 1,
               datasets: [
                 Path.expand("test/evals/first.yaml", cwd),
                 Path.expand("../shared/second.yaml", cwd)
               ],
               sampling: %{repeat: 5, pass_rule: {:rate, 0.8}},
               gates: %{
                 overall: %{threshold: 0.9},
                 groups: %{by: "error_case", threshold: 0.75}
               }
             }
    end

    test "accepts the named pass rules and omits unspecified optional sections" do
      for {value, expected} <- [{"all", :all}, {"any", :any}, {"majority", :majority}] do
        yaml = """
        version: 1
        datasets: [evals.yaml]
        sampling:
          pass_rule: #{value}
        """

        assert {:ok, %{sampling: %{pass_rule: ^expected}, gates: %{}}} = Policy.parse(yaml)
      end
    end

    test "requires version 1 and a nonempty dataset list by default" do
      assert {:error, "policy version is required"} = Policy.parse("datasets: [evals.yaml]")

      assert {:error, error} = Policy.parse("version: 2\ndatasets: [evals.yaml]")
      assert error =~ "unsupported policy version 2"

      for datasets <- ["", "datasets: []", "datasets: evals.yaml", "datasets: [evals.yaml, 2]"] do
        yaml = "version: 1\n#{datasets}"
        assert {:error, error} = Policy.parse(yaml)
        assert error =~ "datasets must be a nonempty list"
      end
    end

    test "allows omitted or empty datasets when positional files will replace them" do
      assert {:ok, %{datasets: []}} =
               Policy.parse("version: 1", allow_empty_datasets: true)

      assert {:ok, %{datasets: []}} =
               Policy.parse("version: 1\ndatasets: []", allow_empty_datasets: true)
    end

    test "rejects unknown keys at every supported map level without creating atoms" do
      unknown = "unknown_#{System.unique_integer([:positive])}"
      assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end

      cases = [
        {"policy", "#{unknown}: true"},
        {"sampling", "sampling:\n  #{unknown}: true"},
        {"sampling.pass_rule", "sampling:\n  pass_rule:\n    rate: 0.8\n    #{unknown}: true"},
        {"gates", "gates:\n  #{unknown}: true"},
        {"gates.overall", "gates:\n  overall:\n    threshold: 0.9\n    #{unknown}: true"},
        {"gates.groups",
         "gates:\n  groups:\n    by: category\n    threshold: 0.8\n    #{unknown}: true"}
      ]

      for {location, fragment} <- cases do
        yaml = "version: 1\ndatasets: [evals.yaml]\n#{fragment}\n"
        assert {:error, error} = Policy.parse(yaml)
        assert error =~ "unknown #{location} keys"
        assert error =~ unknown
      end

      assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
    end

    test "validates sampling values" do
      for fragment <- [
            "repeat: 0",
            "repeat: 1.5",
            "pass_rule: some",
            "pass_rule: {rate: -0.1}",
            "pass_rule: {rate: 1.1}"
          ] do
        yaml = "version: 1\ndatasets: [evals.yaml]\nsampling:\n  #{fragment}\n"
        assert {:error, error} = Policy.parse(yaml)
        assert error =~ "sampling."
      end
    end

    test "validates overall and group gate configuration" do
      invalid = [
        {"gates.overall must be a map", "gates:\n  overall: 0.9"},
        {"gates.overall.threshold is required", "gates:\n  overall: {}"},
        {"cannot set both", "gates:\n  overall: {pass_rate: 0.9, threshold: 0.8}"},
        {"between 0.0 and 1.0", "gates:\n  overall: {threshold: 1.1}"},
        {"gates.groups must be a map", "gates:\n  groups: category"},
        {"gates.groups.by must be a nonempty string", "gates:\n  groups: {threshold: 0.8}"},
        {"gates.groups.by must be a nonempty string",
         "gates:\n  groups: {by: 42, threshold: 0.8}"},
        {"gates.groups.threshold is required", "gates:\n  groups: {by: category}"}
      ]

      for {message, fragment} <- invalid do
        yaml = "version: 1\ndatasets: [evals.yaml]\n#{fragment}\n"
        assert {:error, error} = Policy.parse(yaml)
        assert error =~ message
      end
    end

    test "rejects malformed YAML and non-map documents" do
      assert {:error, "policy must be a YAML map"} = Policy.parse("- version\n- datasets")
      assert {:error, error} = Policy.parse("version: [")
      assert error =~ "invalid policy YAML"
    end
  end

  describe "load/2" do
    test "loads the policy and resolves paths from the configured current directory" do
      tmp_dir = temp_dir!()
      policy_path = Path.join(tmp_dir, "batch.yaml")

      File.write!(policy_path, "version: 1\ndatasets: [datasets/evals.yaml]\n")

      assert {:ok, %{datasets: [dataset]}} = Policy.load("batch.yaml", cwd: tmp_dir)
      assert dataset == Path.join(tmp_dir, "datasets/evals.yaml")
    end

    test "returns an actionable read error" do
      tmp_dir = temp_dir!()

      assert {:error, error} = Policy.load("missing.yaml", cwd: tmp_dir)
      assert error =~ Path.join(tmp_dir, "missing.yaml")
      assert error =~ "no such file or directory"
    end
  end

  describe "resolve/3" do
    test "applies explicit values over policy values over defaults" do
      policy =
        parse!("""
        version: 1
        datasets: [policy.yaml]
        sampling:
          repeat: 3
          pass_rule: majority
        gates:
          overall: {threshold: 0.8}
          groups: {by: category, threshold: 0.7}
        """)

      defaults = %{repeat: 1, pass_rule: :all, strict: false, threshold: 0.5}

      explicit = %{
        datasets: ["cli.yaml"],
        repeat: 7,
        pass_rule: :any,
        group_by: "kind",
        group_threshold: 0.6
      }

      assert {:ok, settings} = Policy.resolve(policy, explicit, defaults)

      assert settings == %{
               datasets: [Path.expand("cli.yaml")],
               repeat: 7,
               pass_rule: :any,
               strict: false,
               threshold: 0.8,
               group_by: "kind",
               group_threshold: 0.6
             }
    end

    test "positional datasets replace policy datasets and fill an intentionally empty policy" do
      empty_policy = parse!("version: 1", allow_empty_datasets: true)

      assert {:ok, %{datasets: datasets}} =
               Policy.resolve(empty_policy, datasets: ["first.yaml", "second.yaml"])

      assert datasets == [Path.expand("first.yaml"), Path.expand("second.yaml")]

      policy = parse!("version: 1\ndatasets: [policy.yaml]")
      assert {:ok, %{datasets: [dataset]}} = Policy.resolve(policy, datasets: ["cli.yaml"])
      assert dataset == Path.expand("cli.yaml")
    end

    test "uses default datasets only when policy and positional datasets are empty" do
      policy = parse!("version: 1", allow_empty_datasets: true)

      assert {:ok, %{datasets: [dataset]}} =
               Policy.resolve(policy, %{}, datasets: ["default.yaml"])

      assert dataset == Path.expand("default.yaml")

      assert {:error, error} = Policy.resolve(policy, %{})
      assert error =~ "datasets must be a nonempty list"
    end

    test "rejects strict mode combined with an effective threshold" do
      policy = parse!("version: 1\ndatasets: [evals.yaml]\ngates:\n  overall: {threshold: 0.8}")

      assert {:error, "strict cannot be combined with threshold"} =
               Policy.resolve(policy, strict: true)

      policy = parse!("version: 1\ndatasets: [evals.yaml]")

      assert {:error, "strict cannot be combined with threshold"} =
               Policy.resolve(policy, %{strict: true, threshold: 0.8})
    end

    test "validates the resolved runtime shape" do
      policy = parse!("version: 1\ndatasets: [evals.yaml]")

      assert {:error, error} = Policy.resolve(policy, unknown: true)
      assert error =~ "unknown explicit settings keys"

      assert {:error, "group_threshold is required with group_by"} =
               Policy.resolve(policy, group_by: "category")

      assert {:error, "group_by is required with group_threshold"} =
               Policy.resolve(policy, group_threshold: 0.8)
    end
  end

  defp parse!(yaml, opts \\ []) do
    assert {:ok, policy} = Policy.parse(yaml, opts)
    policy
  end

  defp temp_dir! do
    path =
      Path.join(System.tmp_dir!(), "tribunal-policy-#{System.unique_integer([:positive])}")

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end
end
