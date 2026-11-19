defmodule CalexWeb.CollectionLive do
  use CalexWeb, :live_view

  alias Calex.Calendars
  alias Calex.Dav.Paths

  @impl true
  def mount(_params, _session, socket) do
    {:ok, reload(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        Calendars and address books
        <:subtitle>
          Share a collection, then the next CalDAV or CardDAV request follows that grant.
        </:subtitle>
      </.header>

      <form id="new-collection" phx-submit="create" class="space-y-3">
        <label class="fieldset">
          <span class="label">Name</span>
          <input type="text" name="collection[display_name]" class="w-full input" required />
        </label>
        <label class="fieldset">
          <span class="label">Kind</span>
          <select name="collection[kind]" class="w-full select">
            <option value="calendar">calendar</option>
            <option value="addressbook">address book</option>
          </select>
        </label>
        <.button>Create</.button>
      </form>

      <section
        :for={collection <- @collections}
        id={"collection-#{collection.id}"}
        class="space-y-3 border-t pt-4"
      >
        <h2 class="font-semibold">{collection.display_name}</h2>
        <p class="text-sm">{collection.kind}</p>
        <p class="text-sm break-all" id={"path-#{collection.id}"}>{Paths.collection(collection)}</p>

        <form
          id={"rename-#{collection.id}"}
          phx-submit="rename"
          phx-value-id={collection.id}
          class="flex gap-2"
        >
          <input
            type="text"
            name="collection[display_name]"
            value={collection.display_name}
            class="w-full input"
            required
          />
          <.button>Rename</.button>
        </form>

        <button
          id={"delete-#{collection.id}"}
          type="button"
          phx-click="delete"
          phx-value-id={collection.id}
          class="btn"
        >
          Delete
        </button>

        <form
          id={"grant-#{collection.id}"}
          phx-submit="grant"
          phx-value-id={collection.id}
          class="space-y-2"
        >
          <label class="fieldset">
            <span class="label">Share with</span>
            <input type="email" name="grant[email]" class="w-full input" required />
          </label>
          <label class="fieldset">
            <span class="label">Access</span>
            <select name="grant[privilege]" class="w-full select">
              <option value="read">read</option>
              <option value="write">write</option>
              <option :if={collection.kind == :calendar} value="free_busy">free-busy only</option>
            </select>
          </label>
          <.button>Grant</.button>
        </form>

        <ul>
          <li
            :for={grant <- collection.grants}
            id={"grant-row-#{grant.id}"}
            class="flex items-center gap-3"
          >
            <span>{grant.user.email}</span>
            <span>{grant.privilege}</span>
            <button
              id={"revoke-#{grant.id}"}
              type="button"
              phx-click="revoke"
              phx-value-id={grant.id}
              class="btn btn-ghost"
            >
              Revoke
            </button>
          </li>
        </ul>
      </section>

      <section :if={@shared != []} class="border-t pt-4">
        <h2 class="font-semibold">Shared with you</h2>
        <ul>
          <li :for={collection <- @shared}>
            {collection.display_name} from {collection.owner.email}
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("create", %{"collection" => attrs}, socket) do
    case Calendars.create_collection(socket.assigns.current_user, attrs) do
      {:ok, _collection} ->
        {:noreply, socket |> put_flash(:info, "collection created") |> reload()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "collection was not created")}
    end
  end

  def handle_event("rename", %{"id" => id, "collection" => attrs}, socket) do
    user = socket.assigns.current_user
    collection = Calendars.get_owned!(user, id)

    case Calendars.rename_collection(user, collection, attrs) do
      {:ok, _collection} -> {:noreply, reload(socket)}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, "collection was not renamed")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    collection = Calendars.get_owned!(user, id)

    case Calendars.delete_collection(user, collection) do
      {:ok, _collection} ->
        {:noreply, socket |> put_flash(:info, "collection deleted") |> reload()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "collection was not deleted")}
    end
  end

  def handle_event("grant", %{"id" => id, "grant" => grant}, socket) do
    user = socket.assigns.current_user
    collection = Calendars.get_owned!(user, id)

    case Calendars.grant(user, collection, grant["email"], grant["privilege"]) do
      {:ok, _grant} ->
        {:noreply, socket |> put_flash(:info, "access updated") |> reload()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, grant_error(reason))}
    end
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    grant = Calendars.get_grant!(user, id)

    case Calendars.revoke(user, grant) do
      {:ok, _grant} ->
        {:noreply, socket |> put_flash(:info, "access revoked") |> reload()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "access was not revoked")}
    end
  end

  defp reload(socket) do
    user = socket.assigns.current_user

    assign(socket,
      collections: Calendars.list_owned(user),
      shared: Calendars.list_shared(user)
    )
  end

  defp grant_error(:not_found), do: "that person does not have an account"
  defp grant_error(:invalid), do: "that access level is not available"
  defp grant_error(:unauthorized), do: "you cannot change this collection"
  defp grant_error(_reason), do: "access was not updated"
end
