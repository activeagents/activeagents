class InvestorMailer < ApplicationMailer
  def portal_invite(investor)
    @investor = investor
    @account = investor.account
    @portal_url = investor_portal_authenticate_url(token: investor.access_token)

    mail(
      subject: "You're invited to the #{@account.name} Investor Portal",
      to: investor.email
    )
  end

  def document_shared(investor, document)
    @investor = investor
    @document = document
    @account = investor.account
    @portal_url = investor_portal_dashboard_url

    mail(
      subject: "New document shared: #{document.name}",
      to: investor.email
    )
  end

  def safe_status_update(investor, safe_agreement, previous_status)
    @investor = investor
    @safe = safe_agreement
    @account = investor.account
    @previous_status = previous_status
    @portal_url = investor_portal_dashboard_url

    subject = case safe_agreement.status
    when "sent" then "Your SAFE agreement is ready for signature"
    when "signed" then "Your SAFE agreement has been signed"
    when "converted" then "Your SAFE has converted to equity"
    else "SAFE agreement status update"
    end

    mail(subject: subject, to: investor.email)
  end

  def portal_access_expiring(investor)
    @investor = investor
    @account = investor.account
    @expires_at = investor.access_token_expires_at
    @days_remaining = ((@expires_at - Time.current) / 1.day).ceil

    mail(
      subject: "Your investor portal access expires soon",
      to: investor.email
    )
  end
end
