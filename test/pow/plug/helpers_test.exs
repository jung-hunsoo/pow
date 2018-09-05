defmodule Pow.Plug.HelpersTest do
  use ExUnit.Case
  doctest Pow.Plug.Helpers

  alias Plug.Conn
  alias Pow.{Config, Config.ConfigError, Plug, Plug.Session}
  alias Pow.Test.{ConnHelpers, ContextMock, Ecto.Users.User}

  @ets Pow.Test.EtsCacheMock
  @default_config [
    current_user_assigns_key: :current_user,
    users_context: ContextMock,
    cache_store_backend: @ets,
    user: User
  ]
  @admin_config Config.put(@default_config, :current_user_assigns_key, :current_admin_user)

  setup do
    {:ok, ets: @ets}
  end

  test "current_user/1" do
    assert_raise ConfigError, "Pow configuration not found. Please set the Pow.Plug.Session plug beforehand.", fn ->
      Plug.Helpers.current_user(%Conn{private: %{}, assigns: %{}})
    end

    user = %{id: 1}
    conn = %Conn{assigns: %{current_user: user}, private: %{pow_config: @default_config}}
    assert Plug.Helpers.current_user(conn) == user

    conn = %Conn{assigns: %{current_user: user}, private: %{pow_config: @admin_config}}
    assert is_nil(Plug.Helpers.current_user(conn))
  end

  test "current_user/2" do
    assert is_nil(Plug.Helpers.current_user(%Conn{assigns: %{}}, @default_config))

    user = %{id: 1}
    conn = %Conn{assigns: %{current_user: user}}

    assert Plug.Helpers.current_user(conn, @default_config) == user
    assert is_nil(Plug.Helpers.current_user(conn, @admin_config))
  end

  test "assign_current_user/3" do
    user = %{id: 1}
    conn = %Conn{assigns: %{}}
    assert Plug.Helpers.assign_current_user(conn, %{id: 1}, @default_config) == %Conn{assigns: %{current_user: user}}

    assert Plug.Helpers.assign_current_user(conn, %{id: 1}, @admin_config) == %Conn{assigns: %{current_admin_user: user}}
  end

  test "authenticate_user/2", %{ets: ets} do
    ets.init()

    opts = Session.init(@default_config)
    conn =
      conn()
      |> ConnHelpers.init_session()
      |> Session.call(opts)

    refute conn.private[:plug_session]["auth"]
    refute Plug.Helpers.current_user(conn)

    assert {:ok, loaded_conn} = Plug.Helpers.authenticate_user(conn, %{"email" => "test@example.com", "password" => "secret"})
    assert user = Plug.Helpers.current_user(loaded_conn)
    assert user.id == 1
    assert loaded_conn.private[:plug_session]["auth"]

    assert {:error, conn} = Plug.Helpers.authenticate_user(conn, %{})
    refute Plug.Helpers.current_user(conn)

    assert {:error, conn} = Plug.Helpers.authenticate_user(conn, %{"email" => "test@example.com"})
    refute Plug.Helpers.current_user(conn)
  end

  test "authenticate_user/2 with missing user" do
    assert_raise ConfigError, "No :user configuration option found for user schema module.", fn ->
      Plug.Helpers.authenticate_user(conn([]), %{})
    end
  end

  test "authenticate_user/2 with invalid users_context" do
    assert_raise UndefinedFunctionError, fn ->
      Plug.Helpers.authenticate_user(conn(users_context: Invalid), %{})
    end
  end

  test "clear_authenticated_user/1", %{ets: ets} do
    ets.init()

    opts = Session.init(@default_config)
    conn =
      conn()
      |> ConnHelpers.init_session()
      |> Session.call(opts)

    assert {:ok, conn} = Plug.Helpers.authenticate_user(conn, %{"email" => "test@example.com", "password" => "secret"})
    assert user = Plug.Helpers.current_user(conn)
    assert session_id = conn.private[:plug_session]["auth"]
    assert {^user, _timestamp} = ets.get(nil, session_id)

    {:ok, conn} = Plug.Helpers.clear_authenticated_user(conn)
    refute Plug.Helpers.current_user(conn)
    refute conn.private[:plug_session]["auth"]
    assert ets.get(nil, session_id) == :not_found
  end

  test "change_user/2" do
    conn = conn()
    assert %Ecto.Changeset{} = Plug.Helpers.change_user(conn)

    conn = Plug.Helpers.assign_current_user(conn, %User{id: 1}, @default_config)
    changeset = Plug.Helpers.change_user(conn)
    assert changeset.data.id == 1
  end

  test "create_user/2", %{ets: ets} do
    ets.init()

    opts = Session.init(@default_config)
    conn =
      conn()
      |> ConnHelpers.init_session()
      |> Session.call(opts)

    assert {:error, _changeset, conn} = Plug.Helpers.create_user(conn, %{})
    refute Plug.Helpers.current_user(conn)
    refute conn.private[:plug_session]["auth"]

    assert {:ok, user, conn} = Plug.Helpers.create_user(conn, %{"email" => "test@example.com", "password" => "secret"})
    assert Plug.Helpers.current_user(conn) == user
    assert conn.private[:plug_session]["auth"]
  end

  test "update_user/2", %{ets: ets} do
    ets.init()

    opts = Session.init(@default_config)
    conn =
      conn()
      |> ConnHelpers.init_session()
      |> Session.call(opts)

    {:ok, conn} = Plug.Helpers.authenticate_user(conn, %{"email" => "test@example.com", "password" => "secret"})
    user        = Plug.Helpers.current_user(conn)
    session_id  = conn.private[:plug_session]["auth"]

    assert {:error, _changeset, conn} = Plug.Helpers.update_user(conn, %{})
    assert Plug.Helpers.current_user(conn) == user
    assert conn.private[:plug_session]["auth"] == session_id

    assert {:ok, updated_user, conn} = Plug.Helpers.update_user(conn, %{"email" => "test@example.com", "password" => "secret"})
    assert updated_user.id == :updated
    assert Plug.Helpers.current_user(conn) == updated_user
    refute updated_user == user
    refute conn.private[:plug_session]["auth"] == session_id
  end

  test "delete_user/2", %{ets: ets} do
    ets.init()

    opts = Session.init(@default_config)
    conn =
      conn()
      |> ConnHelpers.init_session()
      |> Session.call(opts)

    {:ok, conn} = Plug.Helpers.authenticate_user(conn, %{"email" => "test@example.com", "password" => "secret"})

    assert {:ok, user, conn} = Plug.Helpers.delete_user(conn)
    assert user.id == :deleted
    refute Plug.Helpers.current_user(conn)
    refute conn.private[:plug_session]["auth"]
  end

  defp conn(config \\ @default_config) do
    %Conn{private: %{pow_config: config}}
  end
end
