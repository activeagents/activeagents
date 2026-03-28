# frozen_string_literal: true

# GenerativeRouting - Deterministically Generative pattern
#
# Enables agents to route their generation results to different actions
# based on the content of the response. This allows building workflows
# where LLM output determines the next step (redirect, render, action call).
#
# Generation routes are stored in the agent's model_config under "generation_routes".
#
# Usage:
#   agent.add_generation_route("summarize", to: "render_summary")
#   agent.add_generation_route("need_more_info", to: "ask_clarification")
#   result = agent.generate_and_route(input_prompt, session_id: "abc")
#
module GenerativeRouting
  extend ActiveSupport::Concern

  # Execute generation and route the result based on configured patterns
  def generate_and_route(input_prompt, session_id: nil, **params)
    result = build_and_execute_agent(input_prompt, **params)
    return result if generation_routes.blank?

    route = classify_and_route(result[:output])
    result[:metadata] = (result[:metadata] || {}).merge(route: route)
    result
  end

  def generation_routes
    model_config&.dig("generation_routes") || {}
  end

  def add_generation_route(pattern, to:)
    routes = generation_routes.merge(pattern.to_s => to.to_s)
    self.model_config = (model_config || {}).merge("generation_routes" => routes)
  end

  def remove_generation_route(pattern)
    routes = generation_routes.except(pattern.to_s)
    self.model_config = (model_config || {}).merge("generation_routes" => routes)
  end

  private

  def classify_and_route(output)
    return { type: :content, target: nil } if output.blank?

    generation_routes.each do |pattern, target|
      if output.match?(Regexp.new(pattern, Regexp::IGNORECASE))
        route_type = classify_target(target)
        return { type: route_type, target: target, matched_pattern: pattern }
      end
    end

    { type: :content, target: nil }
  end

  def classify_target(target)
    case target
    when /\Aredirect_to_/
      :redirect
    when /\Arender_/
      :render
    when /\Acall_/
      :action
    else
      :content
    end
  end
end
