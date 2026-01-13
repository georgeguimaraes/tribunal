defmodule Tribunal.JudgeTest do
  use ExUnit.Case, async: true

  alias Tribunal.Judge

  defmodule MockBrandVoice do
    @behaviour Tribunal.Judge

    @impl true
    def name, do: :brand_voice

    @impl true
    def prompt(test_case, _opts) do
      """
      Evaluate if the response matches brand voice guidelines.

      Response: #{test_case.actual_output}
      """
    end
  end

  defmodule MockCompliance do
    @behaviour Tribunal.Judge

    @impl true
    def name, do: :compliance

    @impl true
    def prompt(test_case, opts) do
      rules = opts[:rules] || "default rules"

      """
      Check compliance with: #{rules}

      Response: #{test_case.actual_output}
      """
    end

    @impl true
    def evaluate_result(response, _opts) do
      # Custom logic: fail if score < 0.9
      if response["score"] >= 0.9 do
        {:pass,
         %{verdict: response["verdict"], reason: response["reason"], score: response["score"]}}
      else
        {:fail,
         %{verdict: response["verdict"], reason: "Score too low", score: response["score"]}}
      end
    end
  end

  describe "behaviour" do
    test "module can implement the behaviour" do
      assert MockBrandVoice.name() == :brand_voice
      assert is_binary(MockBrandVoice.prompt(%Tribunal.TestCase{actual_output: "test"}, []))
    end

    test "optional evaluate_result callback" do
      assert function_exported?(MockCompliance, :evaluate_result, 2)
      refute function_exported?(MockBrandVoice, :evaluate_result, 2)
    end
  end

  describe "custom_judges/0" do
    test "returns empty list when no judges configured" do
      # Clear any existing config
      original = Application.get_env(:tribunal, :custom_judges)
      Application.delete_env(:tribunal, :custom_judges)

      assert Judge.custom_judges() == []

      # Restore
      if original, do: Application.put_env(:tribunal, :custom_judges, original)
    end

    test "returns configured judges" do
      original = Application.get_env(:tribunal, :custom_judges)
      Application.put_env(:tribunal, :custom_judges, [MockBrandVoice, MockCompliance])

      assert Judge.custom_judges() == [MockBrandVoice, MockCompliance]

      # Restore
      if original do
        Application.put_env(:tribunal, :custom_judges, original)
      else
        Application.delete_env(:tribunal, :custom_judges)
      end
    end
  end

  describe "find/1" do
    setup do
      original = Application.get_env(:tribunal, :custom_judges)
      Application.put_env(:tribunal, :custom_judges, [MockBrandVoice, MockCompliance])

      on_exit(fn ->
        if original do
          Application.put_env(:tribunal, :custom_judges, original)
        else
          Application.delete_env(:tribunal, :custom_judges)
        end
      end)

      :ok
    end

    test "finds registered judge by name" do
      assert {:ok, MockBrandVoice} = Judge.find(:brand_voice)
      assert {:ok, MockCompliance} = Judge.find(:compliance)
    end

    test "returns error for unknown judge" do
      assert :error = Judge.find(:unknown_judge)
    end
  end

  describe "custom_judge_names/0" do
    setup do
      original = Application.get_env(:tribunal, :custom_judges)
      Application.put_env(:tribunal, :custom_judges, [MockBrandVoice, MockCompliance])

      on_exit(fn ->
        if original do
          Application.put_env(:tribunal, :custom_judges, original)
        else
          Application.delete_env(:tribunal, :custom_judges)
        end
      end)

      :ok
    end

    test "returns list of custom judge names" do
      names = Judge.custom_judge_names()
      assert :brand_voice in names
      assert :compliance in names
    end
  end

  describe "custom_judge?/1" do
    setup do
      original = Application.get_env(:tribunal, :custom_judges)
      Application.put_env(:tribunal, :custom_judges, [MockBrandVoice])

      on_exit(fn ->
        if original do
          Application.put_env(:tribunal, :custom_judges, original)
        else
          Application.delete_env(:tribunal, :custom_judges)
        end
      end)

      :ok
    end

    test "returns true for registered custom judge" do
      assert Judge.custom_judge?(:brand_voice)
    end

    test "returns false for built-in judge" do
      refute Judge.custom_judge?(:faithful)
    end

    test "returns false for unknown judge" do
      refute Judge.custom_judge?(:unknown)
    end
  end
end
