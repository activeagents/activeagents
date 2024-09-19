class MessagesController < ApplicationController
  include ActionView::RecordIdentifier

  def create    
    @chat = Chat.find(params[:chat_id])
    @message = @chat.messages.create(message_params.merge(role: 'user'))


    SupportAgent.prompt(
      content: @message.content,
      chat_id: @chat.id,
      user_id: 'current_user.id'
    ).generate_later

    respond_to do |format|
      format.turbo_stream
    end
  end

  private

  def message_params
    params.require(:message).permit(:content)
  end
end