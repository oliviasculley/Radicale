defmodule CalexWeb.UserSessionController do
  use CalexWeb, :controller

  alias Calex.Accounts
  alias CalexWeb.UserAuth

  def new(conn, _params) do
    render(conn, :new, error_message: nil, email: nil)
  end

  def create(conn, %{"user" => %{"email" => email, "password" => password} = user_params}) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      UserAuth.log_in_user(conn, user, user_params)
    else
      render(conn, :new, error_message: "invalid email or password", email: email)
    end
  end

  def delete(conn, _params) do
    UserAuth.log_out_user(conn)
  end
end
