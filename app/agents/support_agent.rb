class SupportAgent < ActiveAgent::Base
  generate_with :openai, model: 'gpt-3.5-turbo', instructions: :instructions

  before_action do
    @chat = Chat.find(params[:chat_id])
  end

  private

  def after_generate
    broadcast_message
  end

  def broadcast_message
    broadcast_append_later_to(
      "#{dom_id(@chat)}_messages",
      target:  "#{dom_id(@chat)}_messages",
      partial: 'support_agent/message',
      locals: { message: message }
    )
  end
end
