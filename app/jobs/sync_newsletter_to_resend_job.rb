class SyncNewsletterToResendJob < ApplicationJob
  self.enqueue_after_transaction_commit = true
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(subscription_id)
    subscription = NewsletterSubscription.find(subscription_id)
    subscription.with_lock do
      return unless subscription.confirmed_at? && !subscription.synced_at?
      # Newsletter consent never adds a contact to the dashboard-user audience.
      audience = ENV.fetch("RESEND_NEWSLETTER_AUDIENCE_ID")
      Resend.api_key = ENV.fetch("RESEND_API_KEY")
      response = Resend::Contacts.create(audience_id: audience,
        email: subscription.email_address, unsubscribed: false)
      raise "Newsletter contact sync failed" unless response[:id].present?
      subscription.update!(synced_at: Time.current)
    end
  end
end
