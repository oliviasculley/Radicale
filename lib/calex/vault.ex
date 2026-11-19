defmodule Calex.Vault do
  @moduledoc """
  Cloak vault used to encrypt recoverable secrets such as TOTP keys.
  """

  use Cloak.Vault, otp_app: :calex
end
