module WorkspaceAgentAttribution
  extend ActiveSupport::Concern

  included do
    before_validation :attribute_workspace_creator, on: :create
  end

  private

  def attribute_workspace_creator
    return if user_id || !account
    self.user_id = Current.account&.id == account_id ? Current.user.id : account.owner_id
  end
end
