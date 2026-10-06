require "test_helper"
require_relative "../support/teammate_helpers"

# Real concurrent transactions are exercised against PostgreSQL in CI.
class TeammateInvitationConcurrencyTest < ActiveSupport::TestCase
  include TeammateHelpers
  self.use_transactional_tests = false

  setup do
    skip "PGlite multiplexes a single backend; PostgreSQL CI exercises row locks" if ENV["PGLITE_TEST"]
    # The plan comes from Plan.free rather than a subscription, so no billing
    # rows outlive the test.
    @plan = Plan.create!(name: "Free", slug: "free", price_cents: 0, included_seats: 3)
    @owner = create_user(email: "owner-#{SecureRandom.hex(6)}@example.com")
    @account = create_account(owner: @owner)
  end

  teardown do
    next unless @account

    WorkspaceInvitation.where(account: @account).delete_all
    users = @account.members.to_a
    @account.reload.destroy!
    users.each { |user| user.reload.destroy! if User.exists?(user.id) }
    @plan&.destroy!
  end

  test "simultaneous acceptance adds the invitee once" do
    invitee = create_user(email: "invitee-#{SecureRandom.hex(6)}@example.com")
    invitation = WorkspaceMembers.new(@account, actor: @owner).invite!(email_address: invitee.email_address, role: "member")
    token = SecureRandom.urlsafe_base64(32)
    invitation.update!(token_digest: Digest::SHA256.hexdigest(token), token_expires_at: 1.day.from_now, delivery_state: "sent")

    outcomes = race(2) do
      AcceptWorkspaceInvitation.call(token: token, signed_in_user: invitee)
      :accepted
    rescue AcceptWorkspaceInvitation::Invalid
      :consumed
    end

    assert_equal [ :accepted, :consumed ], outcomes.sort, outcomes.inspect
    assert_equal 1, @account.account_memberships.where(user: invitee).count
  end

  test "simultaneous invitations cannot take more seats than the plan includes" do
    add_member(@account)

    outcomes = race(2) do |index|
      WorkspaceMembers.new(@account, actor: @owner).invite!(email_address: "racer-#{index}@example.com", role: "member")
      :invited
    rescue WorkspaceMembers::Refused
      :refused
    end

    assert_equal [ :invited, :refused ], outcomes.sort, outcomes.inspect
    assert_equal 3, @account.seats_in_use
  end

  private

  def race(count, &block)
    ready, start, results = Queue.new, Queue.new, Queue.new
    threads = count.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          results << begin
            block.call(index)
          rescue StandardError => error
            error
          end
        end
      end
    end
    count.times { ready.pop }
    count.times { start << true }
    threads.each(&:join)
    count.times.map { results.pop }
  end
end
