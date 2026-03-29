class ApplicationMailer < ActionMailer::Base
  # From address configured via MAILER_FROM_ADDRESS env var or config/environments
  layout "mailer"
end
