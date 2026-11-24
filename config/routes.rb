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
  resources :monitors, only: :show do
    # Hiding a down monitor for its current outage (ADR 0033). That's about an
    # outage Pedant observed, not the monitor's definition.
    resource :hide, only: %i[ create destroy ], controller: "monitor_hides"
  end
  resources :sources, only: %i[ create update ] do
    post :sync, on: :member
  end

  # What git says each host should run, and later what runs (dkam/pedant#16).
  resources :deployments, only: :index

  # Alerts (ADR 0013): channel settings, a test per channel, and the log.
  resources :alerts, only: :index
  resources :alert_channels, only: :update, param: :kind do
    post :test, on: :member
  end

  # API tokens for /mcp (ADR 0025): made here, shown once.
  resources :api_tokens, only: %i[ create destroy ], path: "settings/api_tokens"

  # The read-only MCP server (ADR 0025), for agents, with an API token. Only
  # POST is spoken; GET (an event stream) and DELETE (a session) get 405.
  post  "mcp", to: "mcp#create", as: :mcp
  match "mcp", to: "mcp#method_not_allowed", via: %i[ get delete ]

  # Push monitors, on Kuma's URL shape (ADR 0012). PushTokenFilter has already
  # replaced the token with [FILTERED] by the time this matches.
  match "api/push/[FILTERED]", to: "pushes#create", via: %i[ get post ], as: :push

  root "dashboard#show"
end
