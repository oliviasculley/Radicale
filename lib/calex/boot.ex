defmodule Calex.Boot do
  @moduledoc """
  What calex needs in order to start.

  Settings come from environment variables. Collections, items, and grants
  live in the database. There is no Radicale configuration path, htpasswd
  path, or rights path.
  """

  @spec required_files() :: []
  def required_files, do: []

  @spec config_sources() :: [:environment | :database]
  def config_sources, do: [:environment, :database]
end
