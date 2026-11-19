defmodule CalexWeb.UserRegistrationController do
  use CalexWeb, :controller

  alias Calex.Accounts
  alias Calex.Accounts.Invites
  alias CalexWeb.UserAuth

  def new(conn, params) do
    token = params["invite"]

    render(conn, :new,
      changeset: Accounts.change_user_registration(),
      invite_token: token,
      open: Accounts.allow_registration?() or Invites.valid_invite_token?(token)
    )
  end

  def create(conn, %{"user" => user_params}) do
    token = blank_to_nil(user_params["invite_token"])

    case Accounts.register_user(user_params, token) do
      {:ok, user} ->
        if Accounts.email_disabled?() do
          UserAuth.log_in_user(conn, user)
        else
          Accounts.deliver_user_confirmation_instructions(user, &url(~p"/users/confirm/#{&1}"))

          conn
          |> put_flash(:info, "check your email to confirm your account")
          |> redirect(to: ~p"/users/log_in")
        end

      {:error, :invalid_token} ->
        conn
        |> put_flash(:error, "an invite is required")
        |> render(:new,
          changeset: Accounts.change_user_registration(user_params),
          invite_token: token,
          open: false
        )

      {:error, changeset} ->
        render(conn, :new,
          changeset: changeset,
          invite_token: token,
          open: true
        )
    end
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end
