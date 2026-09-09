# frozen_string_literal: true

class LeadMailer < ApplicationMailer
  # Routes an inquiry to the address that matches the service the lead asked
  # about, so workshop/advisory/dev mail keeps landing where it always has.
  SERVICE_INBOXES = {
    "workshop"   => "workshops@activeagents.ai",
    "advisory"   => "consulting@activeagents.ai",
    "development" => "dev@activeagents.ai",
    "enterprise" => "sales@activeagents.ai",
    "general"    => "hello@activeagents.ai"
  }.freeze

  # Internal notification: tells us a lead came in.
  def notification(lead)
    @lead = lead
    inbox = SERVICE_INBOXES.fetch(lead.service_type, "hello@activeagents.ai")

    mail(
      to: ENV.fetch("LEADS_NOTIFICATION_ADDRESS", inbox),
      reply_to: lead.email,
      subject: "New #{lead.display_service} inquiry from #{lead.name}"
    )
  end

  # Confirmation to the lead so they know we received it.
  def confirmation(lead)
    @lead = lead

    mail(
      to: lead.email,
      subject: "Thanks for reaching out to Active Agent"
    )
  end
end
