defmodule Pow.Phoenix.Controller do
  @moduledoc """
  Used with Pow Phoenix controllers to handle messages, routes and callbacks.

  ## Configuration options

    * `:messages_backend` - See `Pow.Phoenix.Messages` for more.

    * `:routes_backend` - See `Pow.Phoenix.Routes` for more.

    * `:controller_callbacks` - See
      `Pow.Extension.Phoenix.ControllerCallbacks` for more.
  """
  alias Plug.Conn
  alias Pow.{Config, Plug}
  alias Pow.Phoenix.{Messages, PlugErrorHandler, Routes, ViewHelpers}

  @doc false
  defmacro __using__(config) do
    quote do
      use Phoenix.Controller,
        namespace: Pow.Phoenix

      plug :pow_layout, unquote(config)

      @doc """
      See `Pow.Phoenix.Controller.action/3` for more.
      """
      @spec action(Conn.t(), Keyword.t()) :: Conn.t()
      def action(conn, _opts) do
        unquote(__MODULE__).action(__MODULE__, conn, conn.params)
      end

      defp require_authenticated(conn, _opts) do
        opts = Plug.RequireAuthenticated.init(error_handler: PlugErrorHandler)
        Plug.RequireAuthenticated.call(conn, opts)
      end

      defp require_not_authenticated(conn, _opts) do
        opts = Plug.RequireNotAuthenticated.init(error_handler: PlugErrorHandler)
        Plug.RequireNotAuthenticated.call(conn, opts)
      end

      defp pow_layout(conn, _config), do: ViewHelpers.layout(conn)

      @doc """
      See `Pow.Phoenix.Controller.messages/2` for more.

      `Pow.Phoenix.Messages` is used as fallback.
      """
      @spec messages(Conn.t()) :: atom()
      def messages(conn) do
        unquote(__MODULE__).messages(conn, Messages)
      end

      @doc """
      See `Pow.Phoenix.Controller.routes/2` for more.

      `Pow.Phoenix.Routes` is used as fallback.
      """
      @spec routes(Conn.t()) :: atom()
      def routes(conn) do
        unquote(__MODULE__).routes(conn, Routes)
      end

      import unquote(__MODULE__), only: [router_helpers: 1]

      defoverridable messages: 1, routes: 1
    end
  end

  @doc """
  Handles the controller action call.

  If a `:controller_callbacks` module has been set in the configuration,
  then `before_process` and `before_respond` will be called on this module
  on all actions.
  """
  @spec action(atom(), Conn.t(), map()) :: Conn.t()
  def action(controller, %{private: private} = conn, params) do
    action    = private.phoenix_action
    config    = Plug.Helpers.fetch_config(conn)
    callbacks = Config.get(config, :controller_callbacks, nil)

    conn
    |> maybe_callback(callbacks, :before_process, controller, action, config)
    |> process_action(controller, action, params)
    |> maybe_callback(callbacks, :before_respond, controller, action, config)
    |> respond_action(controller, action)
  end

  defp process_action(conn, controller, action, params) do
    apply(controller, String.to_atom("process_#{action}"), [conn, params])
  end

  defp respond_action({:halt, conn}, _controller, _action), do: conn
  defp respond_action(results, controller, action) do
    apply(controller, String.to_atom("respond_#{action}"), [results])
  end

  defp maybe_callback(results, nil, _hook, _controller, _action, _config), do: results
  defp maybe_callback(results, callbacks, hook, controller, action, config) do
    apply(callbacks, hook, [controller, action, results, config])
  end

  @doc """
  Fetches messages backend from configuration, or use fallback.
  """
  @spec messages(Conn.t(), atom()) :: atom()
  def messages(conn, fallback) do
    conn
    |> Plug.Helpers.fetch_config()
    |> Config.get(:messages_backend, fallback)
  end

  @doc """
  Fetches routes backend from configuration, or use fallback.
  """
  @spec routes(Conn.t(), atom()) :: atom()
  def routes(conn, fallback) do
    conn
    |> Plug.Helpers.fetch_config()
    |> Config.get(:routes_backend, fallback)
  end

  @doc """
  Fetches router helpers module from connection.
  """
  @spec router_helpers(Conn.t()) :: atom()
  def router_helpers(%{private: private}) do
    Module.concat([private.phoenix_router, Helpers])
  end
end
