defmodule Calex.Repo do
  use Ecto.Repo,
    otp_app: :calex,
    adapter: Ecto.Adapters.Postgres
end
