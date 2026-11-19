defmodule Calex.Mailer do
  @moduledoc """
  Mailer configuration and delivery.

  SMTP is used only when `SMTP_HOST`, `SMTP_USERNAME`, and `SMTP_PASSWORD`
  are all set and `DISABLE_EMAIL` is off. Otherwise mail uses the local
  adapter and the app does not send. A partial SMTP setup raises unless
  `DISABLE_EMAIL` is `true` or `1`.
  """

  use Swoosh.Mailer, otp_app: :calex

  @spec disabled_flag?(term()) :: boolean()
  def disabled_flag?(flag), do: flag in ~w(true 1)

  @spec production_email_disabled?(map()) :: boolean()
  def production_email_disabled?(env) when is_map(env) do
    disabled_flag?(env["DISABLE_EMAIL"]) or smtp_unset?(env)
  end

  @spec config_from_env(map()) :: keyword()
  def config_from_env(env) when is_map(env) do
    host = present_env(env, "SMTP_HOST")
    username = credential(env, "SMTP_USERNAME")
    password = credential(env, "SMTP_PASSWORD")

    cond do
      disabled_flag?(env["DISABLE_EMAIL"]) or smtp_unset?(env) ->
        [adapter: Swoosh.Adapters.Local] ++ from_config(env)

      is_nil(host) or is_nil(username) or is_nil(password) ->
        raise """
        SMTP_HOST, SMTP_USERNAME, and SMTP_PASSWORD must all be set, or all left unset.
        Leave them unset, or set DISABLE_EMAIL to true, to run without sending mail.
        """

      true ->
        smtp_config(env, host, username, password)
    end
  end

  defp smtp_unset?(env) do
    is_nil(present_env(env, "SMTP_HOST")) and
      is_nil(credential(env, "SMTP_USERNAME")) and
      is_nil(credential(env, "SMTP_PASSWORD"))
  end

  defp smtp_config(env, host, username, password) do
    ssl = env["SMTP_SSL"] == "true"

    [
      adapter: Swoosh.Adapters.SMTP,
      relay: host,
      port: smtp_port(env["SMTP_PORT"]),
      username: username,
      password: password,
      ssl: ssl,
      tls: tls_mode(ssl),
      auth: :always,
      no_mx_lookups: false,
      tls_options: transport_options(host)
    ]
    |> maybe_sockopts(ssl, host)
    |> Kernel.++(from_config(env))
  end

  defp smtp_port(nil), do: 587
  defp smtp_port(port), do: String.to_integer(port)

  defp from_config(env) do
    [
      email_from: env["EMAIL_FROM"] || "no-reply@#{env["HOST"]}",
      email_name: env["EMAIL_NAME"] || "calex"
    ]
  end

  defp present_env(env, key) do
    case env[key] do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _other ->
        nil
    end
  end

  defp credential(env, key) do
    case env[key] do
      value when is_binary(value) ->
        if String.trim(value) == "", do: nil, else: value

      _other ->
        nil
    end
  end

  defp tls_mode(true), do: :never
  defp tls_mode(false), do: :always

  defp maybe_sockopts(config, true, host) do
    Keyword.put(config, :sockopts, transport_options(host))
  end

  defp maybe_sockopts(config, false, _host), do: config

  defp transport_options(host) do
    [
      versions: [:"tlsv1.2", :"tlsv1.3"],
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(host),
      depth: 99,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end
end
