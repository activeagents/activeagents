class Ticket < ApplicationRecord
  has_many :replies, dependent: :destroy
  has_many :agent_contexts, as: :contextable, dependent: :destroy

  validates :subject, :body, :customer_email, presence: true

  enum :status, { open: 0, waiting: 1, closed: 2 }, default: :open

  # The +tag that threads this conversation: replies come back to
  # support+<mail_token>@example.com, which is how a customer's answer finds
  # its ticket even when their client drops every header it did not write.
  # Not has_secure_token: that generates mixed-case base58, and addresses do
  # not survive a round trip through the mail system with their case intact.
  before_create :assign_mail_token

  scope :recent, -> { order(created_at: :desc) }
  scope :by_email, -> { where(channel: "email") }

  def email?
    channel == "email"
  end

  # ---- Mail threading ------------------------------------------------------

  # The address replies are sent from — whichever support address the customer
  # wrote to, falling back to the configured default.
  def support_address
    self[:support_address].presence || ActionMailAgent.default_from
  end

  # Where the customer's reply should go: the support address, +tagged with
  # this ticket's token.
  def reply_address
    ActionMailAgent::Addressing.tagged(support_address, mail_token)
  end

  # The message the next reply answers, for In-Reply-To.
  def last_inbound_message_id
    replies.where(inbound: true).order(:created_at).last&.message_id.presence || mail_message_id
  end

  # The thread so far, for References. Capped because the header is one line
  # and a long-running conversation would otherwise grow it without bound;
  # RFC 5322 §3.6.4 allows trimming the middle, and the ends are what clients
  # thread on.
  def reference_message_ids(limit: 10)
    ids = [ mail_message_id, *replies.order(:created_at).pluck(:message_id) ].compact_blank.uniq
    return ids if ids.size <= limit

    [ ids.first, *ids.last(limit - 1) ]
  end

  # ---- Agent guardrails ----------------------------------------------------

  def handed_off?
    handed_off_at.present?
  end

  # Takes the conversation away from the agent and gives it to a human. The
  # loop guard reads this, so nothing else has to remember to check.
  def hand_off!(reason:)
    return if handed_off?

    update!(handed_off_at: Time.current, handoff_reason: reason, status: :open)
    ActionMailAgent.notify_handoff(self, reason)
  end

  # How many answers the agent has sent on this ticket inside the window —
  # counted from the records rather than kept in a column, so it cannot drift
  # away from what actually happened. The loop guard reads it.
  def agent_replies_within(window)
    replies.outbound.where(ai_generated: true, created_at: window.ago..).count
  end

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

  def assign_mail_token
    self.mail_token ||= ActionMailAgent::Addressing.generate_token
  end

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
