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

  # Investor Portal (public-facing, magic link authenticated)
  scope :investor, as: :investor_portal do
    get "login", to: "investor_portal#login"
    get "auth/:token", to: "investor_portal#authenticate", as: :authenticate
    get "dashboard", to: "investor_portal#dashboard"
    get "documents", to: "investor_portal#documents"
    get "documents/:id", to: "investor_portal#show_document", as: :document
    get "documents/:id/download", to: "investor_portal#download_document", as: :download_document
    delete "logout", to: "investor_portal#logout"
  end

  # Admin Dashboard (Inertia pages for founders)
  namespace :admin do
    resources :investors do
      member do
        post :send_portal_invite
        post :regenerate_access_token
      end
    end

    resources :safe_agreements do
      member do
        post :send_for_signature
        post :mark_signed
        post :convert
        post :cancel
      end
    end

    resources :investor_documents do
      member do
        get :analytics
      end
      resources :access_grants, only: [ :create, :destroy ], controller: "document_access_grants"
    end

    resources :cap_table, only: [ :index ]
  end

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

  # API endpoints
  namespace :api do
    # Admin API for investor portal management
    namespace :admin do
      resources :investors, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          post :send_portal_invite
        end
      end

      resources :safe_agreements, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          post :send_for_signature
          post :mark_signed
          post :convert
        end
      end

      resources :investor_documents, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          get :analytics
        end
        resources :access_grants, only: [ :create, :destroy ], controller: "document_access_grants"
      end

      resource :cap_table, only: [ :show ], controller: "cap_table"
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

    resource :analytics, only: [ :show ], controller: "analytics", action: :index

    namespace :v1 do
      resources :plans, only: [ :index ]
    end
  end
end
