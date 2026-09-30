require "test_helper"
require_relative "../support/pilot_helpers"

# Real concurrent transactions are exercised against PostgreSQL in CI.
class PilotInvitationConcurrencyTest < ActiveSupport::TestCase
  include PilotHelpers
  self.use_transactional_tests = false

  test "simultaneous acceptance provisions only one workspace and grant" do
    skip "PGlite multiplexes a single backend; PostgreSQL CI exercises row locks" if ENV["PGLITE_TEST"]
    plan = Plan.create!(name: "Pro", slug: "pro", price_cents: 9900)
    admin = create_user(admin: true)
    invitation = prepare_invitation(admin: admin, email: "concurrent-#{SecureRandom.hex(6)}@example.com")
    token = SecureRandom.urlsafe_base64(32)
    invitation.update!(token_digest: Digest::SHA256.hexdigest(token), token_expires_at: 1.day.from_now, delivery_state: "sent")
    ready, start, results = Queue.new, Queue.new, Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          begin
            result = AcceptWorkspaceInvitation.call(token: token, signed_in_user: nil,
              password: "password123", password_confirmation: "password123")
            results << result.account_id
          rescue AcceptWorkspaceInvitation::Invalid
            results << :consumed
          rescue StandardError => error
            results << error
          end
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    threads.each(&:join)
    outcomes = 2.times.map { results.pop }
    assert_equal 1, outcomes.count(:consumed), outcomes.inspect
    account = invitation.reload.account
    assert_equal 1, outcomes.count(account.id)
    assert_equal 1, User.where(email_address: invitation.email_address).count
    assert_equal 1, account.account_memberships.count
    assert_equal 1, ProAccessGrant.where(account: account).count
    assert_equal 1, account.pro_access_grant.events.where(action: "granted").count
  ensure
    if invitation
      recipient = invitation.reload.accepted_by
      account = invitation.account
      invitation.destroy!
      account&.destroy!
      recipient&.destroy!
    end
    admin&.destroy!
    plan&.destroy!
  end
end
