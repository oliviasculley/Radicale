defmodule Calex.Encrypted.Binary do
  @moduledoc """
  Ecto type that encrypts binary values with `Calex.Vault`.
  """

  use Cloak.Ecto.Binary, vault: Calex.Vault
end
