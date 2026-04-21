# frozen_string_literal: true

require_relative "lib/ragents/version"

Gem::Specification.new do |spec|
  spec.name = "ragents"
  spec.version = Ragents::VERSION
  spec.authors = [ "ActiveAgents" ]
  spec.email = [ "hello@activeagents.ai" ]

  spec.summary = "Ractor-based AI agents with a Charm-inspired TUI — pure Ruby, no dependencies"
  spec.description = <<~DESC
    Ragents brings the Ractor concurrency model to AI agent orchestration. Each agent
    runs in its own Ractor — an isolated parallel execution context with its own GVL —
    enabling true multi-core utilization for I/O-heavy LLM workloads. Context is managed
    via immutable, shareable message objects passed between Ractors, and tool calls /
    MCP interactions / agent-as-a-tool patterns are expressed as first-class message
    types that flow safely across Ractor boundaries.
  DESC

  spec.homepage = "https://github.com/activeagents/ragents"
  spec.license = "MIT"

  # Ragents uses Ractors for true parallelism in AI agent orchestration.
  # Ractors have been available since Ruby 3.0 but became more stable in 3.2+.
  # Ruby 3.3+ is recommended for the best Ractor performance.
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata = {
    "homepage_uri"    => spec.homepage,
    "source_code_uri" => "https://github.com/activeagents/ragents",
    "changelog_uri"   => "https://github.com/activeagents/ragents/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/activeagents/ragents/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir.glob(%w[
    lib/**/*.rb
    sig/**/*.rbs
    README.md
    LICENSE.txt
    CHANGELOG.md
  ]).reject { |f| File.directory?(f) }

  spec.bindir = "bin"
  spec.executables = spec.files.grep(%r{\Abin/}) { |f| File.basename(f) }
  spec.require_paths = [ "lib" ]

  # Pure Ruby — no C extensions, no Go binaries.
  # The TUI is styled after the Charm (charm.sh) aesthetic — rounded borders,
  # gradient text, Lipgloss-inspired colour palette — implemented entirely via
  # ANSI/VT100 escape sequences using Ruby's stdlib io/console + io/wait.
  # Provider SDKs are optional dependencies brought in by the consuming app.
  spec.add_dependency "json", ">= 2.7"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "minitest-reporters", "~> 1.7"
  spec.add_development_dependency "rubocop", "~> 1.70"
  spec.add_development_dependency "rubocop-minitest", "~> 0.36"
  spec.add_development_dependency "rubocop-performance", "~> 1.22"
  spec.add_development_dependency "webmock", "~> 3.23"
  spec.add_development_dependency "benchmark-ips", "~> 2.13"
end
