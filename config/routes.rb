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

  # API endpoints
  namespace :api do
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
