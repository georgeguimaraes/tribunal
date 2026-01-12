# Judicium

LLM evaluation framework for Elixir.

**Judicium** (Latin: "judgment") provides tools for evaluating LLM outputs, detecting hallucinations, and measuring response quality. Named after *Judicium Dei* (Judgment of God), the medieval trial by ordeal.

## Installation

```elixir
def deps do
  [
    {:judicium, "~> 0.1.0"}
  ]
end
```

## Usage

```elixir
# Evaluate a response against context
Judicium.evaluate(response,
  context: source_documents,
  criteria: [:faithfulness, :relevancy]
)

# Check for hallucinations
Judicium.hallucination?(response, source: source_documents)

# Use LLM-as-judge pattern
Judicium.judge(response, prompt: original_prompt, rubric: scoring_rubric)
```

## Metrics

- **Faithfulness** - Is the response grounded in the provided context?
- **Relevancy** - Does the response address the query?
- **Hallucination** - Does the response contain fabricated information?
- **Coherence** - Is the response logically consistent?
- **Toxicity** - Does the response contain harmful content?

## Roadmap

- [ ] Core evaluation pipeline
- [ ] Faithfulness metric (RAGAS-style)
- [ ] Hallucination detection
- [ ] LLM-as-judge with configurable models
- [ ] ExUnit integration for test assertions
- [ ] Async batch evaluation

## License

MIT
