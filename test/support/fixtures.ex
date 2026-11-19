defmodule Calex.AccountsFixtures do
  @moduledoc false

  alias Calex.Accounts
  alias Calex.Accounts.{Invites, User}
  alias Calex.Repo

  def unique_email, do: "user#{System.unique_integer([:positive])}@example.com"
  def valid_password, do: "passwordpassword"

  def user_fixture(attrs \\ %{}) do
    email = Map.get(attrs, :email, unique_email())
    password = Map.get(attrs, :password, valid_password())

    {:ok, user} =
      Accounts.register_user(
        %{"email" => email, "password" => password, "locale" => "en"},
        Map.get(attrs, :invite_token)
      )

    if Map.get(attrs, :confirmed) == false or user.confirmed_at do
      user
    else
      user |> User.confirm_changeset() |> Repo.update!()
    end
  end

  def invite_user(admin, attrs \\ %{}) do
    {:ok, invite} =
      Invites.create_invite(admin, %{
        "name" => Map.get(attrs, :name, "guest#{System.unique_integer([:positive])}"),
        "uses_left" => Map.get(attrs, :uses_left, 5)
      })

    user_fixture(Map.put(attrs, :invite_token, invite.token))
  end
end
