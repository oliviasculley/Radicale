defmodule CalexWeb.UserTwoFactorHTML do
  use CalexWeb, :html

  def new(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>Two-factor authentication</.header>
      <p :if={@error_message} class="text-error">{@error_message}</p>
      <p :if={@user.two_factor_method == :email}>Enter the code that was emailed to you.</p>
      <p :if={@user.two_factor_method == :app}>Enter the code from your authenticator.</p>
      <form action={~p"/users/log_in/two_factor"} method="post" id="two-factor-form" class="space-y-4">
        <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
        <label class="fieldset">
          <span class="label">Code</span>
          <input
            type="text"
            name="user[code]"
            class="w-full input"
            autocomplete="one-time-code"
            required
          />
        </label>
        <.button>Continue</.button>
      </form>
      <form
        :if={@user.two_factor_method == :email}
        action={~p"/users/log_in/two_factor/email"}
        method="post"
      >
        <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
        <.button>Email a new code</.button>
      </form>
    </Layouts.app>
    """
  end
end
