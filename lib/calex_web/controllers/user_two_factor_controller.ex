defmodule CalexWeb.UserTwoFactorController do
  use CalexWeb, :controller

  alias Calex.Accounts

  def new(conn, _params) do
    case pending_user(conn) do
      nil ->
        redirect(conn, to: ~p"/users/log_in")

      user ->
        render(conn, :new, user: user, error_message: nil)
    end
  end

  def create(conn, %{"user" => %{"code" => code}}) do
    case pending_user(conn) do
      nil ->
        redirect(conn, to: ~p"/users/log_in")

      user ->
        case Accounts.verify_two_factor_login(user, code) do
          {:ok, user} ->
            conn
            |> delete_session(:two_factor_user_id)
            |> CalexWeb.UserAuth.establish_session(user)

          {:error, _reason} ->
            render(conn, :new, user: user, error_message: "invalid code")
        end
    end
  end

  def send_email(conn, _params) do
    case pending_user(conn) do
      nil ->
        redirect(conn, to: ~p"/users/log_in")

      user ->
        case Accounts.deliver_two_factor_email_code(user) do
          {:ok, _result} ->
            conn
            |> put_flash(:info, "a code was emailed")
            |> redirect(to: ~p"/users/log_in/two_factor")

          {:error, :too_many_codes} ->
            conn
            |> put_flash(:error, "too many codes were requested")
            |> redirect(to: ~p"/users/log_in/two_factor")

          {:error, _reason} ->
            conn
            |> put_flash(:error, "the code could not be sent")
            |> redirect(to: ~p"/users/log_in/two_factor")
        end
    end
  end

  defp pending_user(conn) do
    if id = get_session(conn, :two_factor_user_id), do: Accounts.get_user!(id)
  end
end
