class ApplicationMailer < ActionMailer::Base
  # From address configured via MAILER_FROM_ADDRESS env var or config/environments
  layout "mailer"

  # Rails' debug mail logging includes the complete encoded body. Preserve
  # delivery instrumentation without exposing verification/invitation tokens.
  def self.set_payload_for_mail(payload, mail)
    super
    payload[:mail] = "[Email body redacted]"
  end
  private_class_method :set_payload_for_mail
end
