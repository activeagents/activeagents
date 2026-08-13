Rails.application.routes.draw do
  resource :session, only: [ :new, :create, :destroy ]
  resource :registration, only: [ :new, :create ]
  resources :passwords, param: :token, only: [ :new, :create, :edit, :update ]

  # Email verification
  get "verify_email", to: "email_verifications#show", as: :verify_email
  post "resend_verification", to: "email_verifications#create", as: :resend_verification

  # Onboarding flow
  get "pending_verification", to: "onboarding#pending_verification", as: :pending_verification
  get "complete_profile", to: "onboarding#complete_profile", as: :complete_profile
  patch "complete_profile", to: "onboarding#update_profile"

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Landing page
  root to: "pages#home"
  get "pricing", to: "pages#pricing"

  # The dashboard itself: agents, runs, conversations, evaluations, traces,
  # metrics, sandboxes and recordings all come from the activeagent gem's
  # engine, configured for this platform in
  # config/initializers/active_agent_dashboard.rb. Its own /api routes live
  # under the mount (/dashboard/api/...).
  # Named :dashboard so the app's existing dashboard_path links keep working.
  mount ActiveAgent::Dashboard::Engine => "/dashboard", as: :dashboard

  # Plans
  resources :plans, only: [ :index ]

  # Subscriptions
  resources :subscriptions, only: [ :index, :destroy ] do
    collection do
      post :checkout
      post :billing_portal
      patch :change_plan
      post :resume
    end
  end

  # Admin dashboard
  namespace :admin do
    resources :spaces, only: [ :index, :show ] do
      member do
        post :terminate
        get :logs
      end
    end

    root to: "spaces#index"
  end

  # MCP service — the account's agents presented as an authenticated MCP
  # server (tools + agent:// resources) over Streamable HTTP JSON-RPC.
  # Authenticated with a platform API key (Settings -> API Keys).
  #
  # The engine serves the same controller under its mount; this keeps the
  # documented root-level endpoint clients are already configured against.
  post "mcp", to: "active_agent/dashboard/api/mcp#create"

  # Telemetry ingestion — the activeagent gem's telemetry reporter POSTs
  # batched traces here (Configuration::DEFAULT_ENDPOINT is
  # https://api.activeagents.ai/v1/traces). Authenticated with the
  # account's telemetry API key (Bearer token).
  scope module: :api do
    namespace :v1 do
      resources :traces, only: [ :create ]
    end
  end

  # API endpoints this platform owns. Everything the dashboard reads is
  # served by the engine under its mount.
  namespace :api do
    # Plan usage and limits — billing, so ours.
    resource :usage, only: [ :show ], controller: "usage" do
      post :check
    end

    # Sandbox-mode endpoints (only available inside sandbox containers).
    namespace :sandbox do
      get :status, to: "runs#status"
      resources :runs, only: [ :index, :show, :create ]
    end

    # Ragents benchmark results — accepts POSTed JSON from bin/bench.
    resources :benchmarks, only: [ :index, :create ] do
      collection do
        post :run
      end
    end

    namespace :v1 do
      resources :plans, only: [ :index ]
      # Alias of POST /v1/traces for clients configured with an /api prefix.
      resources :traces, only: [ :create ]
    end
  end
end
