class Ticket < ApplicationRecord
  has_many :replies, dependent: :destroy
  has_many :agent_contexts, as: :contextable, dependent: :destroy

  validates :subject, :body, :customer_email, presence: true

  enum :status, { open: 0, waiting: 1, closed: 2 }, default: :open

  scope :recent, -> { order(created_at: :desc) }

  # Runs TriageAgent and applies its classification. The response is
  # requested as JSON but parsed defensively: real providers return the
  # object, the mock provider returns pig-latin, in which case the ticket
  # keeps neutral defaults — the trace still shows the full generation.
  def triage!
    response = TriageAgent.with(ticket: self).triage.generate_now
    apply_triage!(response.message&.content)
  end

  def draft_reply!
    response = SupportReplyAgent.with(ticket: self).draft.generate_now
    replies.create!(
      author: "AI draft",
      body: response.message&.content.presence || "(no draft produced)",
      ai_generated: true,
      draft: true
    )
  end

  def summarize!
    response = SummarizeAgent.with(ticket: self).summarize.generate_now
    update!(ai_summary: response.message&.content)
  end

  def apply_triage!(content)
    data = extract_json(content)

    update!(
      category: TriageAgent::CATEGORIES.include?(data["category"]) ? data["category"] : "other",
      priority: TriageAgent::PRIORITIES.include?(data["priority"]) ? data["priority"] : "normal",
      sentiment: TriageAgent::SENTIMENTS.include?(data["sentiment"]) ? data["sentiment"] : "neutral",
      triage_summary: data["summary"].presence || body.truncate(120),
      triaged_at: Time.current
    )
  end

  private

  # Pulls the first JSON object out of a model response, tolerating code
  # fences and surrounding prose. Returns {} when there is none.
  def extract_json(content)
    return {} if content.blank?

    json = content[/\{.*\}/m]
    return {} unless json

    parsed = JSON.parse(json)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end
end
