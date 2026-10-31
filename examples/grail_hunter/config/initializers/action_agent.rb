# frozen_string_literal: true

# The Active Agent dashboard (the actionagent engine), mounted at
# /activeagents in config/routes.rb. Every hunt's generation lands there as a
# trace with a span waterfall, tool calls and token counts.
#
# The dashboard shows prompts and outputs for every customer's hunts, so it
# sits behind the app's own sign-in and is limited to admin accounts (the
# first account registered on an install). The engine's controllers are not
# this app's controllers, so the signed-in user is read straight from the
# session cookie the Authentication concern writes.
#
# The generator's full annotated initializer, covering multi-tenant mode,
# ingest keys, sandboxes and GitHub, is in the actionagent gem:
#   bundle open actionagent  ->  lib/generators/action_agent/templates/action_agent.rb.erb
ActionAgent.configure do |config|
  # `cookies` is private on a controller; the request's jar is not.
  dashboard_user = ->(controller) {
    session_id = controller.request.cookie_jar.signed[:session_id]
    Session.find_by(id: session_id)&.user if session_id
  }

  config.authentication_method = ->(controller) { dashboard_user.call(controller)&.admin? == true }
  config.current_user_resolver = dashboard_user
  config.sign_in_path = "/session/new"
  config.sign_out_path = "/session"
end
