# Drafts a reply to a ticket, grounded in the knowledge base articles that
# match it (retrieval folded into the instructions). Conversations persist
# through solid_agent: each ticket gets an AgentContext, and every draft is
# recorded as an AgentGeneration carrying the telemetry trace_id — open the
# same trace on the monitoring dashboard to see the generation that
# produced it.
class SupportReplyAgent < ApplicationAgent
  include SolidAgent::HasContext

  has_context

  def draft
    new_trace!
    ticket = params[:ticket]

    load_context(contextable: ticket)

    articles = KnowledgeBase.relevant_to(ticket)
    kb_section =
      if articles.any?
        formatted = articles.map { |a| "### #{a['title']}\n#{a['body']}" }.join("\n\n")
        "Ground your answer in these knowledge base articles when relevant:\n\n#{formatted}"
      else
        "No knowledge base articles matched; answer from general product knowledge and offer to escalate."
      end

    prompt(
      instructions: <<~INSTRUCTIONS,
        You draft support replies for a small SaaS product. Be concise,
        warm, and concrete. Sign off as "The Support Team". Do not invent
        features or prices.

        #{kb_section}
      INSTRUCTIONS
      message: "Draft a reply to this ticket.\n\nSubject: #{ticket.subject}\n\n#{ticket.body}"
    )
  end
end
