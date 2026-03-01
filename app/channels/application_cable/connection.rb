module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :anonymous_id

    def connect
      set_current_user || allow_anonymous
    end

    private

    def set_current_user
      if session = Session.find_by(id: cookies.signed[:session_id])
        self.current_user = session.user
        true
      else
        false
      end
    end

    # Allow anonymous connections for sandbox free tier
    def allow_anonymous
      self.anonymous_id = SecureRandom.uuid
      true
    end
  end
end
