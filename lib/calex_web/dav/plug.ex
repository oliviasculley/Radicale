defmodule CalexWeb.Dav.Plug do
  @moduledoc """
  CalDAV and CardDAV endpoint.

  Browser sessions are not used. Clients authenticate with HTTP Basic and the
  account email and password. Two-factor prompts stay on the website login.
  """

  @behaviour Plug
  import Plug.Conn
  alias Calex.Accounts
  alias Calex.Accounts.User
  alias Calex.Calendars
  alias Calex.Calendars.Collection
  alias Calex.Dav.{Paths, Xml}

  def init(opts), do: opts

  def call(%Plug.Conn{request_path: path} = conn, _opts) do
    cond do
      well_known?(path) -> redirect_well_known(conn)
      dav_path?(path) -> handle(conn)
      true -> conn
    end
  end

  defp well_known?(path) do
    trimmed = String.trim_trailing(path, "/")

    String.ends_with?(trimmed, "/.well-known/caldav") or
      String.ends_with?(trimmed, "/.well-known/carddav")
  end

  defp dav_path?(path), do: path == "/dav" or String.starts_with?(path, "/dav/")

  defp redirect_well_known(conn) do
    conn
    |> put_resp_header("location", Paths.root())
    |> send_resp(301, "")
    |> halt()
  end

  defp handle(conn) do
    if conn.method == "OPTIONS" do
      options(conn)
    else
      case authenticate(conn) do
        {:ok, user} -> dispatch(conn, user)
        :error -> unauthorized(conn)
      end
    end
  end

  defp authenticate(conn) do
    with ["Basic " <> encoded] <- get_req_header(conn, "authorization"),
         {:ok, decoded} <- Base.decode64(encoded),
         [email, password] <- String.split(decoded, ":", parts: 2),
         %User{} = user <- Accounts.get_user_by_email_and_password(email, password),
         true <- not is_nil(user.confirmed_at) or Accounts.email_disabled?() do
      {:ok, user}
    else
      _invalid -> :error
    end
  end

  defp dispatch(conn, user) do
    segments = conn.request_path |> URI.decode() |> String.split("/", trim: true)

    case segments do
      ["dav"] ->
        root(conn, user)

      ["dav", "principals", user_id] ->
        principal(conn, user, user_id)

      ["dav", "calendars", user_id] ->
        home(conn, user, user_id, :calendar)

      ["dav", "addressbooks", user_id] ->
        home(conn, user, user_id, :addressbook)

      ["dav", "calendars", user_id, name] ->
        collection(conn, user, user_id, :calendar, name)

      ["dav", "addressbooks", user_id, name] ->
        collection(conn, user, user_id, :addressbook, name)

      ["dav", "calendars", user_id, name, href] ->
        item(conn, user, user_id, :calendar, name, href)

      ["dav", "addressbooks", user_id, name, href] ->
        item(conn, user, user_id, :addressbook, name, href)

      _other ->
        text(conn, 404, "not found")
    end
  end

  defp root(conn, user) do
    case conn.method do
      "PROPFIND" ->
        xml(
          conn,
          207,
          Xml.multistatus([
            Xml.response(Paths.root(), [
              principal_props(user),
              home_props(user),
              ~s(<D:resourcetype><D:collection/></D:resourcetype>)
            ])
          ])
        )

      _method ->
        text(conn, 405, "method not allowed")
    end
  end

  defp principal(conn, user, user_id) do
    if user_id == user.id do
      case conn.method do
        "PROPFIND" ->
          xml(
            conn,
            207,
            Xml.multistatus([
              Xml.response(Paths.principal(user.id), [
                ~s(<D:displayname>#{Xml.escape(user.email)}</D:displayname>),
                ~s(<D:resourcetype><D:principal/></D:resourcetype>),
                principal_props(user),
                home_props(user)
              ])
            ])
          )

        _method ->
          text(conn, 405, "method not allowed")
      end
    else
      text(conn, 403, "forbidden")
    end
  end

  defp home(conn, user, user_id, kind) do
    if user_id == user.id do
      case conn.method do
        "PROPFIND" ->
          href = home_href(user.id, kind)

          children =
            if depth(conn) in ["1", "infinity"], do: home_children(user.id, kind), else: []

          xml(
            conn,
            207,
            Xml.multistatus([
              Xml.response(href, [
                ~s(<D:resourcetype><D:collection/></D:resourcetype>),
                principal_props(user),
                home_props(user)
              ])
              | children
            ])
          )

        _method ->
          text(conn, 405, "method not allowed")
      end
    else
      text(conn, 403, "forbidden")
    end
  end

  defp collection(conn, user, owner_id, kind, name) do
    case Calendars.fetch_collection(owner_id, kind, name) do
      nil ->
        if conn.method in ["MKCALENDAR", "MKCOL"] and owner_id == user.id do
          make_collection(conn, user, kind, name)
        else
          text(conn, 404, "not found")
        end

      %Collection{} = collection ->
        case conn.method do
          "PROPFIND" -> propfind_collection(conn, user, collection)
          "REPORT" -> report(conn, user, collection)
          "GET" -> text(conn, 405, "method not allowed")
          "DELETE" -> delete_collection(conn, user, collection)
          "PROPPATCH" -> proppatch(conn, user, collection)
          "MKCALENDAR" -> text(conn, 405, "already exists")
          "MKCOL" -> text(conn, 405, "already exists")
          _method -> text(conn, 405, "method not allowed")
        end
    end
  end

  defp item(conn, user, owner_id, kind, name, href) do
    case Calendars.fetch_collection(owner_id, kind, name) do
      nil ->
        text(conn, 404, "not found")

      collection ->
        case conn.method do
          "GET" -> get_item(conn, user, collection, href)
          "PUT" -> put_item(conn, user, collection, href)
          "DELETE" -> delete_item(conn, user, collection, href)
          "HEAD" -> get_item(conn, user, collection, href)
          "PROPFIND" -> propfind_item(conn, user, collection, href)
          _method -> text(conn, 405, "method not allowed")
        end
    end
  end

  defp make_collection(conn, user, kind, name) do
    {:ok, body, conn} = read_body(conn)
    kind = collection_kind(conn.method, kind, body)
    display_name = Xml.display_name(body) || name

    case Calendars.create_collection(user, %{
           "name" => name,
           "display_name" => display_name,
           "kind" => kind
         }) do
      {:ok, _collection} -> text(conn, 201, "")
      {:error, changeset} -> text(conn, 400, inspect(changeset.errors))
    end
  end

  defp collection_kind("MKCALENDAR", _path_kind, _body), do: :calendar

  defp collection_kind("MKCOL", path_kind, body) do
    cond do
      String.contains?(body, "addressbook") -> :addressbook
      String.contains?(body, "calendar") -> :calendar
      true -> path_kind
    end
  end

  defp delete_collection(conn, user, collection) do
    case Calendars.delete_collection(user, collection) do
      {:ok, _collection} -> text(conn, 204, "")
      {:error, :unauthorized} -> text(conn, 403, "forbidden")
      {:error, _reason} -> text(conn, 403, "forbidden")
    end
  end

  defp proppatch(conn, user, collection) do
    {:ok, body, conn} = read_body(conn)

    case Xml.display_name(body) do
      nil ->
        text(conn, 403, "forbidden")

      display_name ->
        case Calendars.rename_collection(user, collection, %{"display_name" => display_name}) do
          {:ok, collection} ->
            xml(
              conn,
              207,
              Xml.multistatus([
                Xml.response(Paths.collection(collection), [displayname(collection)])
              ])
            )

          {:error, :unauthorized} ->
            text(conn, 403, "forbidden")

          {:error, _changeset} ->
            text(conn, 400, "bad request")
        end
    end
  end

  defp propfind_collection(conn, user, collection) do
    case Calendars.authorize(user, collection, :read_collection) do
      {:error, :forbidden} ->
        text(conn, 403, "forbidden")

      :ok ->
        children =
          if depth(conn) in ["1", "infinity"] do
            {:ok, items} = Calendars.list_items(user, collection)

            Enum.map(items, fn item ->
              Xml.response(Paths.item(collection, item.href), item_props(item))
            end)
          else
            []
          end

        xml(
          conn,
          207,
          Xml.multistatus([
            Xml.response(Paths.collection(collection), collection_props(user, collection))
            | children
          ])
        )
    end
  end

  defp propfind_item(conn, user, collection, href) do
    case Calendars.get_item(user, collection, href) do
      {:ok, item} ->
        xml(
          conn,
          207,
          Xml.multistatus([Xml.response(Paths.item(collection, href), item_props(item))])
        )

      {:error, :not_found} ->
        text(conn, 404, "not found")

      {:error, :forbidden} ->
        text(conn, 403, "forbidden")
    end
  end

  defp get_item(conn, user, collection, href) do
    case Calendars.get_item(user, collection, href) do
      {:ok, item} ->
        conn
        |> put_resp_content_type(item.content_type, nil)
        |> put_resp_header("etag", item.etag)
        |> dav_headers()
        |> send_resp(200, item.body)
        |> halt()

      {:error, :not_found} ->
        text(conn, 404, "not found")

      {:error, :forbidden} ->
        text(conn, 403, "forbidden")
    end
  end

  defp put_item(conn, user, collection, href) do
    {:ok, body, conn} = read_body(conn)

    case Calendars.put_item(user, collection, href, body) do
      {:ok, item} ->
        conn
        |> put_resp_header("etag", item.etag)
        |> dav_headers()
        |> send_resp(201, "")
        |> halt()

      {:error, :forbidden} ->
        text(conn, 403, "forbidden")

      {:error, :invalid} ->
        text(conn, 415, "unsupported media")

      {:error, _reason} ->
        text(conn, 400, "bad request")
    end
  end

  defp delete_item(conn, user, collection, href) do
    case Calendars.delete_item(user, collection, href) do
      {:ok, _collection} -> text(conn, 204, "")
      {:error, :not_found} -> text(conn, 404, "not found")
      {:error, :forbidden} -> text(conn, 403, "forbidden")
    end
  end

  defp report(conn, user, collection) do
    {:ok, body, conn} = read_body(conn)

    case Xml.report_kind(body) do
      :sync_collection ->
        sync_report(conn, user, collection, body)

      kind
      when kind in [
             :calendar_query,
             :calendar_multiget,
             :addressbook_query,
             :addressbook_multiget
           ] ->
        query_report(conn, user, collection, body, kind)

      :unknown ->
        text(conn, 400, "unknown report")
    end
  end

  defp query_report(conn, user, collection, body, kind) do
    opts =
      []
      |> maybe_components(body, kind)
      |> maybe_time_range(body)
      |> maybe_text(body)
      |> maybe_hrefs(body, kind)

    case opts do
      {:error, :invalid} ->
        text(conn, 400, "bad request")

      opts ->
        case Calendars.query_items(user, collection, opts) do
          {:ok, items} ->
            responses =
              Enum.map(items, fn item ->
                Xml.response(Paths.item(collection, item.href), report_props(item, kind))
              end)

            xml(conn, 207, Xml.multistatus(responses))

          {:error, :forbidden} ->
            text(conn, 403, "forbidden")
        end
    end
  end

  defp sync_report(conn, user, collection, body) do
    case Calendars.sync_collection(user, collection, Xml.sync_token(body)) do
      {:ok, %{token: token, changed: changed, deleted: deleted}} ->
        responses =
          Enum.map(changed, fn item ->
            Xml.response(Paths.item(collection, item.href), [etag_prop(item.etag)])
          end) ++
            Enum.map(deleted, fn href ->
              Xml.response_status(Paths.item(collection, href), "404 Not Found")
            end)

        xml(conn, 207, Xml.multistatus(responses, [Xml.sync_token_element(token)]))

      {:error, :invalid_sync_token} ->
        text(conn, 409, "invalid sync token")

      {:error, :forbidden} ->
        text(conn, 403, "forbidden")
    end
  end

  defp maybe_components(opts, body, kind) when kind in [:calendar_query, :calendar_multiget] do
    case Xml.comp_filters(body) do
      [] -> opts
      filters -> Keyword.put(opts, :components, filters)
    end
  end

  defp maybe_components(opts, _body, _kind), do: opts

  defp maybe_time_range(opts, body) do
    case Xml.time_range(body) do
      :none -> opts
      :invalid -> {:error, :invalid}
      {:ok, start, finish} -> Keyword.put(opts, :time_range, {start, finish})
    end
  end

  defp maybe_text({:error, _} = error, _body), do: error

  defp maybe_text(opts, body) do
    case Xml.text_match(body) do
      nil -> opts
      text -> Keyword.put(opts, :text, text)
    end
  end

  defp maybe_hrefs({:error, _} = error, _body, _kind), do: error

  defp maybe_hrefs(opts, body, kind) when kind in [:calendar_multiget, :addressbook_multiget] do
    Keyword.put(opts, :hrefs, Xml.hrefs(body) |> Enum.map(&href_name/1))
  end

  defp maybe_hrefs(opts, _body, _kind), do: opts

  defp href_name(href) do
    href |> String.trim_trailing("/") |> String.split("/") |> List.last()
  end

  defp home_href(user_id, :calendar), do: Paths.calendar_home(user_id)
  defp home_href(user_id, :addressbook), do: Paths.addressbook_home(user_id)

  defp home_children(user_id, kind) do
    Enum.map(Calendars.list_collections(user_id, kind), fn collection ->
      Xml.response(Paths.collection(collection), [
        displayname(collection),
        resource_type(collection),
        ~s(<D:sync-token>#{Xml.escape(Paths.sync_token(collection))}</D:sync-token>)
      ])
    end)
  end

  defp collection_props(user, collection) do
    [
      displayname(collection),
      resource_type(collection),
      ~s(<D:sync-token>#{Xml.escape(Paths.sync_token(collection))}</D:sync-token>),
      ~s(<D:getctag>#{Xml.escape(Paths.sync_token(collection))}</D:getctag>),
      privilege_set(Calendars.privilege(user, collection)),
      supported_reports(collection),
      component_set(collection),
      principal_props(user),
      home_props(user)
    ]
  end

  defp item_props(item) do
    [
      etag_prop(item.etag),
      ~s(<D:getcontenttype>#{Xml.escape(item.content_type)}</D:getcontenttype>),
      ~s(<D:resourcetype/>)
    ]
  end

  defp report_props(item, kind) when kind in [:addressbook_query, :addressbook_multiget] do
    [etag_prop(item.etag), "<CARD:address-data>#{Xml.escape(item.body)}</CARD:address-data>"]
  end

  defp report_props(item, _kind) do
    [etag_prop(item.etag), "<C:calendar-data>#{Xml.escape(item.body)}</C:calendar-data>"]
  end

  defp etag_prop(etag), do: "<D:getetag>#{Xml.escape(etag)}</D:getetag>"

  defp displayname(collection),
    do: "<D:displayname>#{Xml.escape(collection.display_name)}</D:displayname>"

  defp resource_type(%Collection{kind: :calendar}) do
    "<D:resourcetype><D:collection/><C:calendar/></D:resourcetype>"
  end

  defp resource_type(%Collection{kind: :addressbook}) do
    "<D:resourcetype><D:collection/><CARD:addressbook/></D:resourcetype>"
  end

  defp principal_props(user) do
    href = Paths.principal(user.id)

    "<D:current-user-principal><D:href>#{href}</D:href></D:current-user-principal><D:principal-URL><D:href>#{href}</D:href></D:principal-URL>"
  end

  defp home_props(user) do
    "<C:calendar-home-set><D:href>#{Paths.calendar_home(user.id)}</D:href></C:calendar-home-set><CARD:addressbook-home-set><D:href>#{Paths.addressbook_home(user.id)}</D:href></CARD:addressbook-home-set>"
  end

  defp privilege_set(:owner), do: privilege_xml(["read", "write"])
  defp privilege_set(:write), do: privilege_xml(["read", "write"])
  defp privilege_set(:read), do: privilege_xml(["read"])

  defp privilege_set(:free_busy),
    do:
      "<D:current-user-privilege-set><D:privilege><C:read-free-busy/></D:privilege></D:current-user-privilege-set>"

  defp privilege_set(:none), do: "<D:current-user-privilege-set/>"

  defp privilege_xml(names) do
    inner = Enum.map_join(names, "", fn name -> "<D:privilege><D:#{name}/></D:privilege>" end)
    "<D:current-user-privilege-set>#{inner}</D:current-user-privilege-set>"
  end

  defp supported_reports(%Collection{kind: :addressbook}) do
    "<D:supported-report-set><D:supported-report><D:report><CARD:addressbook-query/></D:report></D:supported-report><D:supported-report><D:report><CARD:addressbook-multiget/></D:report></D:supported-report><D:supported-report><D:report><D:sync-collection/></D:report></D:supported-report></D:supported-report-set>"
  end

  defp supported_reports(%Collection{kind: :calendar}) do
    "<D:supported-report-set><D:supported-report><D:report><C:calendar-query/></D:report></D:supported-report><D:supported-report><D:report><C:calendar-multiget/></D:report></D:supported-report><D:supported-report><D:report><D:sync-collection/></D:report></D:supported-report></D:supported-report-set>"
  end

  defp component_set(%Collection{kind: :calendar}) do
    "<C:supported-calendar-component-set><C:comp name=\"VEVENT\"/><C:comp name=\"VTODO\"/><C:comp name=\"VJOURNAL\"/></C:supported-calendar-component-set>"
  end

  defp component_set(%Collection{}), do: ""

  defp options(conn) do
    conn
    |> put_resp_header(
      "allow",
      "OPTIONS, GET, HEAD, PUT, DELETE, PROPFIND, PROPPATCH, REPORT, MKCALENDAR, MKCOL"
    )
    |> dav_headers()
    |> send_resp(200, "")
    |> halt()
  end

  defp depth(conn) do
    conn |> get_req_header("depth") |> List.first() || "0"
  end

  defp xml(conn, status, body) do
    conn
    |> put_resp_content_type("application/xml", "utf-8")
    |> dav_headers()
    |> send_resp(status, body)
    |> halt()
  end

  defp text(conn, status, body) do
    conn
    |> dav_headers()
    |> send_resp(status, body)
    |> halt()
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_header("www-authenticate", ~s(Basic realm="calex"))
    |> dav_headers()
    |> send_resp(401, "unauthorized")
    |> halt()
  end

  defp dav_headers(conn) do
    put_resp_header(conn, "dav", "1, 3, extended-mkcol, calendar-access, addressbook")
  end
end
