defmodule Calex.Dav.Xml do
  @moduledoc """
  WebDAV XML used by CalDAV and CardDAV reports.
  """

  def report_kind(xml) when is_binary(xml) do
    cond do
      String.contains?(xml, "calendar-query") -> :calendar_query
      String.contains?(xml, "calendar-multiget") -> :calendar_multiget
      String.contains?(xml, "addressbook-query") -> :addressbook_query
      String.contains?(xml, "addressbook-multiget") -> :addressbook_multiget
      String.contains?(xml, "sync-collection") -> :sync_collection
      true -> :unknown
    end
  end

  def comp_filters(xml) when is_binary(xml) do
    Regex.scan(~r/comp-filter\b[^>]*\bname="([^"]+)"/i, xml)
    |> Enum.map(fn [_, name] -> String.upcase(name) end)
    |> Enum.reject(&(&1 == "VCALENDAR"))
  end

  def time_range(xml) when is_binary(xml) do
    case Regex.run(~r/<[^>]*time-range\b([^>]*)\/?>/i, xml) do
      [_, attrs] ->
        with start when is_binary(start) <- attr(attrs, "start"),
             finish when is_binary(finish) <- attr(attrs, "end"),
             %DateTime{} = range_start <- Calex.Icalendar.parse_utc(start),
             %DateTime{} = range_end <- Calex.Icalendar.parse_utc(finish) do
          {:ok, range_start, range_end}
        else
          _invalid -> :invalid
        end

      _missing ->
        :none
    end
  end

  def text_match(xml) when is_binary(xml) do
    case Regex.run(~r/<[^>]*text-match\b[^>]*>([^<]*)<\/[^>]*text-match>/i, xml) do
      [_, text] -> String.trim(text)
      _missing -> nil
    end
  end

  def hrefs(xml) when is_binary(xml) do
    Regex.scan(~r/<[^>]*\bhref\b[^>]*>([^<]+)<\/[^>]*href>/i, xml)
    |> Enum.map(fn [_, href] -> href |> String.trim() |> URI.decode() end)
  end

  def sync_token(xml) when is_binary(xml) do
    case Regex.run(~r/<[^>]*sync-token\b[^>]*>([^<]*)<\/[^>]*sync-token>/i, xml) do
      [_, token] -> String.trim(token)
      _missing -> nil
    end
  end

  def display_name(xml) when is_binary(xml) do
    case Regex.run(~r/<[^>]*displayname\b[^>]*>([^<]*)<\/[^>]*displayname>/i, xml) do
      [_, name] ->
        name
        |> String.trim()
        |> String.replace("&amp;", "&")
        |> String.replace("&lt;", "<")
        |> String.replace("&gt;", ">")

      _missing ->
        nil
    end
  end

  def multistatus(responses, extra \\ []) do
    body =
      [
        ~s(<?xml version="1.0" encoding="UTF-8"?>),
        ~s(<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav" xmlns:CARD="urn:ietf:params:xml:ns:carddav">),
        Enum.join(responses, ""),
        Enum.join(extra, ""),
        "</D:multistatus>"
      ]
      |> IO.iodata_to_binary()

    body
  end

  def response(href, props) when is_list(props) do
    """
    <D:response><D:href>#{escape(href)}</D:href><D:propstat><D:prop>#{Enum.join(props, "")}</D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>
    """
  end

  def response_status(href, status) do
    """
    <D:response><D:href>#{escape(href)}</D:href><D:status>HTTP/1.1 #{status}</D:status></D:response>
    """
  end

  def sync_token_element(token) do
    "<D:sync-token>#{escape(token)}</D:sync-token>"
  end

  def escape(nil), do: ""

  def escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp attr(attrs, name) do
    case Regex.run(~r/\b#{name}="([^"]*)"/, attrs) do
      [_, value] -> value
      _missing -> nil
    end
  end
end
