module TeammateHelpers
  def create_seat_plans
    [
      Plan.create!(name: "Free", slug: "free", price_cents: 0, included_seats: 1),
      Plan.create!(name: "Pro", slug: "pro", price_cents: 9900, included_seats: 3),
      Plan.create!(name: "Enterprise", slug: "enterprise", price_cents: 200_000, included_seats: -1)
    ]
  end

  # A workspace on +plan+ through an app-managed subscription, which confers
  # the plan without billing.
  def team_account(owner: create_user, plan: "pro")
    account = create_account(owner: owner)
    account.set_payment_processor(:fake_processor, allow_fake: true)
    account.payment_processor.subscribe(plan: plan)
    account.reload
  end

  def add_member(account, user: create_user, role: "member")
    account.account_memberships.create!(user: user, role: role)
    user
  end

  # Invites +email+ as +actor+, runs the delivery and returns the invitation
  # and the token from the email.
  def send_teammate_invitation(account:, actor:, email:, role: "member")
    invitation = WorkspaceMembers.new(account, actor: actor).invite!(email_address: email, role: role)
    [ invitation, deliver_teammate_invitation(invitation) ]
  end

  def deliver_teammate_invitation(invitation)
    WorkspaceInvitationDeliveryJob.perform_now(invitation.id, invitation.reload.delivery_version)
    mail = ActionMailer::Base.deliveries.last
    url = URI.extract(mail.body.decoded).find { |value| value.include?("workspace_invitation?") }
    URI.decode_www_form(URI(url).query).to_h.fetch("token")
  end
end
