# frozen_string_literal: true

class Agent < ApplicationRecord
  belongs_to :user, optional: true
  has_many :agent_versions, dependent: :destroy
  has_many :agent_runs, dependent: :destroy

  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :slug, presence: true, uniqueness: { scope: :user_id }, format: { with: /\A[a-z0-9\-_]+\z/ }
  validates :provider, presence: true
  validates :model, presence: true

  # Status enum
  enum :status, { draft: 0, active: 1, archived: 2 }

  # Callbacks
  before_validation :generate_slug, on: :create
  after_create :create_initial_version
  after_update :create_version_on_config_change, if: :configuration_changed?

  # Scopes
  scope :active_agents, -> { where(status: :active) }
  scope :by_provider, ->(provider) { where(provider: provider) }
  scope :with_tool, ->(tool) { where("tools @> ?", [ tool ].to_json) }

  # Available presets matching AgentAvatar component
  PRESET_TYPES = %w[
    terminal webDeveloper documentAnalysis writing translation
    playwright research imageAnalysis computerUse productDesign
  ].freeze

  # Available instruction sets
  INSTRUCTION_SETS = %w[
    github ruby rails aws gcp python typescript docker kubernetes
  ].freeze

  # Available tools/MCPs
  AVAILABLE_TOOLS = %w[
    terminal playwright filesystem code database slack fetch search edit translate memory
  ].freeze

  # Available providers
  PROVIDERS = %w[openai anthropic ollama openrouter].freeze

  # Returns the configuration as a hash for versioning
  def configuration_snapshot
    {
      name: name,
      description: description,
      provider: provider,
      model: model,
      instructions: instructions,
      preset_type: preset_type,
      appearance: appearance,
      instruction_sets: instruction_sets,
      tools: tools,
      mcp_servers: mcp_servers,
      model_config: model_config,
      response_format: response_format
    }
  end

  # Restore from a version
  def restore_from_version!(version)
    config = version.configuration_snapshot
    update!(
      instructions: config["instructions"],
      preset_type: config["preset_type"],
      appearance: config["appearance"],
      instruction_sets: config["instruction_sets"],
      tools: config["tools"],
      mcp_servers: config["mcp_servers"],
      model_config: config["model_config"],
      response_format: config["response_format"]
    )
  end

  # Get the latest version
  def latest_version
    agent_versions.order(version_number: :desc).first
  end

  # Get version count
  def version_count
    agent_versions.count
  end

  # Generate Ruby agent class code
  def to_agent_class_code
    <<~RUBY
      class #{agent_class_name || name.camelize}Agent < ApplicationAgent
        generate_with :#{provider}, model: "#{model}"#{model_config_code}

        def perform
          prompt#{instructions_code}
        end
      end
    RUBY
  end

  # Execute a run with this agent
  def execute(input_prompt, **params)
    run = agent_runs.create!(
      input_prompt: input_prompt,
      input_params: params,
      status: :pending,
      trace_id: SecureRandom.uuid
    )

    # Queue the execution job
    AgentExecutionJob.perform_later(run.id)

    run
  end

  # Quick test execution (synchronous)
  def test_execute(input_prompt, **params)
    run = agent_runs.create!(
      input_prompt: input_prompt,
      input_params: params,
      status: :running,
      trace_id: SecureRandom.uuid,
      started_at: Time.current
    )

    begin
      # Build and execute the agent
      result = build_and_execute_agent(input_prompt, **params)

      run.update!(
        output: result[:output],
        output_metadata: result[:metadata],
        status: :complete,
        completed_at: Time.current,
        duration_ms: ((Time.current - run.started_at) * 1000).to_i,
        input_tokens: result.dig(:usage, :input_tokens),
        output_tokens: result.dig(:usage, :output_tokens),
        total_tokens: result.dig(:usage, :total_tokens)
      )
    rescue => e
      run.update!(
        status: :failed,
        completed_at: Time.current,
        error_message: e.message,
        error_backtrace: e.backtrace&.first(10)&.join("\n")
      )
    end

    run
  end

  private

  def generate_slug
    return if slug.present?

    base_slug = name.to_s.parameterize
    self.slug = base_slug

    # Ensure uniqueness
    counter = 1
    while Agent.exists?(slug: slug)
      self.slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  end

  def create_initial_version
    agent_versions.create!(
      version_number: 1,
      change_summary: "Initial creation",
      configuration_snapshot: configuration_snapshot
    )
  end

  def configuration_changed?
    saved_changes.keys.any? do |key|
      %w[instructions preset_type appearance instruction_sets tools mcp_servers model_config response_format].include?(key)
    end
  end

  def create_version_on_config_change
    next_version = (latest_version&.version_number || 0) + 1
    changed_fields = saved_changes.keys.select do |key|
      %w[instructions preset_type appearance instruction_sets tools mcp_servers model_config response_format].include?(key)
    end

    agent_versions.create!(
      version_number: next_version,
      change_summary: "Updated: #{changed_fields.join(', ')}",
      configuration_snapshot: configuration_snapshot
    )
  end

  def model_config_code
    return "" if model_config.blank?

    configs = model_config.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
    ", #{configs}"
  end

  def instructions_code
    return "" if instructions.blank?

    "\n    prompt instructions: <<~INSTRUCTIONS\n      #{instructions.gsub("\n", "\n      ")}\n    INSTRUCTIONS"
  end

  def build_and_execute_agent(input_prompt, **params)
    # This will be implemented to actually execute via ActiveAgent
    # For now, return a mock response
    {
      output: "Mock response for: #{input_prompt}",
      metadata: { provider: provider, model: model },
      usage: { input_tokens: 10, output_tokens: 20, total_tokens: 30 }
    }
  end
end
