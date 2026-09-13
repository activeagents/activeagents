# Drafts a reply to a ticket, grounded in the knowledge base articles that
# match it (retrieval folded into the instructions). Conversations persist
# through solid_agent: each ticket gets an AgentContext, and every draft is
# recorded as an AgentGeneration carrying the telemetry trace_id — open the
# same trace on the monitoring dashboard to see the generation that
# produced it.
#
# Two actions, one conversation:
#
#   draft   — what the Draft reply button in the inbox runs
#   respond — what SupportMailbox runs when an email arrives, continuing the
#             stored conversation instead of re-reading the ticket each time
class SupportReplyAgent < ApplicationAgent
  include SolidAgent::HasContext

  has_context

  def draft
    new_trace!
    ticket = params[:ticket]

    load_context(contextable: ticket)

    prompt(
      instructions: instructions_for(ticket),
      message: "Draft a reply to this ticket.\n\nSubject: #{ticket.subject}\n\n#{ticket.body}"
    )
  end

  # Answers the customer's latest email. The history comes from the stored
  # context rather than from the email's quoted thread: the customer's client
  # decides what to quote, and half of them quote nothing.
  def respond
    new_trace!
    ticket = params[:ticket]
    message = params[:message].presence || ticket.body

    load_context(contextable: ticket)

    prompt(
      instructions: [ instructions_for(ticket), EMAIL_INSTRUCTIONS ].join("\n\n"),
      messages: context_messages + [ { role: "user", content: message } ]
    )
  end

  private

  # This answer is an email, and email has rules a chat window does not: no
  # markdown, no "as I mentioned above", and a person on the other end who
  # cannot click a button to escalate.
  EMAIL_INSTRUCTIONS = <<~INSTRUCTIONS.freeze
    You are answering by email. Write plain text — no markdown, no headings,
    no bullet characters other than "-". Keep it under 150 words. Open by
    answering the question, not by restating it.

    Anything that needs a decision only a human can make — refunds, account
    changes, anything involving money or data loss — is not yours to promise.
    Say that a support engineer will follow up, and say when.
  INSTRUCTIONS

  def instructions_for(ticket)
    <<~INSTRUCTIONS
      You draft support replies for a small SaaS product. Be concise,
      warm, and concrete. Sign off as "The Support Team". Do not invent
      features or prices.

      #{knowledge_section(ticket)}
    INSTRUCTIONS
  end

  def knowledge_section(ticket)
    articles = KnowledgeBase.relevant_to(ticket)
    return "No knowledge base articles matched; answer from general product knowledge and offer to escalate." if articles.empty?

    formatted = articles.map { |article| "### #{article["title"]}\n#{article["body"]}" }.join("\n\n")
    "Ground your answer in these knowledge base articles when relevant:\n\n#{formatted}"
  end
end
