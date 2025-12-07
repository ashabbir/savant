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

  # Mount Savant Hub (Rack) for tools, diagnostics, and UI
  mount ->(env) { SavantRails::SavantContainer.hub_app.call(env) }, at: '/'
end
