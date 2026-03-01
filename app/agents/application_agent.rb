# frozen_string_literal: true

class ApplicationAgent < ActiveAgent::Base
  self.generate_later_queue_name = :sandboxes

  # Default system prompt for sandbox demos
  def default_instructions
    <<~PROMPT
      You are a helpful AI assistant. Answer the user's question or complete their task concisely and accurately.

      If the task involves browser automation, describe what actions you would take step by step.
    PROMPT
  end
end
