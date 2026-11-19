defmodule CalexWeb.UserRegistrationHTML do
  use CalexWeb, :html

  def new(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>Register</.header>
      <%= if @open do %>
        <.form :let={f} for={to_form(@changeset)} action={~p"/users/register"} id="registration-form">
          <input type="hidden" name="user[invite_token]" value={@invite_token} />
          <.input field={f[:email]} type="email" label="Email" required />
          <.input field={f[:password]} type="password" label="Password" required />
          <.button>Create account</.button>
        </.form>
      <% else %>
        <p>Registration is invite-only. Ask an administrator for an invite.</p>
      <% end %>
    </Layouts.app>
    """
  end
end
