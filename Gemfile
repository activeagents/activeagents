source "https://rubygems.org"

# Use edge Rails from main branch
gem "rails", github: "rails/rails", branch: "main"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Bundle and transpile JavaScript [https://github.com/rails/jsbundling-rails]
gem "jsbundling-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Bundle and process CSS [https://github.com/rails/cssbundling-rails]
gem "cssbundling-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"
# Markdown rendering for landing pages [https://github.com/vmg/redcarpet]
gem "redcarpet"
# Syntax highlighting for code snippets [https://github.com/rouge-ruby/rouge]
gem "rouge"
# Inertia adapter for Rails [https://inertia-rails.dev]
gem "inertia_rails"
# Active Agent - AI agent framework for Rails [https://github.com/activeagents/activeagent]
gem "activeagent", github: "activeagents/activeagent", branch: "main"
# Solid Agent - Persistence and context management for ActiveAgent
gem "solid_agent", github: "activeagents/solid_agent", branch: "main"
# RubyLLM - model registry (token pricing data) and unified provider API
gem "ruby_llm"
# Ragents - Ractor-based AI agents for benchmarking (Ruby 4.0+)
gem "ragents", path: "ragents"
# Anthropic Claude API client for Active Agent providers
gem "anthropic"
# OpenAI client, also used by the Ollama/OpenRouter providers (OpenAI-compatible APIs)
gem "openai", "~> 0.34"
# Resend email delivery service [https://resend.com/docs/send-with-ruby]
gem "resend"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.7"

# Payment processing with Pay gem [https://github.com/pay-rails/pay]
gem "pay", "~> 7.3"
# Stripe payment processor [https://stripe.com/docs/api]
# Pay gem 7.3 requires stripe ~> 12
gem "stripe", "~> 18.4"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data"

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Pagination [https://github.com/kaminari/kaminari]
gem "kaminari"

# Google Cloud client libraries for Cloud Run sandbox management
gem "google-cloud-run-v2"
gem "google-cloud-logging"

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Load environment variables from .env file [https://github.com/bkeepers/dotenv]
  gem "dotenv-rails"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end
