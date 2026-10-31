Rails.application.routes.draw do
  root "home#index"

  resource :session
  resources :passwords, param: :token
  resource :registration, only: [ :new, :create ]

  resources :hunts do
    member do
      post :run      # queue a discovery run now
      post :plan     # ask the planner agent for search queries
      patch :pause
      patch :resume
    end
    resources :runs, only: :show, controller: "discovery_runs"
  end

  resources :findings, only: :index do
    member do
      patch :keep
      patch :dismiss
    end
  end

  resource :billing, only: :show do
    post :subscribe
    delete :cancel
  end

  # The Active Agent dashboard: traces, metrics, evaluations. Admins only;
  # see config/initializers/action_agent.rb.
  mount ActionAgent::Engine => "/activeagents"

  get "up" => "rails/health#show", as: :rails_health_check
end
