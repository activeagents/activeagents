# frozen_string_literal: true

# A consulting/services inquiry captured from the landing page. Distinct from
# User: a lead has not signed up for the platform, they want to talk to us
# about workshops, advisory, or development work.
class Lead < ApplicationRecord
  SERVICE_TYPES = %w[workshop advisory development enterprise general].freeze

  normalizes :email, with: ->(e) { e.strip.downcase }
  normalizes :name, :company, with: ->(v) { v.strip }

  validates :name, presence: true, length: { maximum: 255 }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :service_type, presence: true, inclusion: { in: SERVICE_TYPES }
  validates :message, length: { maximum: 5_000 }
  validates :company, length: { maximum: 255 }

  scope :recent, -> { order(created_at: :desc) }
  scope :for_service, ->(type) { where(service_type: type) }

  def display_service
    service_type.titleize
  end
end
