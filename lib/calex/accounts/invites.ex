defmodule Calex.Accounts.Invites do
  @moduledoc """
  Invites that let someone register when sign-up is invite-only.
  """

  import Ecto.Query
  alias Calex.Accounts.{Invite, User}
  alias Calex.Repo

  @invite_token_length 20

  def list_invites(%User{role: :admin}) do
    Repo.all(from i in Invite, order_by: i.name)
  end

  def list_invites(%User{}), do: []

  def create_invite(%User{role: :admin} = user, attrs) do
    token = :crypto.strong_rand_bytes(@invite_token_length) |> Base.url_encode64(padding: false)

    user
    |> Invite.create_changeset(token, attrs)
    |> Repo.insert()
  end

  def create_invite(%User{}, _attrs), do: {:error, :unauthorized}

  def valid_invite_token?(token) when token in [nil, ""], do: false

  def valid_invite_token?(token) do
    Repo.exists?(
      from i in Invite,
        where: i.token == ^token,
        where: is_nil(i.disabled_at),
        where: is_nil(i.uses_left) or i.uses_left > 0
    )
  end

  def use_invite(invite_token) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:invite, fn _repo, _changes -> get_invite_by_token(invite_token) end)
    |> Ecto.Multi.update(:decrement_invite, fn %{invite: invite} ->
      uses_left = if is_nil(invite.uses_left), do: nil, else: invite.uses_left - 1
      Ecto.Changeset.change(invite, uses_left: uses_left)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{decrement_invite: invite}} -> {:ok, invite}
      {:error, :invite, :invalid_token, _changes} -> {:error, :invalid_token}
    end
  end

  defp get_invite_by_token(token) when token in [nil, ""], do: {:error, :invalid_token}

  defp get_invite_by_token(token) do
    case Repo.one(
           from i in Invite,
             where: i.token == ^token,
             where: is_nil(i.disabled_at),
             where: is_nil(i.uses_left) or i.uses_left > 0
         ) do
      nil -> {:error, :invalid_token}
      invite -> {:ok, invite}
    end
  end
end
