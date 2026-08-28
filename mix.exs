defmodule Tribunal.MixProject do
  use Mix.Project

  @version "2.0.0"
  @source_url "https://github.com/georgeguimaraes/tribunal"

  def project do
    [
      app: :tribunal,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Tribunal",
      description: "LLM evaluation framework for Elixir",
      package: package(),
      docs: docs(),
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Tribunal.Application, []}
    ]
  end

  defp deps do
    [
      # Required: YAML parsing for configs/datasets
      {:yaml_elixir, ">= 2.11.0 and < 3.0.0"},

      # Optional: LLM-as-judge metrics
      {:req_llm, ">= 1.2.0 and < 2.0.0", optional: true},

      # Optional: embedding similarity
      {:alike, ">= 0.4.0 and < 0.5.0", optional: true},

      # Dev
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["George Guimarães"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib guides mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "Tribunal",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "guides/getting-started.md",
        "guides/evaluation-modes.md",
        "guides/exunit-integration.md",
        "guides/assertions.md",
        "guides/llm-as-judge.md",
        "guides/datasets.md",
        "guides/red-team-testing.md",
        "guides/reporters.md",
        "guides/github-actions.md"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ],
      groups_for_modules: [
        Core: [
          Tribunal,
          Tribunal.TestCase,
          Tribunal.Assertions,
          Tribunal.Evaluator
        ],
        "Assertion Types": [
          Tribunal.Assertions.Deterministic,
          Tribunal.Assertions.Judge,
          Tribunal.Assertions.Embedding
        ],
        Testing: [
          Tribunal.ExUnit,
          Tribunal.Dataset,
          Tribunal.RedTeam
        ],
        Judges: [
          Tribunal.Judge,
          Tribunal.Judges.Faithful,
          Tribunal.Judges.Relevant,
          Tribunal.Judges.Hallucination,
          Tribunal.Judges.Hallucinated,
          Tribunal.Judges.Correctness,
          Tribunal.Judges.Refusal,
          Tribunal.Judges.Bias,
          Tribunal.Judges.Toxicity,
          Tribunal.Judges.Harmful,
          Tribunal.Judges.Jailbreak,
          Tribunal.Judges.Pii,
          Tribunal.Judges.PolicyViolation,
          Tribunal.Judges.ExcessiveAgency,
          Tribunal.Judges.Hijacked,
          Tribunal.Judges.Imitation,
          Tribunal.Judges.PromptExtracted
        ],
        "Red Team": [
          Tribunal.RedTeam.Plugin,
          Tribunal.RedTeam.Plugin.Base,
          Tribunal.RedTeam.Attacker,
          Tribunal.RedTeam.Attacker.ReqLLM,
          Tribunal.RedTeam.Attacker.Stub,
          Tribunal.RedTeam.Plugins.Policy,
          Tribunal.RedTeam.Plugins.ExcessiveAgency,
          Tribunal.RedTeam.Plugins.PromptExtraction,
          Tribunal.RedTeam.Plugins.Imitation,
          Tribunal.RedTeam.Plugins.Hijacking,
          Tribunal.RedTeam.Plugins.Hallucination,
          Tribunal.RedTeam.YamlEmit
        ],
        Reporters: [
          Tribunal.Reporter,
          Tribunal.Reporter.Console,
          Tribunal.Reporter.Text,
          Tribunal.Reporter.JSON,
          Tribunal.Reporter.HTML,
          Tribunal.Reporter.GitHub,
          Tribunal.Reporter.JUnit
        ]
      ]
    ]
  end
end
