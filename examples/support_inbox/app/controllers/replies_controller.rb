class RepliesController < ApplicationController
  before_action :set_ticket

  def create
    reply = @ticket.replies.create!(reply_params.merge(author: "Support"))
    reply.send!
    redirect_to @ticket, notice: "Reply sent."
  end

  def send_reply
    reply = @ticket.replies.drafts.find(params[:id])
    reply.send!
    redirect_to @ticket, notice: "Draft sent."
  end

  private

  def set_ticket
    @ticket = Ticket.find(params[:ticket_id])
  end

  def reply_params
    params.require(:reply).permit(:body)
  end
end
