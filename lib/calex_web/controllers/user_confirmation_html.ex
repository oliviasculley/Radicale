defmodule CalexWeb.UserConfirmationHTML do
  use CalexWeb, :html

  def new(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>Resend confirmation</.header>
      <form action={~p"/users/confirm"} method="post" class="space-y-4">
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
end
