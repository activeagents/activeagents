class TeammateMailer < ApplicationMailer
  default from: -> { ENV.fetch("MAILER_FROM_ADDRESS", "ActiveAgents <hello@activeagents.ai>") }

  def invitation(invitation, token)
    @invitation = invitation
    @accept_url = workspace_invitation_url(token: token)
    mail(to: invitation.email_address, subject: "Join #{invitation.account.name} on ActiveAgents")
  end
end
