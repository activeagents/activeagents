# Produces a short running summary of a ticket and its replies — the kind
# of glanceable context an on-call support person wants before opening the
# full thread.
class SummarizeAgent < ApplicationAgent
  def summarize
    new_trace!
    ticket = params[:ticket]

    thread = [ "Customer (#{ticket.customer_email}): #{ticket.body}" ]
    ticket.replies.order(:created_at).each do |reply|
      thread << "#{reply.author}: #{reply.body}"
    end

    prompt(
      instructions: "Summarize this support thread in at most 3 short sentences: " \
                    "what the customer needs, what has happened so far, and what should happen next.",
      message: "Subject: #{ticket.subject}\n\n#{thread.join("\n\n---\n\n")}"
    )
  end
end
