class ApplicationMailer < ActionMailer::Base
  default from: "ActiveAgent <hello@activeagents.ai>"
  layout "mailer"
end
