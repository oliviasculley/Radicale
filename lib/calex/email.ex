defmodule Calex.Email do
  @moduledoc """
  Transactional emails for account confirmation, password reset, and 2FA.
  """

  import Swoosh.Email
  alias Calex.Accounts.User

  @spec welcome(User.t(), String.t()) :: Swoosh.Email.t()
  def welcome(%User{} = user, url) do
    user
    |> base("confirm your calex account")
    |> text_body("Confirm your calex account:\n#{url}\n")
  end

  @spec reset_password(User.t(), String.t()) :: Swoosh.Email.t()
  def reset_password(%User{} = user, url) do
    user
    |> base("reset your calex password")
    |> text_body("Reset your calex password:\n#{url}\n")
  end

  @spec update_email(User.t(), String.t()) :: Swoosh.Email.t()
  def update_email(%User{} = user, url) do
    user
    |> base("update your calex email")
    |> text_body("Confirm your new calex email:\n#{url}\n")
  end

  @spec two_factor(User.t(), String.t()) :: Swoosh.Email.t()
  def two_factor(%User{} = user, code) do
    user
    |> base("your calex two-factor code")
    |> text_body("Your calex code is #{code}\n")
  end

  defp base(%User{email: email}, subject) do
    from_address = Application.get_env(:calex, Calex.Mailer)[:email_from] || "noreply@localhost"
    from_name = Application.get_env(:calex, Calex.Mailer)[:email_name] || "calex"
    new() |> to(email) |> from({from_name, from_address}) |> subject(subject)
  end
end
