Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Claiming the instance with the console's setup code. 404 once claimed: see Setup.
  get  "setup", to: "setup#new"
  post "setup", to: "setup#create"

  # OIDC login (OidcAuthController). Backchannel logout is the provider's
  # server-to-server POST.
  get    "login",         to: "oidc_auth#login",  as: :login
  get    "login/start",   to: "oidc_auth#start",  as: :login_start
  get    "auth/callback", to: "oidc_auth#callback", as: :auth_callback
  delete "logout",        to: "oidc_auth#logout", as: :logout
  post   "oidc/logout",   to: "oidc_auth#backchannel_logout", as: :oidc_logout

  root "dashboard#show"
end
