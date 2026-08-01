# frozen_string_literal: true

require "test_helper"

class AdminResourceTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @account = create_account(owner: @user)
  end

  test "register_report! accepts symbol-keyed payloads" do
    resource = AdminResource.register_report!(
      account: @account,
      service_name: "support_inbox",
      payload: { name: "Ticket", table_name: "tickets", columns: [ { name: "subject", type: "string" } ] }
    )

    assert_equal "Ticket", resource.name
    assert_equal "tickets", resource.table_name
    assert_equal [ "subject" ], resource.column_names
  end

  test "register_report! rejects names that are not model class names" do
    [ "ticket", "Ticket; DROP TABLE", "商品", "class Foo\nend" ].each do |bad_name|
      assert_raises(ActiveRecord::RecordInvalid, "expected #{bad_name.inspect} to be rejected") do
        AdminResource.register_report!(account: @account, service_name: "app", payload: { "name" => bad_name })
      end
    end
  end

  test "a re-report without admin_route clears it and flips the surface posture" do
    AdminResource.register_report!(
      account: @account, service_name: "app",
      payload: { "name" => "Ticket", "admin_route" => "/admin/tickets" }
    )
    resource = AdminResource.register_report!(
      account: @account, service_name: "app",
      payload: { "name" => "Ticket" }
    )

    assert_nil resource.admin_route
    assert_not resource.admin_ui?
  end

  test "register_report! clamps oversized record counts instead of failing the row" do
    resource = AdminResource.register_report!(
      account: @account, service_name: "app",
      payload: { "name" => "Ticket", "record_count" => 2**40 }
    )

    assert_equal 2**31 - 1, resource.record_count
  end

  test "register_report! bounds reported columns and associations" do
    resource = AdminResource.register_report!(
      account: @account, service_name: "app",
      payload: {
        "name" => "Ticket",
        "columns" => (1..(AdminResource::MAX_COLUMNS + 10)).map { |i| { "name" => "col#{i}" } },
        "associations" => (1..(AdminResource::MAX_ASSOCIATIONS + 10)).map { |i| { "kind" => "has_many", "name" => "assoc#{i}" } }
      }
    )

    assert_equal AdminResource::MAX_COLUMNS, resource.columns.size
    assert_equal AdminResource::MAX_ASSOCIATIONS, resource.associations.size
  end

  test "register_report! enforces the per-account resource cap for new rows" do
    original = AdminResource::MAX_PER_ACCOUNT
    AdminResource.send(:remove_const, :MAX_PER_ACCOUNT)
    AdminResource.const_set(:MAX_PER_ACCOUNT, 1)

    AdminResource.register_report!(account: @account, service_name: "app", payload: { "name" => "Ticket" })

    assert_raises(ArgumentError) do
      AdminResource.register_report!(account: @account, service_name: "app", payload: { "name" => "Reply" })
    end

    # Updating an existing row is still allowed at the cap.
    updated = AdminResource.register_report!(
      account: @account, service_name: "app", payload: { "name" => "Ticket", "record_count" => 5 }
    )
    assert_equal 5, updated.record_count
  ensure
    AdminResource.send(:remove_const, :MAX_PER_ACCOUNT)
    AdminResource.const_set(:MAX_PER_ACCOUNT, original)
  end

  test "schema_fingerprint changes when the reported schema changes" do
    resource = AdminResource.register_report!(
      account: @account, service_name: "app",
      payload: { "name" => "Ticket", "columns" => [ { "name" => "subject", "type" => "string" } ] }
    )
    before = resource.schema_fingerprint

    resource = AdminResource.register_report!(
      account: @account, service_name: "app",
      payload: { "name" => "Ticket", "columns" => [ { "name" => "subject", "type" => "text" } ] }
    )

    assert_not_equal before, resource.schema_fingerprint
  end
end
