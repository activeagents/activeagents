class TicketsController < ApplicationController
  before_action :set_ticket, only: [ :show, :triage, :draft_reply, :summarize ]

  def index
    @tickets = Ticket.recent
    @ticket = Ticket.new
  end

  def show
  end

  def create
    ticket = Ticket.new(ticket_params)
    if ticket.save
      redirect_to ticket, notice: "Ticket created."
    else
      redirect_to tickets_path, alert: ticket.errors.full_messages.to_sentence
    end
  end

  # Each action below runs an agent synchronously — deliberate for a demo,
  # so the trace exists by the time the page reloads.

  def triage
    @ticket.triage!
    redirect_to @ticket, notice: "Ticket triaged."
  rescue => e
    redirect_to @ticket, alert: "Triage failed: #{e.message}"
  end

  def draft_reply
    @ticket.draft_reply!
    redirect_to @ticket, notice: "Reply drafted."
  rescue => e
    redirect_to @ticket, alert: "Draft failed: #{e.message}"
  end

  def summarize
    @ticket.summarize!
    redirect_to @ticket, notice: "Thread summarized."
  rescue => e
    redirect_to @ticket, alert: "Summarize failed: #{e.message}"
  end

  private

  def set_ticket
    @ticket = Ticket.find(params[:id])
  end

  def ticket_params
    params.require(:ticket).permit(:subject, :body, :customer_email)
  end
end
