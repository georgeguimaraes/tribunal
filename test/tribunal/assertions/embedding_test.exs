defmodule Tribunal.Assertions.EmbeddingTest do
  use ExUnit.Case, async: true

  alias Tribunal.Assertions.Embedding
  alias Tribunal.TestCase

  describe "evaluate/2" do
    test "returns pass when output is similar to expected" do
      test_case = %TestCase{
        actual_output: "The cat is sleeping on the couch",
        expected_output: "A feline is resting on the sofa"
      }

      # Mock Alike.similarity to avoid loading actual ML models
      mock_alike = fn _s1, _s2, _opts -> {:ok, 0.85} end

      assert {:pass, details} = Embedding.evaluate(test_case, alike_fn: mock_alike)
      assert details.similarity == 0.85
      assert details.threshold == 0.7
    end

    test "returns fail when output is not similar to expected" do
      test_case = %TestCase{
        actual_output: "The cat is sleeping",
        expected_output: "The weather is nice today"
      }

      mock_alike = fn _s1, _s2, _opts -> {:ok, 0.2} end

      assert {:fail, details} = Embedding.evaluate(test_case, alike_fn: mock_alike)
      assert details.similarity == 0.2
      assert details.reason =~ "not semantically similar"
    end

    test "uses custom threshold" do
      test_case = %TestCase{
        actual_output: "Hello there",
        expected_output: "Hi there"
      }

      mock_alike = fn _s1, _s2, _opts -> {:ok, 0.6} end

      # With default threshold (0.7), should fail
      assert {:fail, _} = Embedding.evaluate(test_case, alike_fn: mock_alike)

      # With lower threshold, should pass
      assert {:pass, details} =
               Embedding.evaluate(test_case, threshold: 0.5, alike_fn: mock_alike)

      assert details.threshold == 0.5
    end

    test "returns error when expected_output is missing" do
      test_case = %TestCase{
        actual_output: "Some output"
      }

      assert {:error, reason} = Embedding.evaluate(test_case, [])
      assert reason =~ "expected_output"
    end

    test "handles Alike error gracefully" do
      test_case = %TestCase{
        actual_output: "Some output",
        expected_output: "Expected"
      }

      mock_alike = fn _s1, _s2, _opts -> {:error, :timeout} end

      assert {:error, reason} = Embedding.evaluate(test_case, alike_fn: mock_alike)
      assert reason =~ "similarity"
    end
  end

  describe "available/0" do
    test "returns list of embedding assertions" do
      available = Embedding.available()

      assert :similar in available
    end
  end
end
