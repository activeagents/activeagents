# frozen_string_literal: true

class EmailVerificationChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_user

    stream_from "email_verification_#{current_user.id}"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
