class NewsletterSubscription < ApplicationRecord
  normalizes :email_address, with: ->(email) { email.strip.downcase }
  validates :email_address, presence: true, uniqueness: true, length: { maximum: 254 }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :consented_at, presence: true
  generates_token_for :confirmation, expires_in: 2.days do
    [ consented_at, confirmed_at ]
  end

  def self.subscribe!(email)
    subscription = find_or_initialize_by(email_address: email)
    return subscription if subscription.persisted? && (subscription.confirmed_at? || subscription.consented_at > 1.hour.ago)
    subscription.update!(consented_at: Time.current)
    NewsletterMailer.confirmation(subscription).deliver_later
    subscription
  rescue ActiveRecord::RecordNotUnique
    find_by!(email_address: email)
  end
end
