# A way a user signs in through an external provider. `uid` is the provider's
# immutable account id (GitHub's numeric user id). `login` and `email` are
# refreshed from the provider on every sign-in and are for display only.
class UserIdentity < ApplicationRecord
  PROVIDERS = %w[ github ].freeze

  belongs_to :user

  validates :provider, inclusion: { in: PROVIDERS }, uniqueness: { scope: :user_id }
  validates :uid, presence: true, uniqueness: { scope: :provider }
end
