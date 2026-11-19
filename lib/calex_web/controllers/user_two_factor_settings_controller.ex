defmodule CalexWeb.UserTwoFactorSettingsController do
  use CalexWeb, :controller

  alias Calex.Accounts
  alias Calex.Accounts.TwoFactor

  def edit(conn, _params) do
    user = conn.assigns.current_user
    secret = get_session(conn, :pending_totp_secret) || TwoFactor.generate_totp_secret()

    conn
    |> put_session(:pending_totp_secret, secret)
    |> render(:edit,
      secret: secret,
      uri: TwoFactor.totp_uri(user.email, secret),
      manual_key: TwoFactor.manual_entry_key(secret),
      recovery_count: Accounts.count_two_factor_recovery_codes(user),
      recovery_codes: get_session(conn, :recovery_codes),
      error_message: nil
    )
  end

  def enable_app(conn, %{"user" => %{"password" => password, "code" => code}}) do
    user = conn.assigns.current_user
    secret = get_session(conn, :pending_totp_secret)

    case Accounts.enable_app_two_factor(user, password, secret, code,
           keep_session_token: get_session(conn, :user_token)
         ) do
      {:ok, _user, codes} ->
        conn
        |> delete_session(:pending_totp_secret)
        |> put_session(:recovery_codes, codes)
        |> put_flash(:info, "authenticator two-factor is on")
        |> redirect(to: ~p"/users/settings/two_factor")

      {:error, reason} ->
        render_edit(conn, user, secret, reason)
    end
  end

  def send_email(conn, _params) do
    case Accounts.deliver_two_factor_email_code(conn.assigns.current_user) do
      {:ok, _result} ->
        conn
        |> put_flash(:info, "a code was emailed")
        |> redirect(to: ~p"/users/settings/two_factor")

      {:error, reason} ->
        conn
        |> put_flash(:error, two_factor_error(reason))
        |> redirect(to: ~p"/users/settings/two_factor")
    end
  end

  def enable_email(conn, %{"user" => %{"password" => password, "code" => code}}) do
    user = conn.assigns.current_user

    case Accounts.enable_email_two_factor(user, password, code,
           keep_session_token: get_session(conn, :user_token)
         ) do
      {:ok, _user, codes} ->
        conn
        |> put_session(:recovery_codes, codes)
        |> put_flash(:info, "email two-factor is on")
        |> redirect(to: ~p"/users/settings/two_factor")

      {:error, reason} ->
        secret = get_session(conn, :pending_totp_secret)
        render_edit(conn, user, secret, reason)
    end
  end

  def disable(conn, %{"user" => %{"password" => password}}) do
    case Accounts.disable_two_factor(conn.assigns.current_user, password) do
      {:ok, _user} ->
        conn
        |> delete_session(:recovery_codes)
        |> put_flash(:info, "two-factor authentication is off")
        |> redirect(to: ~p"/users/settings/two_factor")

      {:error, reason} ->
        conn
        |> put_flash(:error, two_factor_error(reason))
        |> redirect(to: ~p"/users/settings/two_factor")
    end
  end

  def regenerate(conn, %{"user" => %{"password" => password}}) do
    case Accounts.regenerate_two_factor_recovery_codes(conn.assigns.current_user, password) do
      {:ok, codes} ->
        conn
        |> put_session(:recovery_codes, codes)
        |> put_flash(:info, "new recovery codes are below")
        |> redirect(to: ~p"/users/settings/two_factor")

      {:error, reason} ->
        conn
        |> put_flash(:error, two_factor_error(reason))
        |> redirect(to: ~p"/users/settings/two_factor")
    end
  end

  defp render_edit(conn, user, secret, reason) do
    render(conn, :edit,
      secret: secret,
      uri: secret && TwoFactor.totp_uri(user.email, secret),
      manual_key: secret && TwoFactor.manual_entry_key(secret),
      recovery_count: Accounts.count_two_factor_recovery_codes(user),
      recovery_codes: nil,
      error_message: two_factor_error(reason)
    )
  end

  defp two_factor_error(:invalid_code), do: "invalid code"
  defp two_factor_error(:invalid_password), do: "invalid password"
  defp two_factor_error(:already_enabled), do: "two-factor is already on"
  defp two_factor_error(:email_disabled), do: "email is disabled"
  defp two_factor_error(:unconfirmed_email), do: "confirm your email first"
  defp two_factor_error(:too_many_codes), do: "too many codes were requested"
  defp two_factor_error(:not_enabled), do: "two-factor is off"
  defp two_factor_error(reason), do: to_string(reason)
end
