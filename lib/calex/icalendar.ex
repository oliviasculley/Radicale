defmodule Calex.Icalendar do
  @moduledoc """
  iCalendar and vCard reading used by CalDAV and CardDAV.

  Parsing ignores `VTIMEZONE` so a timezone block cannot be mistaken for an event.
  """

  @calendar_components ~w(VEVENT VTODO VJOURNAL VCARD)
  @detail_components ~w(VEVENT VTODO VJOURNAL)

  def kind(text) when is_binary(text) do
    case Enum.find(components(text), &(&1 in @calendar_components)) do
      "VEVENT" -> :vevent
      "VTODO" -> :vtodo
      "VJOURNAL" -> :vjournal
      "VCARD" -> :vcard
      _other -> :unknown
    end
  end

  def uid(text) when is_binary(text) do
    case property(text, "UID", @calendar_components) do
      nil -> nil
      value -> unescape(value)
    end
  end

  def summary(text) when is_binary(text) do
    case property(text, "SUMMARY", @detail_components) do
      nil -> nil
      value -> unescape(value)
    end
  end

  def interval(text) when is_binary(text) do
    case property_parts(text, "DTSTART", @detail_components) do
      nil ->
        {nil, nil}

      {params, value} ->
        start = parse_bound(params, value)

        finish =
          case property_parts(text, "DTEND", @detail_components) do
            nil ->
              duration_end(start, property(text, "DURATION", @detail_components)) ||
                default_end(start, params)

            {end_params, end_value} ->
              parse_bound(end_params, end_value)
          end

        {normalize_start(start), normalize_start(finish)}
    end
  end

  def overlaps?(text, range_start, range_end) do
    case interval(text) do
      {nil, _} ->
        false

      {start, finish} ->
        DateTime.compare(start, range_end) == :lt and DateTime.compare(finish, range_start) == :gt
    end
  end

  def freebusy(text) when is_binary(text) do
    {start, finish} = interval(text)
    uid = uid(text) || "busy"
    start_text = start && format_utc(start)
    finish_text = finish && format_utc(finish)

    lines =
      [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//calex//EN",
        "BEGIN:VFREEBUSY",
        "UID:#{uid}",
        start_text && "DTSTART:#{start_text}",
        finish_text && "DTEND:#{finish_text}",
        start_text && finish_text && "FREEBUSY:#{start_text}/#{finish_text}",
        "END:VFREEBUSY",
        "END:VCALENDAR"
      ]
      |> Enum.reject(&is_nil/1)

    Enum.join(lines, "\r\n") <> "\r\n"
  end

  def etag(data) when is_binary(data) do
    hash = :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
    ~s("#{hash}")
  end

  def parse_utc(value) when is_binary(value) do
    cond do
      Regex.match?(~r/^\d{8}T\d{6}Z?$/, value) ->
        parse_datetime(value)

      Regex.match?(~r/^\d{8}$/, value) ->
        case parse_date(value) do
          nil -> nil
          date -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
        end

      true ->
        nil
    end
  end

  defp components(text) do
    text
    |> lines()
    |> Enum.flat_map(fn line ->
      case Regex.run(~r/^BEGIN:(.+)$/, line) do
        [_, name] -> [String.upcase(String.trim(name))]
        _ -> []
      end
    end)
  end

  defp property(text, name, allowed),
    do: property_parts(text, name, allowed) && elem(property_parts(text, name, allowed), 1)

  defp property_parts(text, name, allowed) do
    {_found, result} =
      Enum.reduce(lines(text), {[], nil}, fn line, {stack, found} ->
        cond do
          found ->
            {stack, found}

          String.starts_with?(line, "BEGIN:") ->
            {[String.upcase(String.trim_leading(line, "BEGIN:")) | stack], nil}

          String.starts_with?(line, "END:") ->
            {tl_stack(stack), nil}

          true ->
            parent = List.first(stack)

            if parent in allowed and String.starts_with?(line, name) do
              case Regex.run(~r/^#{name}((?:;[^:]*)?):(.*)$/, line) do
                [_, params, value] -> {stack, {params, String.trim(value)}}
                _ -> {stack, found}
              end
            else
              {stack, found}
            end
        end
      end)

    result
  end

  defp lines(text) do
    text
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> String.replace(~r/\n[ \t]/, "")
    |> String.split("\n", trim: true)
  end

  defp tl_stack([]), do: []
  defp tl_stack([_head | tail]), do: tail

  defp parse_bound(params, value) do
    cond do
      String.contains?(params, "VALUE=DATE") or Regex.match?(~r/^\d{8}$/, value) ->
        case parse_date(value) do
          nil -> nil
          date -> {:date, date}
        end

      true ->
        case parse_datetime(value) do
          nil -> nil
          datetime -> {:utc, datetime}
        end
    end
  end

  defp normalize_start(nil), do: nil
  defp normalize_start(%DateTime{} = datetime), do: datetime
  defp normalize_start({:utc, datetime}), do: datetime
  defp normalize_start({:date, date}), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")

  defp default_end(nil, _params), do: nil

  defp default_end({:date, date}, _params) do
    DateTime.new!(Date.add(date, 1), ~T[00:00:00], "Etc/UTC")
  end

  defp default_end({:utc, datetime}, params) do
    if String.contains?(params, "VALUE=DATE") do
      DateTime.add(datetime, 86_400, :second)
    else
      datetime
    end
  end

  defp duration_end(nil, _duration), do: nil
  defp duration_end(_start, nil), do: nil

  defp duration_end(start, duration) do
    seconds = duration_seconds(duration)
    base = normalize_start(start)
    if base && seconds, do: DateTime.add(base, seconds, :second), else: nil
  end

  defp duration_seconds(duration) do
    case Regex.run(~r/^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/, duration) do
      [_, days, hours, minutes, seconds] ->
        to_int(days) * 86_400 + to_int(hours) * 3600 + to_int(minutes) * 60 + to_int(seconds)

      _ ->
        nil
    end
  end

  defp parse_datetime(value) do
    case Regex.run(~r/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z?$/, value) do
      [_, year, month, day, hour, minute, second] ->
        DateTime.new!(
          Date.new!(to_int(year), to_int(month), to_int(day)),
          Time.new!(to_int(hour), to_int(minute), to_int(second), 0),
          "Etc/UTC"
        )

      _ ->
        nil
    end
  end

  defp parse_date(value) do
    case Regex.run(~r/^(\d{4})(\d{2})(\d{2})$/, value) do
      [_, year, month, day] -> Date.new!(to_int(year), to_int(month), to_int(day))
      _ -> nil
    end
  end

  defp format_utc(%DateTime{} = datetime) do
    datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> Calendar.strftime("%Y%m%dT%H%M%SZ")
  end

  defp unescape(value) do
    value
    |> String.replace(~r/\\n/i, "\n")
    |> String.replace(~r/\\,/, ",")
    |> String.replace(~r/\\;/, ";")
    |> String.replace("\\\\", "\\")
  end

  defp to_int(nil), do: 0
  defp to_int(""), do: 0
  defp to_int(value), do: String.to_integer(value)
end
