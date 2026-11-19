defmodule Calex.Calendars do
  @moduledoc """
  Collections, items, and grants.

  The context decides whether a caller may read, write, or see only free-busy.
  The web UI and the CalDAV endpoint both call these functions.
  """

  import Ecto.Query
  alias Calex.Accounts
  alias Calex.Accounts.User
  alias Calex.Calendars.{Collection, Grant, Item, Tombstone}
  alias Calex.Dav.Paths
  alias Calex.Icalendar
  alias Calex.Repo

  def list_owned(%User{} = user) do
    Repo.all(
      from c in Collection,
        where: c.owner_id == ^user.id,
        order_by: [asc: c.display_name],
        preload: [grants: :user]
    )
  end

  def list_shared(%User{} = user) do
    Repo.all(
      from c in Collection,
        join: g in Grant,
        on: g.collection_id == c.id and g.user_id == ^user.id,
        order_by: [asc: c.display_name],
        preload: [:owner]
    )
  end

  def get_owned!(%User{} = user, id) do
    Repo.one!(
      from c in Collection,
        where: c.id == ^id and c.owner_id == ^user.id,
        preload: [grants: :user]
    )
  end

  def fetch_collection(owner_id, kind, name) do
    case Ecto.UUID.cast(owner_id) do
      {:ok, owner_id} -> Repo.get_by(Collection, owner_id: owner_id, kind: kind, name: name)
      :error -> nil
    end
  end

  def list_collections(owner_id, kind) do
    case Ecto.UUID.cast(owner_id) do
      {:ok, owner_id} ->
        Repo.all(
          from c in Collection,
            where: c.owner_id == ^owner_id and c.kind == ^kind,
            order_by: [asc: c.name]
        )

      :error ->
        []
    end
  end

  def create_collection(%User{} = user, attrs) when is_map(attrs) do
    attrs = stringify(attrs)
    kind = normalize_kind(attrs["kind"])
    display_name = String.trim(attrs["display_name"] || attrs["name"] || "")

    name =
      case attrs["name"] do
        name when is_binary(name) and name != "" -> name
        _other -> unique_name(user, kind, slug(display_name))
      end

    user
    |> Collection.create_changeset(%{
      "name" => name,
      "display_name" => display_name,
      "kind" => kind && to_string(kind)
    })
    |> Repo.insert()
  end

  def rename_collection(%User{id: id}, %Collection{owner_id: id} = collection, attrs) do
    collection
    |> Collection.rename_changeset(stringify(attrs))
    |> Repo.update()
  end

  def rename_collection(%User{}, %Collection{}, _attrs), do: {:error, :unauthorized}

  def delete_collection(%User{id: id}, %Collection{owner_id: id} = collection) do
    Repo.delete(collection)
  end

  def delete_collection(%User{}, %Collection{}), do: {:error, :unauthorized}

  def grant(%User{id: id}, %Collection{owner_id: id, kind: kind} = collection, email, privilege)
      when is_binary(email) do
    with %User{} = grantee <- Accounts.get_user_by_email(String.trim(email)),
         true <- grantee.id != id,
         {:ok, privilege} <- cast_privilege(privilege, kind) do
      collection
      |> Grant.changeset(grantee, privilege)
      |> Repo.insert(
        on_conflict: {:replace, [:privilege, :updated_at]},
        conflict_target: [:collection_id, :user_id]
      )
    else
      nil -> {:error, :not_found}
      false -> {:error, :invalid}
      {:error, reason} -> {:error, reason}
    end
  end

  def grant(%User{}, %Collection{}, _email, _privilege), do: {:error, :unauthorized}

  def revoke(%User{id: id}, %Grant{} = grant) do
    grant = Repo.preload(grant, :collection)

    if grant.collection.owner_id == id do
      Repo.delete(grant)
    else
      {:error, :unauthorized}
    end
  end

  def get_grant!(%User{} = user, id) do
    grant = Repo.get!(Grant, id) |> Repo.preload(:collection)

    if grant.collection.owner_id == user.id,
      do: grant,
      else: raise(Ecto.NoResultsError, queryable: Grant)
  end

  def privilege(%User{id: id}, %Collection{owner_id: id}), do: :owner

  def privilege(%User{} = user, %Collection{} = collection) do
    case Repo.get_by(Grant, collection_id: collection.id, user_id: user.id) do
      nil -> :none
      %Grant{privilege: privilege} -> privilege
    end
  end

  def authorize(user, collection, action) do
    if allows?(privilege(user, collection), action), do: :ok, else: {:error, :forbidden}
  end

  def put_item(%User{} = user, %Collection{} = collection, href, body) when is_binary(body) do
    with :ok <- authorize(user, collection, :write_item),
         :ok <- validate_href(href),
         {:ok, component} <- component_for(collection, body) do
      store_item(collection, href, body, component)
    end
  end

  def get_item(%User{} = user, %Collection{} = collection, href) do
    with :ok <- authorize(user, collection, :read_item) do
      case Repo.get_by(Item, collection_id: collection.id, href: href) do
        nil -> {:error, :not_found}
        item -> {:ok, represent(item, privilege(user, collection))}
      end
    end
  end

  def delete_item(%User{} = user, %Collection{} = collection, href) do
    with :ok <- authorize(user, collection, :write_item) do
      case Repo.get_by(Item, collection_id: collection.id, href: href) do
        nil ->
          {:error, :not_found}

        item ->
          Repo.transaction(fn ->
            collection = bump_sync(collection)
            Repo.delete!(item)

            %Tombstone{}
            |> Ecto.Changeset.change(
              collection_id: collection.id,
              href: href,
              sync_gen: collection.sync_token
            )
            |> Repo.insert!()

            collection
          end)
      end
    end
  end

  def list_items(%User{} = user, %Collection{} = collection) do
    with :ok <- authorize(user, collection, :read_collection) do
      priv = privilege(user, collection)

      items =
        Repo.all(from i in Item, where: i.collection_id == ^collection.id, order_by: i.href)

      {:ok, Enum.map(items, &represent(&1, priv))}
    end
  end

  def query_items(%User{} = user, %Collection{} = collection, opts) when is_list(opts) do
    with :ok <- authorize(user, collection, :report) do
      priv = privilege(user, collection)
      components = Keyword.get(opts, :components, [])
      range = Keyword.get(opts, :time_range)
      text = Keyword.get(opts, :text)
      hrefs = Keyword.get(opts, :hrefs)

      items =
        Repo.all(from i in Item, where: i.collection_id == ^collection.id, order_by: i.href)
        |> Enum.filter(&query_match?(&1, components, range, text, hrefs))
        |> Enum.map(&represent(&1, priv))

      {:ok, items}
    end
  end

  def sync_collection(%User{} = user, %Collection{} = collection, token) do
    with :ok <- authorize(user, collection, :report) do
      priv = privilege(user, collection)

      case parse_sync_token(collection, token) do
        :initial ->
          items = Repo.all(from i in Item, where: i.collection_id == ^collection.id)

          {:ok,
           %{
             token: Paths.sync_token(collection),
             changed: Enum.map(items, &represent(&1, priv)),
             deleted: []
           }}

        {:since, generation} ->
          changed =
            Repo.all(
              from i in Item,
                where: i.collection_id == ^collection.id and i.sync_gen > ^generation
            )

          deleted =
            Repo.all(
              from t in Tombstone,
                where: t.collection_id == ^collection.id and t.sync_gen > ^generation,
                select: t.href
            )

          {:ok,
           %{
             token: Paths.sync_token(collection),
             changed: Enum.map(changed, &represent(&1, priv)),
             deleted: deleted
           }}

        :invalid ->
          {:error, :invalid_sync_token}
      end
    end
  end

  defp allows?(:owner, _action), do: true

  defp allows?(:write, action)
       when action in [:read_collection, :read_item, :write_item, :report], do: true

  defp allows?(:read, action) when action in [:read_collection, :read_item, :report], do: true

  defp allows?(:free_busy, action) when action in [:read_collection, :read_item, :report],
    do: true

  defp allows?(_privilege, _action), do: false

  defp represent(%Item{} = item, :free_busy) do
    body =
      if item.component == :vevent do
        Icalendar.freebusy(item.data)
      else
        redacted(item)
      end

    %{
      href: item.href,
      etag: Icalendar.etag(body),
      body: body,
      content_type: content_type(item.component),
      component: item.component
    }
  end

  defp represent(%Item{} = item, _privilege) do
    %{
      href: item.href,
      etag: item.etag,
      body: item.data,
      content_type: content_type(item.component),
      component: item.component
    }
  end

  defp redacted(item) do
    name = item.component |> to_string() |> String.upcase()

    Enum.join(
      [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//calex//EN",
        "BEGIN:#{name}",
        "UID:#{item.uid || "hidden"}",
        "END:#{name}",
        "END:VCALENDAR"
      ],
      "\r\n"
    ) <> "\r\n"
  end

  defp content_type(:vcard), do: "text/vcard; charset=utf-8"
  defp content_type(_component), do: "text/calendar; charset=utf-8"

  defp store_item(collection, href, body, component) do
    {starts_at, ends_at} =
      if component == :vevent do
        case Icalendar.interval(body) do
          {nil, _} -> {nil, nil}
          {start, finish} -> {start, finish}
        end
      else
        {nil, nil}
      end

    Repo.transaction(fn ->
      collection = bump_sync(collection)

      attrs = %{
        collection_id: collection.id,
        href: href,
        uid: Icalendar.uid(body),
        component: component,
        data: body,
        etag: Icalendar.etag(body),
        sync_gen: collection.sync_token,
        starts_at: starts_at,
        ends_at: ends_at
      }

      case Repo.get_by(Item, collection_id: collection.id, href: href) do
        nil ->
          %Item{}
          |> Ecto.Changeset.cast(attrs, Map.keys(attrs))
          |> Ecto.Changeset.validate_required([
            :collection_id,
            :href,
            :component,
            :data,
            :etag,
            :sync_gen
          ])
          |> Repo.insert!()

        item ->
          item
          |> Ecto.Changeset.cast(attrs, [
            :uid,
            :component,
            :data,
            :etag,
            :sync_gen,
            :starts_at,
            :ends_at
          ])
          |> Repo.update!()
      end
    end)
  end

  defp bump_sync(%Collection{id: id}) do
    Repo.update_all(from(c in Collection, where: c.id == ^id), inc: [sync_token: 1])
    Repo.get!(Collection, id)
  end

  defp component_for(%Collection{kind: :addressbook}, body) do
    case Icalendar.kind(body) do
      :vcard -> {:ok, :vcard}
      _other -> {:error, :invalid}
    end
  end

  defp component_for(%Collection{kind: :calendar}, body) do
    case Icalendar.kind(body) do
      component when component in [:vevent, :vtodo, :vjournal] -> {:ok, component}
      _other -> {:error, :invalid}
    end
  end

  defp query_match?(item, components, range, text, hrefs) do
    component_name = item.component |> to_string() |> String.upcase()

    component_ok? = components == [] or component_name in components

    href_ok? = is_nil(hrefs) or item.href in hrefs or href_basename_match?(hrefs, item.href)

    range_ok? =
      case range do
        nil ->
          true

        {start, finish} ->
          item.component != :vevent or Icalendar.overlaps?(item.data, start, finish)
      end

    text_ok? =
      case text do
        nil -> true
        text -> String.contains?(String.downcase(item.data), String.downcase(text))
      end

    component_ok? and href_ok? and range_ok? and text_ok?
  end

  defp href_basename_match?(hrefs, href) do
    Enum.any?(hrefs, fn candidate ->
      candidate == href or String.ends_with?(candidate, "/" <> href)
    end)
  end

  defp parse_sync_token(_collection, nil), do: :initial
  defp parse_sync_token(_collection, ""), do: :initial

  defp parse_sync_token(collection, token) do
    case Regex.run(~r/\/sync\/([0-9a-fA-F-]{36})\/(\d+)$/, token) do
      [_, id, generation] ->
        case Integer.parse(generation) do
          {number, ""}
          when id == collection.id and number >= 0 and number <= collection.sync_token ->
            {:since, number}

          _invalid ->
            :invalid
        end

      _invalid ->
        :invalid
    end
  end

  defp cast_privilege(privilege, kind) do
    privilege =
      privilege
      |> to_string()
      |> String.trim()
      |> String.downcase()
      |> String.replace("-", "_")
      |> String.replace(" ", "_")

    cond do
      privilege in ["free_busy", "free_busy_only", "freebusy"] and kind == :addressbook ->
        {:error, :invalid}

      privilege in ["read"] ->
        {:ok, :read}

      privilege in ["write"] ->
        {:ok, :write}

      privilege in ["free_busy", "free_busy_only", "freebusy"] ->
        {:ok, :free_busy}

      true ->
        {:error, :invalid}
    end
  end

  defp normalize_kind(kind) when kind in [:calendar, :addressbook], do: kind

  defp normalize_kind(kind) when is_binary(kind) do
    case String.downcase(kind) do
      "calendar" -> :calendar
      "addressbook" -> :addressbook
      "address_book" -> :addressbook
      _other -> nil
    end
  end

  defp normalize_kind(_kind), do: nil

  defp unique_name(user, kind, name) do
    base = if name in [nil, ""], do: "collection", else: name

    Stream.iterate(0, &(&1 + 1))
    |> Enum.find_value(fn
      0 ->
        if name_free?(user, kind, base), do: base

      n ->
        candidate = "#{base}-#{n}"
        if name_free?(user, kind, candidate), do: candidate
    end)
  end

  defp name_free?(user, kind, name) do
    not Repo.exists?(
      from c in Collection,
        where: c.owner_id == ^user.id and c.kind == ^kind and c.name == ^name
    )
  end

  defp slug(name) do
    slug =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    case slug do
      "" -> "collection"
      slug -> String.slice(slug, 0, 64)
    end
  end

  defp validate_href(href) when is_binary(href) do
    if href != "" and href not in [".", ".."] and not String.contains?(href, "/") and
         byte_size(href) <= 255 do
      :ok
    else
      {:error, :invalid}
    end
  end

  defp stringify(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      pair -> pair
    end)
  end
end
