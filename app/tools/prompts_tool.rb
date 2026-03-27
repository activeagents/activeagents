# frozen_string_literal: true

# PromptsTool - Prompt composition and management
#
# Enables agents to build, compose, and reuse prompt templates.
# Supports loading prompts from agent definitions and composing
# multi-part prompts for complex tasks.
#
# Usage:
#   PromptsTool.call(operation: "build", template: "You are a {role}. {task}", variables: { role: "reviewer", task: "Review this code" })
#   PromptsTool.call(operation: "compose", parts: [{ role: "system", content: "..." }, { role: "user", content: "..." }])
#   PromptsTool.call(operation: "list")
#
class PromptsTool < BaseTool
  tool_name "prompts"
  description "Build, compose, and manage prompt templates. Create structured prompts from templates with variable substitution, or compose multi-part prompts."

  parameter :operation, type: "string", description: "The operation to perform", required: true, enum: %w[build compose list from_agent]
  parameter :template, type: "string", description: "Prompt template with {variable} placeholders (for build)"
  parameter :variables, type: "object", description: "Variables to substitute into the template (for build)"
  parameter :parts, type: "array", description: "Array of prompt parts to compose (for compose). Each part has 'role' and 'content'."
  parameter :agent_name, type: "string", description: "Agent name or slug to load prompt from (for from_agent)"
  parameter :context, type: "object", description: "Additional context to include in the prompt"

  MAX_PROMPT_LENGTH = 100_000 # ~100K characters

  def call(operation:, template: nil, variables: {}, parts: [], agent_name: nil, context: {})
    case operation
    when "build"
      raise ParameterError, "template is required for build operation" if template.blank?
      build_prompt(template, variables, context)
    when "compose"
      raise ParameterError, "parts are required for compose operation" if parts.blank?
      compose_prompt(parts, context)
    when "list"
      list_available_prompts
    when "from_agent"
      raise ParameterError, "agent_name is required for from_agent operation" if agent_name.blank?
      load_agent_prompt(agent_name, context)
    else
      raise ParameterError, "Unknown operation: #{operation}. Must be one of: build, compose, list, from_agent"
    end
  end

  private

  def build_prompt(template, variables, context)
    # Substitute {variable} placeholders
    prompt = template.dup
    variables.each do |key, value|
      prompt.gsub!("{#{key}}", value.to_s)
    end

    # Append context if provided
    if context.present?
      prompt += "\n\nContext:\n#{format_context(context)}"
    end

    validate_length!(prompt)

    {
      prompt: prompt,
      variables_used: variables.keys,
      unresolved: prompt.scan(/\{(\w+)\}/).flatten,
      length: prompt.length
    }
  end

  def compose_prompt(parts, context)
    messages = parts.map do |part|
      role = part["role"] || part[:role] || "user"
      content = part["content"] || part[:content] || ""

      validate_role!(role)

      { role: role, content: content }
    end

    # Add context as a system message if provided
    if context.present?
      context_message = { role: "system", content: "Additional context:\n#{format_context(context)}" }
      messages.unshift(context_message)
    end

    total_length = messages.sum { |m| m[:content].length }
    validate_length!(total_length)

    {
      messages: messages,
      part_count: messages.size,
      total_length: total_length
    }
  end

  def list_available_prompts
    prompts = []

    # List prompts from database agents
    Agent.active_agents.where.not(instructions: [nil, ""]).limit(50).each do |agent|
      prompts << {
        source: "agent",
        name: agent.name,
        slug: agent.slug,
        preview: agent.instructions.truncate(200),
        agent_id: agent.id
      }
    end

    # List prompts from agent classes
    if defined?(ApplicationAgent)
      ApplicationAgent.descendants.each do |klass|
        instance = klass.new rescue next
        if instance.respond_to?(:default_instructions)
          prompts << {
            source: "class",
            name: klass.name,
            preview: instance.default_instructions.truncate(200)
          }
        end
      end
    end

    { prompts: prompts, count: prompts.size }
  end

  def load_agent_prompt(agent_name, context)
    agent = Agent.find_by(slug: agent_name) ||
            Agent.find_by(name: agent_name)

    unless agent
      raise ExecutionError, "Agent not found: #{agent_name}"
    end

    prompt = agent.instructions || ""

    if context.present?
      prompt += "\n\nContext:\n#{format_context(context)}"
    end

    {
      agent: agent.name,
      agent_id: agent.id,
      prompt: prompt,
      provider: agent.provider,
      model: agent.model,
      tools: agent.tools
    }
  end

  def format_context(context)
    context.map { |key, value| "#{key}: #{value}" }.join("\n")
  end

  def validate_role!(role)
    valid_roles = %w[system user assistant]
    unless valid_roles.include?(role)
      raise ParameterError, "Invalid role: #{role}. Must be one of: #{valid_roles.join(', ')}"
    end
  end

  def validate_length!(content)
    length = content.is_a?(String) ? content.length : content.to_i
    if length > MAX_PROMPT_LENGTH
      raise ParameterError, "Prompt exceeds maximum length of #{MAX_PROMPT_LENGTH} characters"
    end
  end
end
