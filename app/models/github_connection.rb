# frozen_string_literal: true

# An account's GitHub OAuth grant and the repositories it made available
# (Settings -> Integrations). Lives in the activeagent gem's dashboard engine,
# like ProviderKey; the name is kept here so the rest of the app can refer to
# it the same way.
GithubConnection = ActionAgent::GithubConnection
