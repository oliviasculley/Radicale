defmodule CalexWeb.InviteLive do
  use CalexWeb, :live_view

  alias Calex.Accounts
  alias Calex.Accounts.Invites

  @impl true
  def mount(_params, _session, socket) do
    if Accounts.admin?(socket.assigns.current_user) do
      {:ok, reload(socket)}
    else
      {:ok, push_navigate(socket, to: ~p"/collections")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>Invites</.header>
      <form id="new-invite" phx-submit="create" class="space-y-3">
        <label class="fieldset">
          <span class="label">Name</span>
          <input type="text" name="invite[name]" class="w-full input" required />
        </label>
        <label class="fieldset">
          <span class="label">Uses left</span>
          <input type="number" name="invite[uses_left]" class="w-full input" min="0" />
        </label>
        <.button>Create invite</.button>
      </form>
      <ul class="space-y-2">
        <li :for={invite <- @invites} id={"invite-#{invite.id}"}>
          <span>{invite.name}</span>
          <code>{invite.token}</code>
          <.link href={~p"/users/register?#{[invite: invite.token]}"}>registration link</.link>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("create", %{"invite" => attrs}, socket) do
    attrs =
      if attrs["uses_left"] in [nil, ""] do
        Map.delete(attrs, "uses_left")
      else
        attrs
      end

    case Invites.create_invite(socket.assigns.current_user, attrs) do
      {:ok, invite} ->
        {:noreply, socket |> put_flash(:info, "invite #{invite.name} created") |> reload()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "invite was not created")}
    end
  end

  defp reload(socket) do
    assign(socket, invites: Invites.list_invites(socket.assigns.current_user))
  end
end
