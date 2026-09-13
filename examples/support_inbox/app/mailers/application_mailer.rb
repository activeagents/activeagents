class ApplicationMailer < ActionMailer::Base
  # Evaluated per message: the support address is configured at boot (and
  # overridable with SUPPORT_ADDRESS), not baked in at class-load time.
  default from: -> { ActionMailAgent.default_from }
  layout "mailer"
end
