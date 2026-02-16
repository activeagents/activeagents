# frozen_string_literal: true

# These example agents serve as the source of truth for landing page flip cards.
# Each example is based on official Active Agent documentation.
# DO NOT modify without updating the corresponding flip card in:
#   app/views/pages/sections/_features.html.erb

module FlipCardExamples
  # ==========================================================================
  # 1. AGENTS ARE CONTROLLERS
  # Docs: https://docs.activeagents.ai/agents
  # ==========================================================================
  class TranslationAgent < ApplicationAgent
    generate_with :openai, model: "gpt-4o"

    def translate
      prompt message: "Translate '#{params[:text]}' to #{params[:target_lang]}"
    end
  end

  # Usage:
  #   response = TranslationAgent.with(text: "Hello", target_lang: "es").translate.generate_now

  # ==========================================================================
  # 2. ACTION PROMPT
  # Docs: https://docs.activeagents.ai/actions
  # ==========================================================================
  class SummaryAgent < ApplicationAgent
    def summarize
      prompt(
        instructions: "Summarize in 2-3 sentences",
        message: params[:text],
        temperature: 0.3
      )
    end
  end

  # Usage:
  #   SummaryAgent.with(text: content).summarize.generate_now

  # ==========================================================================
  # 3. ANY LLM - Provider Configuration
  # Docs: https://docs.activeagents.ai/providers
  # ==========================================================================
  class OpenAIAgent < ApplicationAgent
    generate_with :open_ai, model: "gpt-4o"

    def ask
      prompt message: params[:message]
    end
  end

  class AnthropicAgent < ApplicationAgent
    generate_with :anthropic, model: "claude-sonnet-4-5-20250929"

    def ask
      prompt message: params[:message]
    end
  end

  class OllamaAgent < ApplicationAgent
    generate_with :ollama, model: "llama3"

    def ask
      prompt message: params[:message]
    end
  end

  # ==========================================================================
  # 4. STREAMING
  # Docs: https://docs.activeagents.ai/agents/streaming
  # ==========================================================================
  class StreamingAgent < ApplicationAgent
    generate_with :openai, model: "gpt-4o", stream: true

    on_stream :handle_chunk

    def chat
      prompt message: params[:message]
    end

    private

    def handle_chunk(chunk)
      print chunk.delta if chunk.delta
    end
  end

  # ==========================================================================
  # 5. STRUCTURED OUTPUT
  # Docs: https://docs.activeagents.ai/actions/structured_output
  # ==========================================================================
  class DataExtractionAgent < ApplicationAgent
    generate_with :openai, model: "gpt-4o"

    def parse_resume
      prompt(
        message: "Extract resume data: #{params[:file_data]}",
        response_format: :json_schema
      )
    end
  end

  # Schema file: app/views/agents/data_extraction/parse_resume/schema.json

  # ==========================================================================
  # 6. TOOL CALLING
  # Docs: https://docs.activeagents.ai/actions/tools
  # ==========================================================================
  class WeatherAgent < ApplicationAgent
    generate_with :openai, model: "gpt-4o"

    def weather_update
      prompt(
        message: params[:query],
        tools: [{
          name: "get_weather",
          description: "Get current weather for a location",
          parameters: {
            type: "object",
            properties: {
              location: { type: "string", description: "City and state" }
            },
            required: ["location"]
          }
        }]
      )
    end

    def get_weather(location:)
      # AI calls this method automatically
      { location: location, temperature: "72F", conditions: "sunny" }
    end
  end

  # ==========================================================================
  # 7. RESILIENT BY DEFAULT
  # Docs: https://docs.activeagents.ai/agents/retries
  # ==========================================================================
  class ReliableAgent < ApplicationAgent
    generate_with :openai,
      model: "gpt-4o",
      retries: 3,
      backoff: :exponential

    on_error :handle_failure

    def ask
      prompt message: params[:message]
    end

    private

    def handle_failure(error)
      Rails.logger.error("Agent failed: #{error.message}")
    end
  end

  # ==========================================================================
  # 8. MCP SUPPORT
  # Docs: https://docs.activeagents.ai/agents/mcp
  # ==========================================================================
  class MCPAgent < ApplicationAgent
    generate_with :anthropic,
      model: "claude-sonnet-4-5-20250929",
      mcp_servers: {
        filesystem: {
          command: "npx",
          args: ["-y", "@anthropic/mcp-fs"]
        },
        github: { url: "https://mcp.github.com" }
      }

    def assist
      prompt message: params[:message]
    end
  end

  # ==========================================================================
  # 9. BACKGROUND JOBS (Asynchronous Generation)
  # Docs: https://docs.activeagents.ai/agents/generation#asynchronous
  # ==========================================================================
  class AsyncAgent < ApplicationAgent
    self.generate_later_queue_name = :ai_tasks

    def analyze
      prompt message: params[:data]
    end
  end

  # Usage:
  #   AsyncAgent.with(data: content).analyze.generate_later
  #   AsyncAgent.with(data: content).analyze.generate_later(queue: :reports, wait: 5.minutes)
end
