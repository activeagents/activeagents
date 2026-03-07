# Changelog

All notable changes to Ragents will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-03-01

### Added

- Initial release of the `ragents` gem
- `Ragents::Ractor::AgentRactor` — Ractor-based agent execution with supervisor/worker split
- `Ragents::Ractor::Supervisor` — Multi-agent orchestration with agent-as-a-tool pattern
- `Ragents::Ractor::AgentPool` — Bounded parallel agent pool with rate limiting
- Immutable `Data.define` message types for zero-copy Ractor boundary crossing:
  - `UserMessage`, `AssistantMessage`, `SystemMessage`
  - `ToolCallMessage`, `ToolResultMessage`
  - `AgentCallMessage`, `AgentResultMessage`
  - `ErrorMessage` (cross-Ractor exception propagation)
- `Ragents::Context` — Mutable conversation history with Ractor-safe snapshot/import
- `Ragents::Tool` + `Ragents::ToolRegistry` — Frozen tool definitions with JSON Schema
- Pure-Ruby providers (no SDK dependencies, stdlib `Net::HTTP` only):
  - `OpenAIProvider` — OpenAI, Azure, Ollama, OpenRouter
  - `AnthropicProvider` — Claude 3.x models
  - `MockProvider` — Scripted responses for testing
- Benchmark suite:
  - `concurrent_llm_benchmark.rb` — Sequential / Threads / Ractors / Async comparison
  - `puma_vs_falcon_comparison.rb` — Architectural model comparison
  - `ractor_object_passing_benchmark.rb` — Zero-copy vs Marshal overhead analysis
- `bin/ragents` CLI for interactive agent sessions
