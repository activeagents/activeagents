# frozen_string_literal: true

module Api
  class TemplatesController < BaseController
    include AgentSerialization

    # No anonymous exemption: #show looks a template up by bare id, so the
    # exemption served unpublished drafts and private prompt libraries to
    # anyone walking the id space. #index was already limited to public
    # templates; #show was not.

    # GET /api/templates
    def index
      @templates = AgentTemplate.public_templates.order(usage_count: :desc)

      # Filter by category
      @templates = @templates.by_category(params[:category]) if params[:category].present?

      # Featured only
      @templates = @templates.featured if params[:featured].present?

      render json: {
        templates: @templates.map { |t| template_json(t) },
        categories: AgentTemplate::CATEGORIES
      }
    end

    # GET /api/templates/:id
    def show
      @template = AgentTemplate.find(params[:id])
      render json: { template: template_json(@template, include_details: true) }
    end

    # POST /api/templates/:id/use
    def use
      @template = AgentTemplate.find(params[:id])

      agent = @template.create_agent_for(
        current_user,
        name: params[:name] || @template.name
      )

      # The detail shape, not a summary: the dashboard opens the new agent in
      # the editor straight from this response. Seeded from a summary, the
      # editor showed the agent as unconfigured and its first Save persisted
      # empty instructions/tools/model_config over the template's real ones.
      if agent.persisted?
        render json: { agent: agent_json(agent, include_details: true) }, status: :created
      else
        render json: { errors: agent.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def template_json(template, include_details: false)
      json = {
        id: template.id,
        name: template.name,
        slug: template.slug,
        description: template.description,
        category: template.category,
        provider: template.provider,
        model: template.model,
        preset_type: template.preset_type,
        appearance: template.appearance,
        icon: template.icon,
        usage_count: template.usage_count,
        featured: template.featured,
        tools: template.tools
      }

      if include_details
        json.merge!(
          instructions: template.instructions,
          instruction_sets: template.instruction_sets,
          model_config: template.model_config
        )
      end

      json
    end
  end
end
