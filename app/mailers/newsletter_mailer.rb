class NewsletterMailer < ApplicationMailer
  default from: -> { ENV.fetch("MAILER_FROM_ADDRESS", "ActiveAgents <hello@activeagents.ai>") }

  def confirmation(subscription)
    @confirmation_url = newsletter_subscription_url(token: subscription.generate_token_for(:confirmation))
    mail(to: subscription.email_address, subject: "Confirm your ActiveAgents newsletter subscription")
  end
end
