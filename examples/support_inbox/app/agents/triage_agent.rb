# Classifies an incoming ticket: category, priority, sentiment, and a
# one-line summary. The response is requested as JSON and parsed
# defensively in Ticket#apply_triage! — with the mock provider the reply
# isn't JSON, and the ticket falls back to neutral defaults, which keeps
# the demo working without API keys.
class TriageAgent < ApplicationAgent
  CATEGORIES = %w[billing bug how-to feature-request account other].freeze
  PRIORITIES = %w[low normal high urgent].freeze
  SENTIMENTS = %w[positive neutral negative].freeze

  def triage
    new_trace!
    ticket = params[:ticket]

    prompt(
      instructions: <<~INSTRUCTIONS,
        You triage customer support tickets for a small SaaS product.
        Respond with ONLY a JSON object, no prose, of the shape:
        {"category": <one of: #{CATEGORIES.join(', ')}>,
         "priority": <one of: #{PRIORITIES.join(', ')}>,
         "sentiment": <one of: #{SENTIMENTS.join(', ')}>,
         "summary": <one sentence, max 20 words>}
      INSTRUCTIONS
      message: "Subject: #{ticket.subject}\n\nFrom: #{ticket.customer_email}\n\n#{ticket.body}"
    )
  end
end
