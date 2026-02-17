class DashboardController < ApplicationController
  def index
    render inertia: "Dashboard", props: {
      user: current_user_props,
      initialAgents: agents_data,
      meta: meta_data
    }
  end

  private

  def current_user_props
    # Placeholder for user data
    { name: "Developer" }
  end

  def agents_data
    Agent.order(updated_at: :desc).limit(20).map do |agent|
      {
        id: agent.id,
        name: agent.name,
        slug: agent.slug,
        description: agent.description,
        provider: agent.provider,
        model: agent.model,
        status: agent.status,
        presetType: agent.preset_type,
        appearance: agent.appearance,
        versionCount: agent.version_count,
        createdAt: agent.created_at,
        updatedAt: agent.updated_at
      }
    end
  rescue ActiveRecord::StatementInvalid
    # Table doesn't exist yet
    []
  end

  def meta_data
    {
      providers: Agent::PROVIDERS,
      presetTypes: Agent::PRESET_TYPES,
      instructionSets: Agent::INSTRUCTION_SETS,
      availableTools: Agent::AVAILABLE_TOOLS
    }
  rescue NameError
    # Agent class not loaded yet
    {
      providers: %w[openai anthropic ollama openrouter],
      presetTypes: %w[terminal webDeveloper research writing],
      instructionSets: %w[github ruby rails aws gcp python typescript docker kubernetes],
      availableTools: %w[terminal playwright filesystem code database slack fetch search edit translate memory]
    }
  end
end
