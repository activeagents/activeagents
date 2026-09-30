class ProAccessNoticeJob < ApplicationJob
  def perform(event_id)
    event = ProAccessEvent.find(event_id)
    event.with_lock do
      return if event.notified_at?
      PilotMailer.access_notice(event).deliver_now
      event.update!(notified_at: Time.current)
    end
  end
end
