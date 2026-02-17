Rails.application.routes.draw do
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
      end
      collection do
        get :presets
      end
    end

    resources :runs, controller: "agent_runs", only: [:index, :show] do
      member do
        post :cancel
      end
    end
  end
end
