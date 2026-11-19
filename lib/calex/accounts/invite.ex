defmodule Calex.Accounts.Invite do
  @moduledoc """
  An invite created by an admin. It can be disabled and can run out of uses.
  """

  use Calex, :schema

  schema "invites" do
    field :name, :string
    field :token, :string
    field :uses_left, :integer
    field :disabled_at, :utc_datetime_usec

    belongs_to :created_by, Calex.Accounts.User
    has_many :users, Calex.Accounts.User

    timestamps()
  end

  def create_changeset(%Calex.Accounts.User{id: user_id}, token, attrs) do
    %__MODULE__{}
    |> change(token: token, created_by_id: user_id)
    |> cast(attrs, [:name, :uses_left, :disabled_at])
    |> validate_required([:name, :token, :created_by_id])
    |> validate_number(:uses_left, greater_than_or_equal_to: 0)
  end
end
