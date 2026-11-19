defmodule CalexWeb.CollectionLiveTest do
  use CalexWeb.ConnCase, async: false

  alias Calex.Calendars.{Collection, Grant}
  alias Calex.Repo

  test "web UI grant read write and free-busy-only is enforced on the next DAV request", %{
    conn: conn
  } do
    owner = user_fixture()
    other = invite_user(owner)
    {:ok, view, _html} = live(log_in_user(conn, owner), ~p"/collections")

    view
    |> form("#new-collection", collection: %{display_name: "Shared calendar", kind: "calendar"})
    |> render_submit()

    collection = Repo.get_by!(Collection, owner_id: owner.id, display_name: "Shared calendar")

    view
    |> form("#grant-#{collection.id}", grant: %{email: other.email, privilege: "write"})
    |> render_submit()

    href = "/dav/calendars/#{owner.id}/#{collection.name}/secret.ics"
    body = vevent("secret-uid", "Secret Planning", "20260101T100000Z", "20260101T110000Z")
    assert response(dav_request(other, "PUT", href, body), 201)
    assert response(dav_request(other, "GET", href), 200) =~ "Secret Planning"

    view
    |> form("#grant-#{collection.id}", grant: %{email: other.email, privilege: "read"})
    |> render_submit()

    assert response(dav_request(other, "PUT", href, body), 403)
    assert response(dav_request(other, "GET", href), 200) =~ "Secret Planning"

    view
    |> form("#grant-#{collection.id}", grant: %{email: other.email, privilege: "free_busy"})
    |> render_submit()

    busy = response(dav_request(other, "GET", href), 200)
    refute busy =~ "Secret Planning"
    assert busy =~ "VFREEBUSY"
    assert busy =~ "FREEBUSY"

    query = """
    <C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
      <D:prop><C:calendar-data/></D:prop>
      <C:filter>
        <C:comp-filter name="VCALENDAR">
          <C:comp-filter name="VEVENT"/>
        </C:comp-filter>
      </C:filter>
    </C:calendar-query>
    """

    report =
      response(
        dav_request(other, "REPORT", "/dav/calendars/#{owner.id}/#{collection.name}/", query),
        207
      )

    refute report =~ "Secret Planning"
    assert report =~ "VFREEBUSY"

    grant = Repo.get_by!(Grant, collection_id: collection.id, user_id: other.id)
    view |> element("#revoke-#{grant.id}") |> render_click()
    assert response(dav_request(other, "GET", href), 403)
  end

  test "web UI renames and deletes a collection", %{conn: conn} do
    owner = user_fixture()
    {:ok, view, _html} = live(log_in_user(conn, owner), ~p"/collections")

    view
    |> form("#new-collection", collection: %{display_name: "Temp", kind: "addressbook"})
    |> render_submit()

    collection = Repo.get_by!(Collection, owner_id: owner.id, display_name: "Temp")

    view
    |> form("#rename-#{collection.id}", collection: %{display_name: "People"})
    |> render_submit()

    assert Repo.get!(Collection, collection.id).display_name == "People"
    view |> element("#delete-#{collection.id}") |> render_click()
    refute Repo.get(Collection, collection.id)
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
end
