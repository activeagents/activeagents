# frozen_string_literal: true

# One ActiveRecord model reported by a connected app (POST /v1/resources).
# The manifest row the platform scaffolds an admin agent from — the
# rails_admin analogue: rails_admin turns a model into admin screens, we
# turn it into an admin agent. Identity follows the auto-registration
# convention: account + service_name (the connected app) + name (the model
# class); environment is attribution, not identity.
class AdminResource < ApplicationRecord
  belongs_to :account
  belongs_to :agent, optional: true

  # Resource names must look like Ruby model class names — they flow into
  # agent names, slugs, and generated class code, and anything else is a
  # misconfigured (or hostile) reporter.
  NAME_FORMAT = /\A[A-Z][A-Za-z0-9_:]*\z/

  # Cardinality caps: per-account row cap (a reporter looping over invented
  # service/model names must not create unbounded rows) and per-row bounds
  # on the reported arrays (jsonb bloat).
  MAX_PER_ACCOUNT = 500
  MAX_COLUMNS = 200
  MAX_ASSOCIATIONS = 100

  validates :service_name, presence: true, length: { maximum: 100 }
  validates :name, presence: true, length: { maximum: 80 },
    format: { with: NAME_FORMAT, message: "must be a model class name" },
    uniqueness: { scope: [ :account_id, :service_name ] }

  scope :recent, -> { order(last_reported_at: :desc, name: :asc) }
  scope :for_service, ->(service) { where(service_name: service) }
  scope :with_agent, -> { where.not(agent_id: nil) }

  # Upserts one reported resource. Reports are full snapshots: columns,
  # associations and counts are replaced, not merged, so a dropped column
  # disappears from the manifest on the next report.
  def self.register_report!(account:, service_name:, environment: nil, payload: {})
    payload = payload.respond_to?(:stringify_keys) ? payload.stringify_keys : {}
    name = payload["name"].to_s.strip
    raise ArgumentError, "resource name is required" if name.blank?

    resource = find_or_initialize_by(account: account, service_name: service_name, name: name)
    if resource.new_record? && account.admin_resources.count >= MAX_PER_ACCOUNT
      raise ArgumentError, "resource cap (#{MAX_PER_ACCOUNT}) reached for this account"
    end

    resource.first_reported_at ||= Time.current
    resource.assign_attributes(
      environment: environment.presence || resource.environment,
      table_name: payload["table_name"].presence,
      columns: Array(payload["columns"]).first(MAX_COLUMNS).map { |c| normalize_column(c) },
      associations: Array(payload["associations"]).first(MAX_ASSOCIATIONS).map { |a| normalize_association(a) },
      record_count: normalize_count(payload["record_count"]),
      admin_route: payload["admin_route"].presence,
      metadata: payload["metadata"].presence || {},
      last_reported_at: Time.current
    )
    resource.save!
    resource
  end

  # Does the connected app already have an admin UI for this resource? When
  # false, the generated agent works "without the admin UI" — through data
  # tools and the app's public web surface.
  def admin_ui?
    admin_route.present?
  end

  def column_names
    Array(columns).filter_map { |c| c["name"] }
  end

  # Short digest of the reported schema — lets the UI and the scaffolder
  # tell whether a resource changed since its agent was generated.
  def schema_fingerprint
    Digest::SHA256.hexdigest([ columns, associations ].to_json).first(12)
  end

  def self.normalize_column(column)
    column = column.stringify_keys if column.respond_to?(:stringify_keys)
    return {} unless column.is_a?(Hash)

    column.slice("name", "type", "null", "default").compact
  end

  def self.normalize_association(association)
    association = association.stringify_keys if association.respond_to?(:stringify_keys)
    return {} unless association.is_a?(Hash)

    association.slice("kind", "name", "class_name").compact
  end

  # Reported counts are informational; clamp to the 4-byte integer column
  # so a bogus count can't fail the whole row.
  def self.normalize_count(count)
    return nil if count.nil? || !count.respond_to?(:to_i)

    count.to_i.clamp(0, 2**31 - 1)
  end
end
