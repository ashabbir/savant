Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
  get '/healthz', to: 'rpc#healthz'
  post '/rpc', to: 'rpc#call'

  # Avoid noisy 404s from browsers auto-requesting /favicon.ico
  get '/favicon.ico', to: 'static#favicon'

  # Engine UI (Reasoning Worker Dashboard)
  namespace :engine do
    resources :workers, only: [:index]
    resources :jobs, only: [:index, :show]
    
    # Blackboard Explorer
    get 'blackboard', to: 'blackboard#index'
    get 'blackboard/sessions/:id', to: 'blackboard#show_session'
  end

  # Blackboard API
  scope :blackboard do
    post 'sessions', to: 'blackboard#create_session'
    post 'events', to: 'blackboard#append_event'
    get 'events', to: 'blackboard#replay'
    get 'subscribe', to: 'blackboard#subscribe'
    get 'stats', to: 'blackboard#stats'
    get 'artifacts/:id', to: 'blackboard#get_artifact'
    post 'artifacts', to: 'blackboard#create_artifact'
  end

  # Mount Savant Hub (Rack) for tools, diagnostics, and UI
  mount ->(env) { SavantRails::SavantContainer.hub_app.call(env) }, at: '/'
end
