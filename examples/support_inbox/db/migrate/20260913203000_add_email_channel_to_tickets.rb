# Email support: a ticket gains the identity a mail thread needs (the +tag
# token replies come back on, the Message-Id of the email that opened it, the
# address it was sent to) and a reply gains a direction, so a customer's
# answer and the agent's answer live in the same thread in the right order.
class AddEmailChannelToTickets < ActiveRecord::Migration[8.1]
  def change
    add_column :tickets, :channel, :string, null: false, default: "web"
    add_column :tickets, :mail_token, :string
    add_column :tickets, :mail_message_id, :string
    add_column :tickets, :support_address, :string
    add_column :tickets, :handed_off_at, :datetime
    add_column :tickets, :handoff_reason, :string

    add_index :tickets, :mail_token, unique: true
    add_index :tickets, :mail_message_id

    add_column :replies, :inbound, :boolean, null: false, default: false
    add_column :replies, :message_id, :string
    add_column :replies, :delivered_at, :datetime

    add_index :replies, :message_id
  end
end
