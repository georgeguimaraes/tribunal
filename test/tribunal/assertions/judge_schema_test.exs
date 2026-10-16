defmodule Tribunal.Assertions.JudgeSchemaTest do
  # Registers a custom judge through application config.
  use ExUnit.Case, async: false

  alias Tribunal.Assertions.Judge
  alias Tribunal.Evaluator
  alias Tribunal.Reporter.JSON, as: JSONReporter
  alias Tribunal.TestCase

  defmodule Rubric do
    @behaviour Tribunal.Judge

    @criteria ["accuracy", "completeness", "tone"]
    @ratings ["yes", "partial", "no", "not_applicable"]

    @impl true
    def name, do: :rubric

    @impl true
    def prompt(test_case, _opts) do
      """
      Rate the response on accuracy, completeness, and tone.
      Use "not_applicable" when a criterion does not apply.

      Response: #{test_case.actual_output}
      """
    end

    @impl true
    def schema(_opts) do
      criterion =
        {:map,
         [
           rating: [type: {:in, @ratings}, required: true],
           reason: [type: :string, required: true]
         ]}

      Enum.map(@criteria, &{String.to_atom(&1), [type: criterion, required: true]})
    end

    @impl true
    def evaluate_result(response, _opts) do
      ratings = Map.new(@criteria, &{&1, get_in(response, [&1, "rating"])})
      applicable = Enum.reject(ratings, fn {_criterion, rating} -> rating == "not_applicable" end)
      unmet = for {criterion, rating} <- applicable, rating != "yes", do: criterion

      details = %{
        verdict: if(applicable != [] and unmet == [], do: "yes", else: "no"),
        reason: reason(applicable, unmet),
        score: score(applicable),
        criteria: response
      }

      if details.verdict == "yes", do: {:pass, details}, else: {:fail, details}
    end

    defp reason([], _unmet), do: "No criterion applies"
    defp reason(_applicable, []), do: "All applicable criteria are met"
    defp reason(_applicable, unmet), do: "Unmet criteria: #{Enum.join(unmet, ", ")}"

    defp score([]), do: 0.0

    defp score(applicable) do
      Enum.count(applicable, fn {_criterion, rating} -> rating == "yes" end) / length(applicable)
    end
  end

  defmodule CitedVerdict do
    @behaviour Tribunal.Judge

    @impl true
    def name, do: :cited_verdict

    @impl true
    def prompt(test_case, _opts), do: "Is this response accurate? #{test_case.actual_output}"

    @impl true
    def schema(_opts) do
      [
        verdict: [type: :string, required: true],
        reason: [type: :string, required: true],
        score: [type: :float],
        quotes: [type: {:list, :string}, required: true]
      ]
    end
  end

  setup do
    previous = Application.get_env(:tribunal, :custom_judges, [])
    Application.put_env(:tribunal, :custom_judges, [Rubric, CitedVerdict])
    on_exit(fn -> Application.put_env(:tribunal, :custom_judges, previous) end)

    %{test_case: %TestCase{input: "How do I reset my password?", actual_output: "Answer"}}
  end

  defp rubric_client(ratings) do
    response =
      Map.new(ratings, fn {criterion, rating} ->
        {criterion, %{"rating" => rating, "reason" => "#{criterion} is #{rating}"}}
      end)

    fn _model, messages, opts ->
      send(self(), {:judge_request, messages, opts[:schema]})
      {:ok, response}
    end
  end

  describe "judges with a custom schema" do
    test "request the judge's schema instead of the default verdict fields", %{
      test_case: test_case
    } do
      client = rubric_client(%{"accuracy" => "yes", "completeness" => "yes", "tone" => "yes"})

      assert {:pass, _details} = Judge.evaluate(:rubric, test_case, llm: client)
      assert_received {:judge_request, messages, schema}

      assert schema == Rubric.schema([])
      system_prompt = Enum.find(messages, &(&1.role == "system")).content
      assert system_prompt =~ "matches the requested schema"
      refute system_prompt =~ ~s(verdict: "yes")
    end

    test "pass the decoded object to evaluate_result/2", %{test_case: test_case} do
      client = rubric_client(%{"accuracy" => "yes", "completeness" => "yes", "tone" => "yes"})

      assert {:pass, details} = Judge.evaluate(:rubric, test_case, llm: client)
      assert details.criteria["tone"] == %{"rating" => "yes", "reason" => "tone is yes"}
    end

    test "ignore criteria rated not applicable", %{test_case: test_case} do
      client =
        rubric_client(%{
          "accuracy" => "yes",
          "completeness" => "not_applicable",
          "tone" => "yes"
        })

      assert {:pass, details} = Judge.evaluate(:rubric, test_case, llm: client)
      assert details.score == 1.0
    end

    test "fail when an applicable criterion is not met", %{test_case: test_case} do
      client =
        rubric_client(%{"accuracy" => "yes", "completeness" => "partial", "tone" => "no"})

      assert {:fail, details} = Judge.evaluate(:rubric, test_case, llm: client)
      assert details.reason == "Unmet criteria: completeness, tone"
      assert_in_delta details.score, 1 / 3, 0.001
    end

    test "fail when no criterion applies", %{test_case: test_case} do
      client =
        rubric_client(%{
          "accuracy" => "not_applicable",
          "completeness" => "not_applicable",
          "tone" => "not_applicable"
        })

      assert {:fail, details} = Judge.evaluate(:rubric, test_case, llm: client)
      assert details.reason == "No criterion applies"
    end

    test "keep verdict, score, reason, and criteria in JSON reports", %{test_case: test_case} do
      client = rubric_client(%{"accuracy" => "no", "completeness" => "yes", "tone" => "yes"})

      result = Evaluator.evaluate(test_case, [{:rubric, [llm: client]}])
      assert result.failures == [{:rubric, "Unmet criteria: accuracy"}]

      [evaluation] =
        %{cases: [result]}
        |> JSONReporter.format()
        |> JSON.decode!()
        |> get_in(["cases", Access.at(0), "evaluations"])

      assert %{"type" => "rubric", "result" => %{"fail" => details}} = evaluation
      assert details["verdict"] == "no"
      assert details["reason"] == "Unmet criteria: accuracy"
      assert_in_delta details["score"], 2 / 3, 0.001
      assert details["criteria"]["accuracy"]["rating"] == "no"
    end
  end

  describe "judges with a custom schema and the default interpretation" do
    test "keep the verdict instructions and verdict logic", %{test_case: test_case} do
      client = fn _model, messages, opts ->
        send(self(), {:judge_request, messages, opts[:schema]})

        {:ok,
         %{"verdict" => "partial", "reason" => "Mostly", "score" => 0.9, "quotes" => ["Answer"]}}
      end

      assert {:pass, details} = Judge.evaluate(:cited_verdict, test_case, llm: client)
      assert details == %{verdict: "partial", reason: "Mostly", score: 0.9}
      assert_received {:judge_request, messages, schema}

      assert Keyword.has_key?(schema, :quotes)
      system_prompt = Enum.find(messages, &(&1.role == "system")).content
      assert system_prompt =~ ~s(verdict: "yes", "no", or "partial")
      assert system_prompt =~ "any other fields the requested schema defines"
    end
  end

  describe "judges without a custom schema" do
    test "request the default verdict fields", %{test_case: test_case} do
      client = fn _model, messages, opts ->
        send(self(), {:judge_request, messages, opts[:schema]})
        {:ok, %{"verdict" => "yes", "reason" => "Relevant", "score" => 0.9}}
      end

      assert {:pass, details} = Judge.evaluate(:relevant, test_case, llm: client)
      assert details == %{verdict: "yes", reason: "Relevant", score: 0.9}
      assert_received {:judge_request, messages, schema}

      assert Keyword.keys(schema) == [:verdict, :reason, :score]
      system_prompt = Enum.find(messages, &(&1.role == "system")).content
      assert system_prompt =~ ~s(verdict: "yes", "no", or "partial")
    end
  end
end
