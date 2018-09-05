defmodule PowPersistentSession.Phoenix.ControllerCallbacks do
  @moduledoc false
  use Pow.Extension.Phoenix.ControllerCallbacks.Base

  alias Plug.Conn
  alias PowPersistentSession.Plug

  def before_process(Pow.Phoenix.SessionController, :create, conn, _config) do
    store = Map.get(conn.params["user"], "persistent_session", "true")

    Conn.put_private(conn, :store_persistent_session?, store)
  end

  def before_respond(Pow.Phoenix.SessionController, :create, {:ok, conn}, _config) do
    user = Pow.Plug.Helpers.current_user(conn)

    case conn.private[:store_persistent_session?] do
      "true" -> {:ok, Plug.Helpers.create(conn, user)}
      _any   -> {:ok, conn}
    end
  end

  def before_respond(Pow.Phoenix.SessionController, :delete, {:ok, conn}, _config) do
    {:ok, Plug.Helpers.delete(conn)}
  end
end
