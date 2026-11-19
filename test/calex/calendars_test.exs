defmodule Calex.CalendarsTest do
  use Calex.DataCase, async: false

  alias Calex.Calendars
  alias Calex.Calendars.Collection

  test "owner grants read, write, and free-busy, and a stranger is denied" do
    owner = user_fixture()
    reader = invite_user(owner)
    stranger = invite_user(owner)
    body = event("item-1", "Planning", "20260101T100000Z", "20260101T110000Z")

    assert {:ok, %Collection{name: "work"} = collection} =
             Calendars.create_collection(owner, %{
               "name" => "work",
               "display_name" => "Work",
               "kind" => "calendar"
             })

    assert {:error, :forbidden} = Calendars.get_item(reader, collection, "item.ics")
    assert {:error, :forbidden} = Calendars.put_item(stranger, collection, "item.ics", body)

    assert {:ok, _item} = Calendars.put_item(owner, collection, "item.ics", body)
    assert {:ok, _grant} = Calendars.grant(owner, collection, reader.email, "read")
    assert Calendars.privilege(reader, collection) == :read
    assert {:error, :forbidden} = Calendars.put_item(reader, collection, "item.ics", body)

    {:ok, visible} = Calendars.get_item(reader, collection, "item.ics")
    assert visible.body =~ "SUMMARY:Planning"

    assert {:ok, _grant} = Calendars.grant(owner, collection, reader.email, "write")
    updated = event("item-1", "Planning updated", "20260101T100000Z", "20260101T110000Z")
    assert {:ok, _written} = Calendars.put_item(reader, collection, "item.ics", updated)
    {:ok, written} = Calendars.get_item(reader, collection, "item.ics")
    assert written.body =~ "Planning updated"

    assert {:ok, _grant} = Calendars.grant(owner, collection, reader.email, "free_busy")
    {:ok, busy} = Calendars.get_item(reader, collection, "item.ics")
    refute busy.body =~ "Planning"
    assert busy.body =~ "VFREEBUSY"
    assert busy.body =~ "FREEBUSY"
    assert {:error, :forbidden} = Calendars.put_item(reader, collection, "item.ics", updated)
    assert {:error, :forbidden} = Calendars.get_item(stranger, collection, "item.ics")
  end

  test "rename and delete stay with the owner" do
    owner = user_fixture()
    other = invite_user(owner)

    assert {:ok, collection} =
             Calendars.create_collection(owner, %{
               "display_name" => "Notes",
               "kind" => "addressbook"
             })

    assert {:ok, renamed} =
             Calendars.rename_collection(owner, collection, %{"display_name" => "People"})

    assert renamed.display_name == "People"

    assert {:error, :unauthorized} =
             Calendars.rename_collection(other, renamed, %{"display_name" => "Nope"})

    assert {:error, :unauthorized} = Calendars.delete_collection(other, renamed)
    assert {:ok, _deleted} = Calendars.delete_collection(owner, renamed)
    refute Repo.get(Collection, collection.id)
  end

  defp event(uid, summary, start_stamp, end_stamp) do
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
