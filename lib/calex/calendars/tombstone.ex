defmodule Calex.Calendars.Tombstone do
  @moduledoc """
  A deleted item reported by a later sync-collection.
  """

  use Calex, :schema

  schema "tombstones" do
    field :href, :string
    field :sync_gen, :integer

    belongs_to :collection, Calex.Calendars.Collection

    timestamps(updated_at: false)
  end
end
