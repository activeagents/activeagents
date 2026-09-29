require "test_helper"
require_relative "../support/pilot_helpers"

class PublicSignupTest < ActionDispatch::IntegrationTest
  include PilotHelpers
  include ActiveJob::TestHelper

  setup { create_pilot_plans }

  test "uninvited public signup verifies and reaches paid checkout without granting Pro from the redirect" do
    get "/registration/new"
    assert_response :success
    assert_difference [ "User.count", "Account.count", "AccountMembership.count" ], 1 do
      post "/registration", params: { user: { email_address: "public@example.com", password: "password123", password_confirmation: "password123" } }
    end
    assert_redirected_to "/pending_verification"
    user = User.find_by!(email_address: "public@example.com")
    assert_not user.email_verified?
    assert_equal "free", user.primary_account.current_plan.slug
    assert_equal 0, WorkspaceInvitation.count
    get "/verify_email", params: { token: user.email_verification_token }
    assert_redirected_to "/complete_profile"

    calls = []
    checkout = ->(**arguments) do
      calls << arguments
      Struct.new(:url, :expires_at).new("https://checkout.stripe.com/c/pay_test", 1.hour.from_now.to_i)
    end
    # Preexisting Stripe customer avoids any customer-creation API request.
    user.primary_account.set_payment_processor(:stripe).update!(processor_id: "cus_public")
    with_method(Stripe::Checkout::Session, :create, ->(*arguments) { checkout.call(**arguments.first) }) do
      patch "/complete_profile", params: { user: { first_name: "Public" }, plan_slug: "pro" }
      assert_redirected_to "https://checkout.stripe.com/c/pay_test"
      post "/subscriptions/checkout", params: { plan_id: Plan.find_by!(slug: "pro").id }
      assert_redirected_to "https://checkout.stripe.com/c/pay_test"
    end
    assert_equal 1, calls.length
    assert_equal "subscription", calls.first[:mode]
    assert_equal "price_pro", calls.first[:line_items].first[:price]
    assert_equal "free", user.primary_account.reload.current_plan.slug
    assert_equal 0, ProAccessGrant.count
    get "/subscriptions", params: { checkout_session_id: "cs_forged", plan_slug: "pro" }
    assert_response :success
    assert_equal "free", user.primary_account.reload.current_plan.slug
    create_paid_subscription(user.primary_account)
    assert_equal "pro", user.primary_account.current_plan.slug
    assert user.primary_account.paid_subscriber?
    post "/subscriptions/checkout", params: { plan_id: Plan.find_by!(slug: "pro").id }, headers: { "X-Inertia" => "true" }
    assert_response :conflict
    assert_equal 1, Pay::Subscription.count
  end

  test "newsletter consent does not create users workspaces sessions or grants" do
    assert_no_difference [ "User.count", "Account.count", "Session.count", "ProAccessGrant.count" ] do
      assert_difference "NewsletterSubscription.count", 1 do
        2.times do
          post "/newsletter_subscription", params: { email_address: "  Reader@Example.com " }, as: :json
          assert_response :success
        end
      end
    end
    subscription = NewsletterSubscription.find_by!(email_address: "reader@example.com")
    assert_nil subscription.confirmed_at
    token = subscription.generate_token_for(:confirmation)
    get "/newsletter_subscription", params: { token: token }
    assert_response :success
    assert_nil subscription.reload.confirmed_at
    assert_enqueued_with(job: SyncNewsletterToResendJob, args: [ subscription.id ]) do
      patch "/newsletter_subscription", params: { token: token }
      assert_response :success
    end
    assert subscription.reload.confirmed_at?
    patch "/newsletter_subscription", params: { token: token }
    assert_response :gone
    get "/dashboard/api/agents", as: :json
    assert_response :unauthorized
  end

  test "legacy newsletter endpoint also records consent without an account" do
    assert_no_difference [ "User.count", "Account.count", "Session.count" ] do
      post "/registration", params: { email_address: "newsletter@example.com", source: "newsletter" }, as: :json
      assert_response :success
    end
  end

  test "repeat email-only registration cannot sign into an existing pending account" do
    user = create_user(email: "pending@example.com", email_verified: false)
    create_account(owner: user)
    assert_no_difference [ "User.count", "Account.count", "Session.count" ] do
      post "/registration", params: { email_address: " Pending@Example.com " }, as: :json
      assert_response :success
    end
    get "/dashboard/api/provider_keys", as: :json
    assert_response :unauthorized
  end

  test "public pricing remains open and free signup never grants Pro" do
    get "/pricing"
    assert_redirected_to "/plans"
    get "/plans"
    assert_response :success
    post "/registration", params: { email_address: "free@example.com", source: "retainer_pilot", plan_slug: "pro" }, as: :json
    assert_response :success
    user = User.find_by!(email_address: "free@example.com")
    assert_equal "public_signup", user.signup_source
    assert_equal "free", user.primary_account.current_plan.slug
    assert_not user.primary_account.paid_subscriber?
    assert_equal 0, ProAccessGrant.count
  end

  test "workspace members cannot start or modify billing" do
    owner = create_user
    account = create_account(owner: owner)
    member = create_user
    account.account_memberships.create!(user: member, role: "member")
    sign_in_as(member)
    post "/subscriptions/checkout", params: { plan_id: Plan.find_by!(slug: "pro").id }
    assert_response :forbidden
    post "/subscriptions/billing_portal"
    assert_response :forbidden
  end

  test "a complimentary Pro client can still choose paid Pro for the selected workspace" do
    user = create_user
    account = create_account(owner: user)
    admin = create_user(admin: true)
    ProAccess.grant!(account: account, actor: admin, source: "retainer_pilot", reason: "Retainer", review_on: Date.current + 30)
    sign_in_as(user)
    get "/plans", headers: { "X-Inertia" => "true" }
    assert_response :success
    assert_equal "pro", json_response.dig("props", "current_plan", "slug")
    assert_equal false, json_response.dig("props", "subscribed")
    assert_equal "complimentary_pilot", json_response.dig("props", "access_source")
    account.update!(checkout_url: "https://checkout.stripe.com/c/pilot", checkout_expires_at: 1.hour.from_now)
    post "/subscriptions/checkout", params: { plan_id: Plan.find_by!(slug: "pro").id }, headers: { "X-Inertia" => "true" }
    assert_response :success
    assert_equal "https://checkout.stripe.com/c/pilot", json_response["checkout_url"]
    assert_not account.paid_subscriber?
  end

  test "signup claims only the recording minted for its browser session" do
    unrelated = SessionRecording.start_user_session!(visitor_id: "unrelated", owner: nil)
    post "/api/session_recordings/start_user_session", as: :json
    own = SessionRecording.find(json_response["recording_id"])
    post "/registration", params: { email_address: "recording-signup@example.com", recording_id: unrelated.id }, as: :json
    user = User.find_by!(email_address: "recording-signup@example.com")
    get "/verify_email", params: { token: user.email_verification_token }
    patch "/complete_profile", params: { user: { first_name: "Owner" } }
    assert_redirected_to "/dashboard"
    assert_equal user.primary_account.id, own.reload.account_id
    assert_nil unrelated.reload.account_id
  end
end
