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

  # Authentication
  resource :session, only: [:new, :create, :destroy]
  resource :registration, only: [:new, :create]

  # App dashboard (Inertia)
  get "dashboard", to: "dashboard#index"

  # Plans (public)
  resources :plans, only: [:index]

  # Subscriptions (requires auth + account)
  resources :subscriptions, only: [:index, :destroy] do
    collection do
      post :checkout
      post :billing_portal
      patch :change_plan
      post :resume
    end
  end

  # API
  namespace :api do
    namespace :v1 do
      resources :plans, only: [:index]
    end
  end

  # Pay webhooks are auto-mounted at /pay/webhooks/stripe
  # via Pay::Engine (configured in config/initializers/pay.rb)
end
