class DocumentAccessLog < ApplicationRecord
  belongs_to :investor_document
  belongs_to :investor

  validates :action, presence: true, inclusion: { in: %w[viewed downloaded] }

  scope :recent, -> { order(created_at: :desc) }
  scope :views, -> { where(action: "viewed") }
  scope :downloads, -> { where(action: "downloaded") }
  scope :today, -> { where("created_at >= ?", Time.current.beginning_of_day) }
  scope :this_week, -> { where("created_at >= ?", 1.week.ago) }
end
