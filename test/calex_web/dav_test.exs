defmodule CalexWeb.DavTest do
  use CalexWeb.ConnCase, async: false

  test "well-known caldav and carddav redirect to the dav root" do
    for path <- ["/.well-known/caldav", "/.well-known/carddav"] do
      conn = dispatch(build_conn(), @endpoint, "GET", path)
      assert redirected_to(conn, 301) == "/dav/"
    end
  end

  test "client creates and deletes a calendar and an address book" do
    user = user_fixture()

    assert response(dav(user, "MKCALENDAR", calendar_home(user) <> "work/"), 201)

    assert response(dav(user, "PROPFIND", "/dav/"), 207) =~ "current-user-principal"
    assert response(dav(user, "PROPFIND", "/dav/"), 207) =~ "calendar-home-set"
    assert response(dav(user, "PROPFIND", "/dav/"), 207) =~ "addressbook-home-set"

    assert response(
             dav(
               user,
               "MKCOL",
               address_home(user) <> "people/",
               ~s(<CARD:addressbook xmlns:CARD="urn:ietf:params:xml:ns:carddav"/>)
             ),
             201
           )

    assert response(dav(user, "DELETE", calendar_home(user) <> "work/"), 204)
    assert response(dav(user, "GET", calendar_home(user) <> "work/missing.ics"), 404)
    assert response(dav(user, "DELETE", address_home(user) <> "people/"), 204)
  end

  test "client puts gets lists and deletes VEVENT VTODO VJOURNAL and vCard" do
    user = user_fixture()
    assert response(dav(user, "MKCALENDAR", calendar_home(user) <> "work/"), 201)

    assert response(
             dav(user, "MKCOL", address_home(user) <> "people/", "<CARD:addressbook/>"),
             201
           )

    items = [
      {calendar_home(user) <> "work/event.ics",
       vevent("event-1", "Event One", "20260301T090000Z", "20260301T100000Z")},
      {calendar_home(user) <> "work/todo.ics", vtodo("todo-1", "Todo One")},
      {calendar_home(user) <> "work/journal.ics", vjournal("journal-1", "Journal One")},
      {address_home(user) <> "people/ada.vcf", vcard("card-1", "Ada Lovelace")}
    ]

    for {path, body} <- items do
      assert response(dav(user, "PUT", path, body), 201)
      got = response(dav(user, "GET", path), 200)
      assert got =~ "UID:"

      assert got =~
               body
               |> String.split("\n")
               |> Enum.find(
                 &(String.starts_with?(&1, "SUMMARY:") || String.starts_with?(&1, "FN:"))
               )
    end

    listed =
      build_conn()
      |> put_req_header("authorization", auth(user))
      |> put_req_header("content-type", "application/xml")
      |> put_req_header("depth", "1")
      |> dispatch(@endpoint, "PROPFIND", calendar_home(user) <> "work/", "")

    assert response(listed, 207) =~ "event.ics"
    assert response(listed, 207) =~ "todo.ics"
    assert response(listed, 207) =~ "journal.ics"

    cards =
      build_conn()
      |> put_req_header("authorization", auth(user))
      |> put_req_header("content-type", "application/xml")
      |> put_req_header("depth", "1")
      |> dispatch(@endpoint, "PROPFIND", address_home(user) <> "people/", "")

    assert response(cards, 207) =~ "ada.vcf"

    multiget = """
    <C:calendar-multiget xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
      <D:prop><D:getetag/><C:calendar-data/></D:prop>
      <D:href>#{calendar_home(user)}work/todo.ics</D:href>
    </C:calendar-multiget>
    """

    assert response(dav(user, "REPORT", calendar_home(user) <> "work/", multiget), 207) =~
             "Todo One"

    query = """
    <CARD:addressbook-query xmlns:D="DAV:" xmlns:CARD="urn:ietf:params:xml:ns:carddav">
      <D:prop><CARD:address-data/></D:prop>
      <CARD:filter>
        <CARD:prop-filter name="FN"><CARD:text-match>Ada</CARD:text-match></CARD:prop-filter>
      </CARD:filter>
    </CARD:addressbook-query>
    """

    assert response(dav(user, "REPORT", address_home(user) <> "people/", query), 207) =~
             "Ada Lovelace"

    card_multiget = """
    <CARD:addressbook-multiget xmlns:D="DAV:" xmlns:CARD="urn:ietf:params:xml:ns:carddav">
      <D:prop><CARD:address-data/></D:prop>
      <D:href>#{address_home(user)}people/ada.vcf</D:href>
    </CARD:addressbook-multiget>
    """

    assert response(dav(user, "REPORT", address_home(user) <> "people/", card_multiget), 207) =~
             "Ada Lovelace"

    for {path, _body} <- items do
      assert response(dav(user, "DELETE", path), 204)
      assert response(dav(user, "GET", path), 404)
    end
  end

  test "calendar-query time range includes one event and excludes another" do
    user = user_fixture()
    assert response(dav(user, "MKCALENDAR", calendar_home(user) <> "work/"), 201)

    included = vevent("in-1", "Included Meeting", "20260101T100000Z", "20260101T110000Z")
    excluded = vevent("out-1", "Excluded Meeting", "20260201T100000Z", "20260201T110000Z")
    assert response(dav(user, "PUT", calendar_home(user) <> "work/in.ics", included), 201)
    assert response(dav(user, "PUT", calendar_home(user) <> "work/out.ics", excluded), 201)

    report = """
    <C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
      <D:prop><C:calendar-data/></D:prop>
      <C:filter>
        <C:comp-filter name="VCALENDAR">
          <C:comp-filter name="VEVENT">
            <C:time-range start="20260101T000000Z" end="20260102T000000Z"/>
          </C:comp-filter>
        </C:comp-filter>
      </C:filter>
    </C:calendar-query>
    """

    body = response(dav(user, "REPORT", calendar_home(user) <> "work/", report), 207)
    assert body =~ "Included Meeting"
    refute body =~ "Excluded Meeting"
  end

  test "sync-collection reports an etag change" do
    user = user_fixture()
    collection = calendar_home(user) <> "work/"
    assert response(dav(user, "MKCALENDAR", collection), 201)

    original = vevent("sync-1", "Before", "20260401T100000Z", "20260401T110000Z")
    first = dav(user, "PUT", collection <> "sync.ics", original)
    assert response(first, 201)
    [first_etag] = get_resp_header(first, "etag")

    initial = response(dav(user, "REPORT", collection, sync_report("")), 207)
    token = Regex.run(~r/<D:sync-token>([^<]+)<\/D:sync-token>/, initial) |> Enum.at(1)
    assert token =~ "/sync/"
    assert initial =~ first_etag |> String.replace("\"", "&quot;")

    updated = vevent("sync-1", "After", "20260401T100000Z", "20260401T120000Z")
    second = dav(user, "PUT", collection <> "sync.ics", updated)
    assert response(second, 201)
    [second_etag] = get_resp_header(second, "etag")
    assert second_etag != first_etag

    changed = response(dav(user, "REPORT", collection, sync_report(token)), 207)
    assert changed =~ second_etag |> String.replace("\"", "&quot;")
    refute changed =~ first_etag |> String.replace("\"", "&quot;")

    got = response(dav(user, "GET", collection <> "sync.ics"), 200)
    assert got =~ "UID:sync-1"
    assert got =~ "SUMMARY:After"
    assert get_resp_header(dav(user, "GET", collection <> "sync.ics"), "etag") == [second_etag]
  end

  test "a user with no grant cannot read or write another user's collection" do
    owner = user_fixture()
    other = invite_user(owner)
    collection = calendar_home(owner) <> "private/"
    assert response(dav(owner, "MKCALENDAR", collection), 201)

    body = vevent("private-1", "Private", "20260501T100000Z", "20260501T110000Z")
    assert response(dav(owner, "PUT", collection <> "private.ics", body), 201)
    assert response(dav(other, "GET", collection <> "private.ics"), 403)
    assert response(dav(other, "PUT", collection <> "private.ics", body), 403)
    assert response(dav(other, "PROPFIND", collection), 403)
    assert response(dav(other, "DELETE", collection), 403)
  end

  defp dav(user, method, path, body \\ "") do
    dav_request(user, method, path, body)
  end

  defp auth(user) do
    "Basic " <> Base.encode64("#{user.email}:#{valid_password()}")
  end

  defp calendar_home(user), do: "/dav/calendars/#{user.id}/"
  defp address_home(user), do: "/dav/addressbooks/#{user.id}/"

  defp sync_report(token) do
    """
    <D:sync-collection xmlns:D="DAV:">
      <D:sync-token>#{token}</D:sync-token>
      <D:prop><D:getetag/></D:prop>
    </D:sync-collection>
    """
  end

  defp vevent(uid, summary, start_stamp, end_stamp) do
    """
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:-//calex//EN
    BEGIN:VEVENT
    UID:#{uid}
    DTSTART:#{start_stamp}
    DTEND:#{end_stamp}
    SUMMARY:#{summary}
    END:VEVENT
    END:VCALENDAR
    """
  end

  defp vtodo(uid, summary) do
    """
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:-//calex//EN
    BEGIN:VTODO
    UID:#{uid}
    SUMMARY:#{summary}
    END:VTODO
    END:VCALENDAR
    """
  end

  defp vjournal(uid, summary) do
    """
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:-//calex//EN
    BEGIN:VJOURNAL
    UID:#{uid}
    SUMMARY:#{summary}
    END:VJOURNAL
    END:VCALENDAR
    """
  end

  defp vcard(uid, name) do
    """
    BEGIN:VCARD
    VERSION:3.0
    UID:#{uid}
    FN:#{name}
    N:Lovelace;Ada;;;
    END:VCARD
    """
  end
end
