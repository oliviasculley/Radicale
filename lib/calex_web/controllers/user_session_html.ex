defmodule CalexWeb.UserSessionHTML do
  use CalexWeb, :html

  def new(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>Log in</.header>
      <p :if={@error_message} class="text-error">{@error_message}</p>
      <form action={~p"/users/log_in"} method="post" id="login-form" class="space-y-4">
        <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
        <label class="fieldset">
          <span class="label">Email</span>
          <input type="email" name="user[email]" value={@email} class="w-full input" required />
        </label>
        <label class="fieldset">
          <span class="label">Password</span>
          <input type="password" name="user[password]" class="w-full input" required />
        </label>
        <.button>Log in</.button>
      </form>
      <p>
        <.link href={~p"/users/reset_password"}>Forgot password?</.link>
      </p>
    </Layouts.app>
    """
  end
end
