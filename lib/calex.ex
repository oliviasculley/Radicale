defmodule Calex do
  @moduledoc """
  Calex keeps the contexts that define your domain and business logic.
  """

  def schema do
    quote do
      use Ecto.Schema
      import Ecto.Changeset

      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
      @timestamps_opts [type: :utc_datetime_usec]
    end
  end

  defmacro __using__(:schema) do
    quote do
      unquote(Calex.schema())
    end
  end
end
