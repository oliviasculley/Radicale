defmodule CalexWeb.Router do
  use CalexWeb, :router

  import CalexWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CalexWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  scope "/", CalexWeb do
    pipe_through :browser

    get "/", PageController, :home
    delete "/users/log_out", UserSessionController, :delete
    get "/users/confirm", UserConfirmationController, :new
    post "/users/confirm", UserConfirmationController, :create
    get "/users/confirm/:token", UserConfirmationController, :confirm
  end

  scope "/", CalexWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
    get "/users/log_in", UserSessionController, :new
    post "/users/log_in", UserSessionController, :create
    get "/users/log_in/two_factor", UserTwoFactorController, :new
    post "/users/log_in/two_factor", UserTwoFactorController, :create
    post "/users/log_in/two_factor/email", UserTwoFactorController, :send_email
    get "/users/reset_password", UserResetPasswordController, :new
    post "/users/reset_password", UserResetPasswordController, :create
    get "/users/reset_password/:token", UserResetPasswordController, :edit
    put "/users/reset_password/:token", UserResetPasswordController, :update
  end

  scope "/", CalexWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm_email/:token", UserSettingsController, :confirm_email
    get "/users/settings/two_factor", UserTwoFactorSettingsController, :edit
    post "/users/settings/two_factor/app", UserTwoFactorSettingsController, :enable_app
    post "/users/settings/two_factor/email", UserTwoFactorSettingsController, :send_email
    put "/users/settings/two_factor/email", UserTwoFactorSettingsController, :enable_email
    delete "/users/settings/two_factor", UserTwoFactorSettingsController, :disable
    post "/users/settings/two_factor/recovery", UserTwoFactorSettingsController, :regenerate

    live_session :authenticated, on_mount: [{CalexWeb.UserAuth, :ensure_authenticated}] do
      live "/collections", CollectionLive, :index
      live "/invites", InviteLive, :index
    end
  end
end
