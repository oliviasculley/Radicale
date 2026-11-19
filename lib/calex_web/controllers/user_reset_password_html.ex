defmodule CalexWeb.UserResetPasswordHTML do
  use CalexWeb, :html

  def new(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>Reset password</.header>
      <form action={~p"/users/reset_password"} method="post" class="space-y-4">
        <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
        <label class="fieldset">
          <span class="label">Email</span>
          <input type="email" name="user[email]" class="w-full input" required />
        </label>
        <.button>Send instructions</.button>
      </form>
    </Layouts.app>
    """
  end

  def edit(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>Choose a new password</.header>
      <.form
        :let={f}
        for={to_form(@changeset)}
        action={~p"/users/reset_password/#{@token}"}
        method="put"
      >
        <.input field={f[:password]} type="password" label="New password" required />
        <.input field={f[:password_confirmation]} type="password" label="Confirm password" required />
        <.button>Update password</.button>
      </.form>
    </Layouts.app>
    """
  end
end
