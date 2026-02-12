class PlaygroundController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:execute, :reset]

  AGENTS = {
    "research" => {
      name: "Research Agent",
      description: "Gathers information and finds authoritative sources with citations",
      class_name: "ResearchAgent",
      action: "investigate",
      icon: "search",
      color: "blue",
      source_file: "app/agents/research_agent.rb",
      template_files: [
        "app/views/agents/research/instructions.md.erb",
        "app/views/agents/research/investigate.md.erb"
      ]
    },
    "writing" => {
      name: "Writing Agent",
      description: "Drafts structured documents from research findings",
      class_name: "WritingAgent",
      action: "draft",
      icon: "pencil",
      color: "green",
      source_file: "app/agents/writing_agent.rb",
      template_files: [
        "app/views/agents/writing/instructions.md.erb",
        "app/views/agents/writing/draft.md.erb"
      ]
    },
    "report_builder" => {
      name: "Report Builder",
      description: "Orchestrates research and writing to produce cited reports",
      class_name: "ReportBuilderAgent",
      action: "build_report",
      icon: "document",
      color: "purple",
      source_file: "app/agents/report_builder_agent.rb",
      template_files: [
        "app/views/agents/report_builder/instructions.md.erb",
        "app/views/agents/report_builder/build_report.md.erb"
      ]
    }
  }.freeze

  def index
    session = find_or_create_session

    agents_data = AGENTS.transform_values do |agent|
      agent.merge(
        source_code: read_source(agent[:source_file]),
        template_sources: agent[:template_files].map { |f| { path: f, content: read_source(f) } }
      )
    end

    render inertia: "Playground", props: {
      agents: agents_data,
      default_agent: "research",
      session_id: session.id,
      messages: session.playground_messages.map(&:to_h),
      shared_context: session.shared_context
    }
  end

  def execute
    session = find_or_create_session
    agent_key = params[:agent]
    message = params[:message]
    agent_config = AGENTS[agent_key]

    unless agent_config
      return render json: { error: "Unknown agent: #{agent_key}" }, status: :unprocessable_entity
    end

    # Persist user message
    session.add_message(role: "user", content: message, agent_name: agent_key)

    agent_class = agent_config[:class_name].constantize
    action = agent_config[:action]

    # Build agent params with session for shared context access
    agent_params = { message: message, session: session }

    begin
      # Optionally override provider if user supplies an API key
      if session.metadata["api_key"].present? && session.metadata["provider"].present?
        provider = session.metadata["provider"].to_sym
        model = session.metadata["model"] || default_model_for(provider)
        api_key = session.metadata["api_key"]

        dynamic_agent = Class.new(agent_class) do
          generate_with provider, model: model, api_key: api_key
        end
        generation = dynamic_agent.with(agent_params).send(action)
      else
        generation = agent_class.with(agent_params).send(action)
      end

      response = generation.generate_now

      # Extract response content
      response_content = extract_content(response)

      # Persist assistant message
      assistant_msg = session.add_message(
        role: "assistant",
        content: response_content,
        agent_name: agent_key,
        metadata: {
          model: response.try(:model) || "mock",
          usage: extract_usage(response)
        }
      )

      # Update shared context based on agent type
      update_shared_context(session, agent_key, message, response_content)

      render json: {
        message: assistant_msg.to_h,
        shared_context: session.reload.shared_context,
        agent: agent_key
      }
    rescue => e
      Rails.logger.error "[Playground] Agent execution error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"

      error_msg = session.add_message(
        role: "system",
        content: "Error: #{e.message}",
        agent_name: agent_key,
        metadata: { error: true }
      )

      render json: { error: e.message, message: error_msg.to_h }, status: :internal_server_error
    end
  end

  def reset
    session = find_session
    if session
      session.playground_messages.destroy_all
      session.update!(shared_context: {}, status: "active")
    end

    render json: { success: true }
  end

  def context
    session = find_session
    if session
      render json: { shared_context: session.shared_context }
    else
      render json: { shared_context: {} }
    end
  end

  def update_settings
    session = find_or_create_session
    settings = params.permit(:api_key, :provider, :model)

    session.update!(
      metadata: session.metadata.merge(settings.to_h)
    )

    render json: { success: true, metadata: session.metadata }
  end

  private

  def find_or_create_session
    token = cookies[:playground_session_token]

    if token.present?
      session = PlaygroundSession.find_by(session_token: token)
      return session if session
    end

    # Create new session
    token = SecureRandom.urlsafe_base64(32)
    cookies[:playground_session_token] = {
      value: token,
      expires: 7.days.from_now,
      httponly: true
    }

    PlaygroundSession.create!(session_token: token, status: "active")
  end

  def find_session
    token = cookies[:playground_session_token]
    PlaygroundSession.find_by(session_token: token) if token.present?
  end

  def read_source(relative_path)
    full_path = Rails.root.join(relative_path)
    File.exist?(full_path) ? File.read(full_path) : "# File not found: #{relative_path}"
  end

  def extract_content(response)
    msg = response.try(:message)
    return "" unless msg

    content = msg.respond_to?(:content) ? msg.content : msg.to_s

    case content
    when String
      content
    when Array
      content.select { |b| b.is_a?(Hash) && b[:type] == "text" }.map { |b| b[:text] }.join
    else
      content.to_s
    end
  end

  def extract_usage(response)
    usage = response.try(:usage)
    return {} unless usage

    {
      input_tokens: usage.try(:input_tokens) || usage.try(:[], :input_tokens),
      output_tokens: usage.try(:output_tokens) || usage.try(:[], :output_tokens)
    }.compact
  end

  def update_shared_context(session, agent_key, user_message, response_content)
    case agent_key
    when "research"
      # Store research findings in shared context
      existing = session.research_findings
      findings = existing.merge(
        "topic" => user_message,
        "summary" => response_content.truncate(500),
        "sources" => (existing["sources"] || []) + simulated_sources_for(user_message),
        "updated_at" => Time.current.iso8601
      )
      session.update_shared_context("research", findings)
    when "writing"
      # Store draft in shared context
      session.update_shared_context("draft", response_content)
    when "report_builder"
      # Store final report
      session.update_shared_context("report", response_content)
    end
  end

  def simulated_sources_for(topic)
    [
      {
        "title" => "Understanding #{topic}",
        "authors" => ["Smith, A.", "Johnson, B."],
        "year" => 2024,
        "journal" => "Journal of Advanced Research",
        "url" => "https://doi.org/10.1234/#{topic.parameterize}"
      },
      {
        "title" => "#{topic}: A Systematic Review",
        "authors" => ["Williams, C."],
        "year" => 2025,
        "journal" => "Annual Review of Technology",
        "url" => "https://doi.org/10.5678/#{topic.parameterize}"
      }
    ]
  end

  def default_model_for(provider)
    case provider.to_s
    when "openai" then "gpt-4o-mini"
    when "anthropic" then "claude-sonnet-4-5-20250929"
    when "ollama" then "llama3.2"
    else "gpt-4o-mini"
    end
  end
end
