# Sends the agent's answer back out on the customer's thread.
#
# The headers are the whole job. Get them wrong and every reply starts a new
# conversation in the customer's client, their answer comes back unthreaded,
# and a second autoresponder on their side will happily talk to this one
# forever.
class SupportMailer < ApplicationMailer
  def answer
    @ticket = params[:ticket]
    @reply = params[:reply]

    # Ours to set, and set before delivery: Reply assigns the id on create so
    # the customer's answer — which will quote it in In-Reply-To — can be
    # matched back to this ticket.
    headers["Message-ID"] = bracket(@reply.message_id)

    # What this answers, and the thread it belongs to. The new id is dropped
    # from References: a message does not reference itself.
    if (parent = @ticket.last_inbound_message_id).present?
      headers["In-Reply-To"] = bracket(parent)
    end

    references = @ticket.reference_message_ids - [ @reply.message_id ]
    headers["References"] = references.map { |id| bracket(id) }.join(" ") if references.any?

    # RFC 3834. This is a generated reply, and saying so is what keeps the
    # vacation responder on the other side from answering it — the same
    # courtesy LoopGuard expects from everyone else.
    headers["Auto-Submitted"] = "auto-replied"

    mail(
      to: @ticket.customer_email,
      from: @ticket.support_address,
      # Where the answer should come back to: the support address +tagged
      # with this ticket's token.
      reply_to: @ticket.reply_address,
      subject: "Re: #{@ticket.subject}"
    )
  end

  private

  def bracket(message_id)
    id = message_id.to_s.delete("<>")
    id.present? ? "<#{id}>" : nil
  end
end
