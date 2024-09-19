class Message < ApplicationRecord
  include ActionView::RecordIdentifier

  enum :role, {
    system: "system", assistant: "assistant", user: "user"
  }

  belongs_to :chat
end