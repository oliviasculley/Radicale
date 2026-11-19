defmodule Calex.Calendars.Item do
  @moduledoc """
  One calendar component or vCard stored in a collection.
  """

  use Calex, :schema

  schema "items" do
    field :href, :string
    field :uid, :string
    field :component, Ecto.Enum, values: [:vevent, :vtodo, :vjournal, :vcard]
    field :data, :string
    field :etag, :string
    field :sync_gen, :integer, default: 0
    field :starts_at, :utc_datetime_usec
    field :ends_at, :utc_datetime_usec

    belongs_to :collection, Calex.Calendars.Collection

    timestamps()
  end
end
