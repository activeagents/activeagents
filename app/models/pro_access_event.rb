class ProAccessEvent < ApplicationRecord
  belongs_to :pro_access_grant
  belongs_to :actor, class_name: "User", optional: true
  validates :action, inclusion: { in: %w[granted updated revoked expired] }
  after_create_commit -> { ProAccessNoticeJob.perform_later(id) }
end
