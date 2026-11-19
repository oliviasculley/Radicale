defmodule CalexWeb.UserSettingsHTML do
  use CalexWeb, :html

  def edit(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        Settings
        <:subtitle>{@current_user.email}</:subtitle>
      </.header>

      <section class="space-y-3">
        <h2 class="font-semibold">Email</h2>
        <.form :let={f} for={to_form(@email_changeset)} action={~p"/users/settings"} id="email-form">
          <input type="hidden" name="action" value="update_email" />
          <.input field={f[:email]} type="email" label="Email" required />
          <label class="fieldset">
            <span class="label">Current password</span>
            <input type="password" name="current_password" class="w-full input" required />
          </label>
          <.button>Change email</.button>
        </.form>
      </section>

      <section class="space-y-3">
        <h2 class="font-semibold">Password</h2>
        <.form
          :let={f}
          for={to_form(@password_changeset)}
          action={~p"/users/settings"}
          id="password-form"
        >
          <input type="hidden" name="action" value="update_password" />
          <.input field={f[:password]} type="password" label="New password" required />
          <.input
            field={f[:password_confirmation]}
            type="password"
            label="Confirm password"
            required
          />
          <label class="fieldset">
            <span class="label">Current password</span>
            <input type="password" name="current_password" class="w-full input" required />
          </label>
          <.button>Change password</.button>
        </.form>
      </section>

      <section class="space-y-3">
        <h2 class="font-semibold">Language</h2>
        <form action={~p"/users/settings"} method="post" id="locale-form">
          <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
          <input type="hidden" name="_method" value="put" />
          <input type="hidden" name="action" value="update_locale" />
          <label class="fieldset">
            <span class="label">Locale</span>
            <input type="text" name="locale" value={@locale} class="w-full input" required />
          </label>
          <.button>Save language</.button>
        </form>
      </section>

      <p>
        <.link href={~p"/users/settings/two_factor"}>Two-factor authentication</.link>
      </p>
    </Layouts.app>
    """
  end
end
