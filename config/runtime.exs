import Config

# Runtime configuration comes from environment variables and the database.
# calex does not read an INI file, an htpasswd file, or a rights file.

if System.get_env("PHX_SERVER") do
  config :calex, CalexWeb.Endpoint, server: true
end

config :calex, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

host =
  System.get_env("HOST") ||
    if config_env() == :test do
      "localhost"
    else
      raise "No hostname set! Must be the domain and tld like `calex.shibao.dev`."
    end

maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

if config_env() == :test do
  config :calex, Calex.Repo,
    url:
      System.get_env(
        "TEST_DATABASE_URL",
        "ecto://postgres:postgres@127.0.0.1/calex_test#{System.get_env("MIX_TEST_PARTITION")}"
      ),
    socket_options: maybe_ipv6
else
  config :calex, Calex.Repo,
    url: System.get_env("DATABASE_URL", "ecto://postgres:postgres@127.0.0.1/calex_dev"),
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "10")),
    socket_options: maybe_ipv6
end

if config_env() != :test do
  config :calex, CalexWeb.Endpoint,
    url: [scheme: "https", host: host, port: 443],
    http: [
      ip: {0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT", "4000"))
    ]
end

if config_env() in [:dev, :prod] do
  config :calex, Calex.Accounts, registration: System.get_env("REGISTRATION", "invite")

  if Calex.Mailer.disabled_flag?(System.get_env("DISABLE_EMAIL")) do
    config :calex, :email_disabled, true
  end
end

if config_env() == :prod do
  cloak_key =
    System.get_env("CLOAK_KEY") ||
      raise """
      environment variable CLOAK_KEY is missing.
      You can generate one with: /app/priv/cloak_key.sh
      """

  cloak_key =
    case Base.decode64(cloak_key) do
      {:ok, key} when byte_size(key) == 32 -> key
      _invalid -> raise "CLOAK_KEY must be 32 random bytes, base64-encoded"
    end

  config :calex, Calex.Vault,
    ciphers: [default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: cloak_key}]

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by running: priv/random.sh
      """

  config :calex, CalexWeb.Endpoint, secret_key_base: secret_key_base
  config :calex, :automigrate, true
  config :calex, :email_disabled, Calex.Mailer.production_email_disabled?(System.get_env())
  config :calex, Calex.Mailer, Calex.Mailer.config_from_env(System.get_env())
end
