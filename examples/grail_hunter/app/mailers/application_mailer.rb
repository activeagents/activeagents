class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM", "Grail Hunter <hunts@example.com>")
  layout "mailer"
end
