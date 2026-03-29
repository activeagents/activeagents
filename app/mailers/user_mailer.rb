# frozen_string_literal: true

class UserMailer < ApplicationMailer
  # Uses default from address from ApplicationMailer/config

  def email_verification(user)
    @user = user
    @verification_url = verify_email_url(token: user.email_verification_token)

    mail(
      to: user.email_address,
      subject: "Verify your email to get started with Active Agent"
    )
  end

  def welcome(user)
    @user = user
    @dashboard_url = dashboard_url

    mail(
      to: user.email_address,
      subject: "Welcome to Active Agent - Let's build your first agent!"
    )
  end
end
