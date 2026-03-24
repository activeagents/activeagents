Rails.application.routes.draw do
  resource :session, only: [ :new, :create, :destroy ]
  resource :registration, only: [ :new, :create ]
  resources :passwords, param: :token, only: [ :new, :create, :edit, :update ]
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

  # App dashboard (Inertia) - all dashboard routes render React app
  get "dashboard", to: "dashboard#index"
  get "dashboard/*path", to: "dashboard#index"

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

  # API endpoints
  namespace :api do
    # Sandbox-mode endpoints (only available in sandbox containers)
    namespace :sandbox do
      get :status, to: "runs#status"
      resources :runs, only: [ :index, :show, :create ]
    end
    resources :agents do
      member do
        get :versions
        post :restore
        get :runs
        post :execute
        post :test
        post :duplicate
        get :export
        get :analytics
      end
      collection do
        get :presets
      end
    end

    resources :templates, only: [ :index, :show ] do
      member do
        post :use
      end
    end

    resources :runs, controller: "agent_runs", only: [ :index, :show ] do
      member do
        post :cancel
      end
    end

    # Sandbox sessions (free tier demo runners)
    resources :sandboxes, param: :id, only: [ :index, :create, :show, :destroy ] do
      collection do
        post :compare
      end
      member do
        post :run
      end
    end

    # Instance tiers (hardware selection like Colab/HuggingFace)
    resources :instance_tiers, only: [ :index, :show ] do
      collection do
        get :recommend
        get :pricing
      end
    end

    # Session recordings (playback and handoff)
    resources :session_recordings, only: [ :index, :show, :destroy ] do
      member do
        get :actions
        get "snapshot/:action_id", action: :snapshot, as: :snapshot
        post :export
        post :handoff
      end
      collection do
        get :recent
        get :demo
      end
    end

    resource :analytics, only: [ :show ], controller: "analytics", action: :index

    # Ragents benchmark results — accepts POSTed JSON from bin/bench
    # GET  /api/benchmarks     — list recent runs
    # POST /api/benchmarks     — ingest a new benchmark run from bin/bench
    resources :benchmarks, only: [ :index, :create ]

    namespace :v1 do
      resources :plans, only: [ :index ]
    end
  end
end
