Rails.application.routes.draw do
  # The gem's dev console — local traces & metrics while you build. Mounted
  # in development only: in production this app's telemetry POSTs to the
  # ActiveAgents platform instead (see config/active_agent.yml).
  mount ActiveAgent::Dashboard::Engine => "/active_agent" if Rails.env.local?

  resources :tickets, only: [ :index, :show, :create ] do
    member do
      post :triage
      post :draft_reply
      post :summarize
    end

    resources :replies, only: [ :create ] do
      member do
        post :send_reply
      end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check

  root "tickets#index"
end
