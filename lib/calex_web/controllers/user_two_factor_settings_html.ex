defmodule CalexWeb.UserTwoFactorSettingsHTML do
  use CalexWeb, :html

  def edit(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>Two-factor authentication</.header>
      <p :if={@error_message} class="text-error">{@error_message}</p>

      <%= if @current_user.two_factor_method do %>
        <p>
          Method: {@current_user.two_factor_method}. Recovery codes left: {@recovery_count}.
        </p>
        <ul :if={@recovery_codes} id="recovery-codes">
          <li :for={code <- @recovery_codes}><code>{code}</code></li>
        </ul>
        <form action={~p"/users/settings/two_factor"} method="post" class="space-y-3">
          <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
          <input type="hidden" name="_method" value="delete" />
          <label class="fieldset">
            <span class="label">Password</span>
            <input type="password" name="user[password]" class="w-full input" required />
          </label>
          <.button>Turn off</.button>
        </form>
        <form action={~p"/users/settings/two_factor/recovery"} method="post" class="space-y-3">
          <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
          <label class="fieldset">
            <span class="label">Password</span>
            <input type="password" name="user[password]" class="w-full input" required />
          </label>
          <.button>Regenerate recovery codes</.button>
        </form>
      <% else %>
        <section class="space-y-3">
          <h2 class="font-semibold">Authenticator app</h2>
          <p>Scan this address or enter the key in your authenticator, then confirm with a code.</p>
          <p id="totp-uri"><code>{@uri}</code></p>
          <p id="totp-key"><code>{@manual_key}</code></p>
          <form action={~p"/users/settings/two_factor/app"} method="post" class="space-y-3">
            <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
            <label class="fieldset">
              <span class="label">Password</span>
              <input type="password" name="user[password]" class="w-full input" required />
            </label>
            <label class="fieldset">
              <span class="label">Authenticator code</span>
              <input type="text" name="user[code]" class="w-full input" required />
            </label>
            <.button>Turn on authenticator</.button>
          </form>
        </section>
        <section class="space-y-3">
          <h2 class="font-semibold">Email codes</h2>
          <form action={~p"/users/settings/two_factor/email"} method="post">
            <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
            <.button>Email a code</.button>
          </form>
          <form action={~p"/users/settings/two_factor/email"} method="post" class="space-y-3">
            <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
            <input type="hidden" name="_method" value="put" />
            <label class="fieldset">
              <span class="label">Password</span>
              <input type="password" name="user[password]" class="w-full input" required />
            </label>
            <label class="fieldset">
              <span class="label">Emailed code</span>
              <input type="text" name="user[code]" class="w-full input" required />
            </label>
            <.button>Turn on email codes</.button>
          </form>
        </section>
      <% end %>
    </Layouts.app>
    """
  end
end
