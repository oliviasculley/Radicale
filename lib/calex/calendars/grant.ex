defmodule Calex.Calendars.Grant do
  @moduledoc """
  Access given by a collection owner to another user.
  """

  use Calex, :schema

  schema "grants" do
    field :privilege, Ecto.Enum, values: [:read, :write, :free_busy]

    belongs_to :collection, Calex.Calendars.Collection
    belongs_to :user, Calex.Accounts.User

    timestamps()
  end

  def changeset(collection, user, privilege) do
    %__MODULE__{}
    |> change(collection_id: collection.id, user_id: user.id, privilege: privilege)
    |> validate_required([:collection_id, :user_id, :privilege])
    |> unique_constraint([:collection_id, :user_id])
  end
end
