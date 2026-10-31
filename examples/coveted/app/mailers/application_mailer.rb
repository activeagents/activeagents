class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM", "Coveted <hello@example.com>")
  layout "mailer"
end
