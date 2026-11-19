defmodule CalexWeb.UserSettingsController do
  use CalexWeb, :controller

  alias Calex.Accounts

  def edit(conn, _params) do
    user = conn.assigns.current_user

    render(conn, :edit,
      email_changeset: Accounts.change_user_email(user),
      password_changeset: Accounts.change_user_password(user),
      locale: user.locale || "en"
    )
  end

  def update(conn, %{"action" => "update_email"} = params) do
    user = conn.assigns.current_user
    %{"current_password" => password, "user" => user_params} = params

    case Accounts.apply_user_email(user, password, user_params) do
      {:ok, applied} ->
        Accounts.deliver_update_email_instructions(
          applied,
          user.email,
          &url(~p"/users/settings/confirm_email/#{&1}")
        )

        conn
        |> put_flash(:info, "check the new address to confirm the change")
        |> redirect(to: ~p"/users/settings")

      {:error, changeset} ->
        render(conn, :edit,
          email_changeset: changeset,
          password_changeset: Accounts.change_user_password(user),
          locale: user.locale || "en"
        )
    end
  end

  def update(conn, %{"action" => "update_password"} = params) do
    user = conn.assigns.current_user
    %{"current_password" => password, "user" => user_params} = params

    case Accounts.update_user_password(user, password, user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "password updated")
        |> CalexWeb.UserAuth.log_in_user(user)

      {:error, changeset} ->
        render(conn, :edit,
          email_changeset: Accounts.change_user_email(user),
          password_changeset: changeset,
          locale: user.locale || "en"
        )
    end
  end

  def update(conn, %{"action" => "update_locale", "locale" => locale}) do
    user = conn.assigns.current_user

    case Accounts.update_user_locale(user, locale) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "language updated")
        |> redirect(to: ~p"/users/settings")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "language was not saved")
        |> redirect(to: ~p"/users/settings")
    end
  end

  def confirm_email(conn, %{"token" => token}) do
    case Accounts.update_user_email(conn.assigns.current_user, token) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "email updated")
        |> redirect(to: ~p"/users/settings")

      :error ->
        conn
        |> put_flash(:error, "email link is invalid or has expired")
        |> redirect(to: ~p"/users/settings")
    end
  end
end
