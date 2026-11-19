defmodule Calex.Accounts.TwoFactor do
  @moduledoc """
  Pure helpers for authenticator TOTP, emailed login codes, and recovery codes.
  """

  @issuer "calex"
  @email_code_digits 6
  @totp_period_seconds 30
  @recovery_code_count 10
  @recovery_code_bytes 7

  @spec generate_totp_secret() :: binary()
  def generate_totp_secret, do: NimbleTOTP.secret()

  @spec totp_uri(String.t(), binary()) :: String.t()
  def totp_uri(email, secret) do
    NimbleTOTP.otpauth_uri("#{@issuer}:#{email}", secret, issuer: @issuer)
  end

  @spec manual_entry_key(binary()) :: String.t()
  def manual_entry_key(secret) do
    secret
    |> Base.encode32(padding: false)
    |> to_charlist()
    |> Enum.chunk_every(4)
    |> Enum.join(" ")
  end

  @doc """
  Accepts the current and previous 30-second windows.

  Returns the window that matched so consuming the previous window does not
  also burn the current window.
  """
  @spec totp_used_at(binary(), String.t(), keyword()) :: {:ok, DateTime.t()} | :error
  def totp_used_at(secret, code, opts \\ []) do
    since = Keyword.get(opts, :since)
    now = Keyword.get(opts, :now, System.os_time(:second))

    cond do
      NimbleTOTP.valid?(secret, code, time: now, since: since) ->
        {:ok, usec_datetime(now)}

      NimbleTOTP.valid?(secret, code, time: now - @totp_period_seconds, since: since) ->
        {:ok, usec_datetime(now - @totp_period_seconds)}

      true ->
        :error
    end
  end

  @spec generate_email_code() :: String.t()
  def generate_email_code do
    :crypto.strong_rand_bytes(8)
    |> :binary.decode_unsigned()
    |> rem(10 ** @email_code_digits)
    |> Integer.to_string()
    |> String.pad_leading(@email_code_digits, "0")
  end

  @spec normalize_code(String.t()) :: String.t()
  def normalize_code(code) when is_binary(code), do: String.replace(code, ~r/\s/, "")

  @spec generate_recovery_codes() :: [String.t()]
  def generate_recovery_codes do
    Stream.repeatedly(&generate_recovery_code/0)
    |> Stream.uniq()
    |> Enum.take(@recovery_code_count)
  end

  @spec generate_recovery_code() :: String.t()
  def generate_recovery_code do
    raw =
      @recovery_code_bytes
      |> :crypto.strong_rand_bytes()
      |> Base.encode32(padding: false)
      |> String.downcase()
      |> binary_part(0, 10)

    "#{binary_part(raw, 0, 5)}-#{binary_part(raw, 5, 5)}"
  end

  defp usec_datetime(unix_seconds) do
    unix_seconds
    |> DateTime.from_unix!()
    |> Map.put(:microsecond, {0, 6})
  end

  @spec normalize_recovery_code(String.t()) :: String.t()
  def normalize_recovery_code(code) when is_binary(code) do
    code
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]/, "")
  end
end
