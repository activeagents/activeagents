class Session < ApplicationRecord
  belongs_to :user
  belongs_to :account, optional: true
end
