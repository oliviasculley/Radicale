defmodule CalexWeb.UserResetPasswordController do
  use CalexWeb, :controller

  alias Calex.Accounts

  def new(conn, _params) do
    render(conn, :new)
  end

  def create(conn, %{"user" => %{"email" => email}}) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &url(~p"/users/reset_password/#{&1}")
      )
    end

    conn
    |> put_flash(:info, "if that account can reset its password, the instructions are on the way")
    |> redirect(to: ~p"/")
  end

  def edit(conn, %{"token" => token}) do
    if user = Accounts.get_user_by_reset_password_token(token) do
      render(conn, :edit,
        user: user,
        token: token,
        changeset: Accounts.change_user_password(user)
      )
    else
      conn
      |> put_flash(:error, "reset link is invalid or has expired")
      |> redirect(to: ~p"/")
    end
  end

  def update(conn, %{"token" => token, "user" => user_params}) do
    if user = Accounts.get_user_by_reset_password_token(token) do
      case Accounts.reset_user_password(user, user_params) do
        {:ok, _user} ->
          conn
          |> put_flash(:info, "password updated")
          |> redirect(to: ~p"/users/log_in")

        {:error, changeset} ->
          render(conn, :edit, user: user, token: token, changeset: changeset)
      end
    else
      conn
      |> put_flash(:error, "reset link is invalid or has expired")
      |> redirect(to: ~p"/")
    end
  end
end
