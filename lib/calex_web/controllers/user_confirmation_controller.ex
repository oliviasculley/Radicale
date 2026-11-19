defmodule CalexWeb.UserConfirmationController do
  use CalexWeb, :controller

  alias Calex.Accounts

  def new(conn, _params) do
    render(conn, :new)
  end

  def create(conn, %{"user" => %{"email" => email}}) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_confirmation_instructions(user, &url(~p"/users/confirm/#{&1}"))
    end

    conn
    |> put_flash(:info, "if that email can be confirmed, the instructions are on the way")
    |> redirect(to: ~p"/")
  end

  def confirm(conn, %{"token" => token}) do
    case Accounts.confirm_user(token) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "email confirmed")
        |> redirect(to: ~p"/users/log_in")

      :error ->
        conn
        |> put_flash(:error, "confirmation link is invalid or has expired")
        |> redirect(to: ~p"/")
    end
  end
end
