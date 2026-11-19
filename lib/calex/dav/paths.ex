defmodule Calex.Dav.Paths do
  @moduledoc """
  CalDAV and CardDAV paths. Clients discover these from the principal.
  """

  alias Calex.Calendars.Collection

  def root, do: "/dav/"
  def principal(user_id), do: "/dav/principals/#{user_id}/"
  def calendar_home(user_id), do: "/dav/calendars/#{user_id}/"
  def addressbook_home(user_id), do: "/dav/addressbooks/#{user_id}/"

  def collection(%Collection{kind: :calendar} = collection) do
    "/dav/calendars/#{collection.owner_id}/#{collection.name}/"
  end

  def collection(%Collection{kind: :addressbook} = collection) do
    "/dav/addressbooks/#{collection.owner_id}/#{collection.name}/"
  end

  def item(%Collection{} = collection, href) do
    collection(collection) <> href
  end

  def sync_token(%Collection{} = collection) do
    "http://calex/sync/#{collection.id}/#{collection.sync_token}"
  end
end
