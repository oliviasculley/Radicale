defmodule Calex.Migrator do
  @moduledoc """
  Applies database migrations when production starts.
  """

  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    if Application.get_env(:calex, :automigrate, false) do
      Ecto.Migrator.run(Calex.Repo, :up, all: true)
    end

    {:ok, %{}}
  end
end
