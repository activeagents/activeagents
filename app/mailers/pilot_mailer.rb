class PilotMailer < ApplicationMailer
  default from: -> { ENV.fetch("MAILER_FROM_ADDRESS", "ActiveAgents <hello@activeagents.ai>") }

  def invitation(invitation, token)
    @invitation = invitation
    @accept_url = workspace_invitation_url(token: token)
    mail(to: invitation.email_address, subject: "Your #{invitation.workspace_name} Pro workspace invitation")
  end

  def access_notice(event)
    @event = event
    @account = event.pro_access_grant.account
    mail(to: @account.owner.email_address, subject: "#{@account.name}: Pro pilot access #{event.action}")
  end
end
