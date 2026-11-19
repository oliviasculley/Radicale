defmodule Calex.Calendars.Collection do
  @moduledoc """
  A calendar or address book owned by one user.
  """

  use Calex, :schema

  schema "collections" do
    field :name, :string
    field :display_name, :string
    field :kind, Ecto.Enum, values: [:calendar, :addressbook]
    field :sync_token, :integer, default: 0

    belongs_to :owner, Calex.Accounts.User
    has_many :items, Calex.Calendars.Item
    has_many :grants, Calex.Calendars.Grant

    timestamps()
  end

  def create_changeset(owner, attrs) do
    %__MODULE__{}
    |> cast(attrs, [:name, :display_name, :kind])
    |> put_change(:owner_id, owner.id)
    |> validate_required([:name, :display_name, :kind, :owner_id])
    |> validate_format(:name, ~r/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/)
    |> unique_constraint([:owner_id, :kind, :name])
  end

  def rename_changeset(collection, attrs) do
    collection
    |> cast(attrs, [:display_name])
    |> validate_required([:display_name])
    |> validate_length(:display_name, min: 1, max: 120)
  end
end
