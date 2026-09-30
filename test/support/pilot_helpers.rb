module PilotHelpers
  def create_pilot_plans
    Plan.create!(name: "Free", slug: "free", price_cents: 0)
    Plan.create!(name: "Pro", slug: "pro", price_cents: 9900, stripe_monthly_price_id: "price_pro")
  end

  def prepare_invitation(admin:, email: "pilot@example.com", **attributes)
    WorkspaceInvitation.create!(invited_by: admin, email_address: email, workspace_name: "Pilot workspace",
      reason: "Monthly retainer pilot", review_on: 1.month.from_now.to_date, **attributes)
  end

  def deliver_invitation(invitation, admin: invitation.invited_by)
    invitation.queue_delivery!(actor: admin)
    WorkspaceInvitationDeliveryJob.perform_now(invitation.id, invitation.reload.delivery_version)
    mail = ActionMailer::Base.deliveries.last
    url = URI.extract(mail.body.decoded).find { |value| value.include?("workspace_invitation?") }
    URI.decode_www_form(URI(url).query).to_h.fetch("token")
  end

  def create_paid_subscription(account, status: "active", trial_ends_at: nil, price: "price_pro")
    customer = account.pay_customers.create!(processor: "stripe", processor_id: "cus_#{SecureRandom.hex(6)}")
    customer.subscriptions.create!(name: "default", processor_id: "sub_#{SecureRandom.hex(6)}",
      processor_plan: price, status: status, trial_ends_at: trial_ends_at)
  end

  # No external requests in the checkout/mail failure tests. Restore the
  # original method even when an assertion or the stub raises.
  def with_method(object, method, replacement)
    original = object.method(method)
    object.define_singleton_method(method, replacement)
    yield
  ensure
    object.define_singleton_method(method, original)
  end
end
