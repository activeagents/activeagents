class Reply < ApplicationRecord
  belongs_to :ticket

  validates :body, :author, presence: true

  scope :drafts, -> { where(draft: true) }
  scope :sent, -> { where(draft: false) }

  def send!
    update!(draft: false)
    ticket.waiting!
  end
end
