Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Claiming the instance with the console's setup code. 404 once claimed: see Setup.
  get  "setup", to: "setup#new"
  post "setup", to: "setup#create"
  post "setup/password", to: "setup#create_password", as: :setup_password

  # Sign-in: a password (PasswordSessionsController) or OIDC (OidcAuthController),
  # whichever setup chose (ADR 0015). Backchannel logout is the provider's
  # server-to-server POST.
  get    "login",         to: "oidc_auth#login",  as: :login
  post   "login",         to: "password_sessions#create"
  get    "login/start",   to: "oidc_auth#start",  as: :login_start
  get    "auth/callback", to: "oidc_auth#callback", as: :auth_callback
  delete "logout",        to: "oidc_auth#logout", as: :logout
  post   "oidc/logout",   to: "oidc_auth#backchannel_logout", as: :oidc_logout

  # The owner's sign-in settings: change the email or password, or switch to OIDC.
  get   "settings",          to: "settings#show",            as: :settings
  patch "settings/email",    to: "settings#update_email",    as: :settings_email
  patch "settings/password", to: "settings#update_password", as: :settings_password
  post  "settings/oidc",     to: "settings#link_oidc",       as: :settings_oidc

  # Monitors are defined in git (ADR 0016): Pedant shows them and edits only
  # where it reads them from.
  resources :monitors, only: :show
  resources :sources, only: %i[ create update ] do
    post :sync, on: :member
  end

  # Push monitors, on Kuma's URL shape (ADR 0012). PushTokenFilter has already
  # replaced the token with [FILTERED] by the time this matches.
  match "api/push/[FILTERED]", to: "pushes#create", via: %i[ get post ], as: :push

  root "dashboard#show"
end
