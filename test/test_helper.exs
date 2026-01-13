# Exclude LLM tests by default (require API key)
# Run with: mix test --include llm
ExUnit.configure(exclude: [:llm])
ExUnit.start()
