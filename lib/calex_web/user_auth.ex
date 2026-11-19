defmodule CalexWeb.UserAuth do
  @moduledoc """
  Website session authentication.

  A password login stops for a second factor when two-factor authentication is on.
  CalDAV clients do not use this plug. They use HTTP Basic.
  """

  use CalexWeb, :verified_routes
  import Plug.Conn
  import Phoenix.Controller
  alias Calex.Accounts
  alias Calex.Accounts.User

  def log_in_user(conn, user, params \\ %{}) do
    user = Accounts.confirm_when_email_disabled(user)

    cond do
      is_nil(user.confirmed_at) ->
        conn
        |> put_flash(:error, "confirm your email before logging in")
        |> redirect(to: ~p"/users/log_in")

      challenge_two_factor?(user) ->
        conn
        |> renew_session()
        |> put_session(:two_factor_user_id, user.id)
        |> put_session(:two_factor_remember, params["remember_me"] == "true")
        |> redirect(to: ~p"/users/log_in/two_factor")

      true ->
        establish_session(conn, user)
    end
  end

  def challenge_two_factor?(%User{two_factor_method: :email}) do
    not Accounts.email_disabled?()
  end

  def challenge_two_factor?(%User{} = user), do: User.two_factor_enabled?(user)

  def establish_session(conn, user) do
    user_return_to = get_session(conn, :user_return_to)
    token = Accounts.generate_user_session_token(user)

    conn
    |> renew_session()
    |> put_session(:user_token, token)
    |> redirect(to: user_return_to || ~p"/collections")
  end

  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    conn
    |> renew_session()
    |> put_flash(:info, "logged out")
    |> redirect(to: ~p"/")
  end

  def fetch_current_user(conn, _opts) do
    {user_token, conn} = ensure_user_token(conn)
    user = user_token && Accounts.get_user_by_session_token(user_token)
    assign(conn, :current_user, user)
  end

  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "log in to continue")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/users/log_in")
      |> halt()
    end
  end

  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn |> redirect(to: ~p"/collections") |> halt()
    else
      conn
    end
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/users/log_in")}
    end
  end

  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  defp mount_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      if token = session["user_token"], do: Accounts.get_user_by_session_token(token)
    end)
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      {nil, conn}
    end
  end

  defp renew_session(conn) do
    delete_csrf_token()
    conn |> configure_session(renew: true) |> clear_session()
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn
end
