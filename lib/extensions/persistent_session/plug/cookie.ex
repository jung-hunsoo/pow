defmodule PowPersistentSession.Plug.Cookie do
  @moduledoc """
  This plug will handle persistent user sessions with cookies.

  By default, the cookie will expire after 30 days. The cookie expiration will
  be renewed on every request. The token in the cookie can only be used once to
  create a session.

  ## Example

    defmodule MyAppWeb.Endpoint do
      # ...

      plug Pow.Plug.Session, otp_app: :my_app

      plug PowPersistentSession.Plug.Cookie

      #...
    end

  ## Configuration options

    * `:persistent_session_store` - see `PowPersistentSession.Plug.Base`

    * `:cache_store_backend` - see `PowPersistentSession.Plug.Base`

    * `:persistent_session_cookie_key` - session key name. This defaults to
      "persistent_session_cookie". If `:otp_app` is used it'll automatically
      prepend the key with the `:otp_app` value.

    * `:persistent_session_cookie_max_age` - max age for cookie in seconds. This
      defaults to 30 days in seconds.
  """
  use PowPersistentSession.Plug.Base

  alias Plug.Conn
  alias Pow.{Config, Plug, UUID}

  @cookie_key "persistent_session_cookie"
  @ttl Integer.floor_div(:timer.hours(24) * 30, 1000)

  @doc """
  Sets a persistent session cookie with an auto generated token.

  The token is set as a key in the persistent session cache with
  the user struct id.

  The unique cookie id will be prepended by the `:otp_app` configuration
  value, if present.
  """
  @spec create(Conn.t(), map(), Config.t()) :: Conn.t()
  def create(conn, %{id: user_id}, config) do
    {store, store_config} = store(config)
    cookie_key            = cookie_key(config)
    key                   = cookie_id(config)
    value                 = user_id
    opts                  = session_opts(config)

    store.put(store_config, key, value)
    Conn.put_resp_cookie(conn, cookie_key, key, opts)
  end

  @doc """
  Expires the persistent session cookie.

  If a persistent session cookie exists it'll be expired, and the token in
  the persistent session cache will be deleted.
  """
  @spec delete(Conn.t(), Config.t()) :: Conn.t()
  def delete(conn, config) do
    cookie_key = cookie_key(config)

    case conn.req_cookies[cookie_key] do
      nil    -> conn
      key_id -> do_delete(conn, cookie_key, key_id, config)
    end
  end

  defp do_delete(conn, cookie_key, key_id, config) do
    {store, store_config} = store(config)
    value                 = ""
    opts                  = [max_age: -1, path: "/"]

    store.delete(store_config, key_id)
    Conn.put_resp_cookie(conn, cookie_key, value, opts)
  end

  @doc """
  Authenticates a user with the persistent session cookie.

  If a persistent session cookie exists, it'll fetch the credentials from the
  persistent session cache, and create a new session and persistent session
  cookie. The old persistent session cookie and session cache credentials will
  be removed.

  The cookie expiration will automatically be renewed on every request.
  """
  @spec authenticate(Conn.t(), Config.t()) :: Conn.t()
  def authenticate(conn, config) do
    user = Plug.Helpers.current_user(conn)

    conn
    |> Conn.fetch_cookies()
    |> maybe_authenticate(user, config)
    |> maybe_renew(config)
  end

  defp maybe_authenticate(conn, nil, config) do
    cookie_key = cookie_key(config)

    case conn.req_cookies[cookie_key] do
      nil    -> conn
      key_id -> do_authenticate(conn, key_id, config)
    end
  end
  defp maybe_authenticate(conn, _user, _config), do: conn

  defp do_authenticate(conn, key_id, config) do
    {store, store_config} = store(config)
    mod                   = config[:mod]

    store_config
    |> store.get(key_id)
    |> maybe_fetch_user(config)
    |> case do
      nil ->
        delete(conn, config)

      user ->
        conn
        |> delete(config)
        |> create(user, config)
        |> mod.do_create(user)
    end
  end

  defp maybe_fetch_user(:not_found, _config), do: nil
  defp maybe_fetch_user(user_id, config) do
    Pow.Operations.get_by([id: user_id], config)
  end

  defp maybe_renew(conn, config) do
    cookie_key  = cookie_key(config)

    case conn.resp_cookies[cookie_key] do
      nil  -> renew(conn, cookie_key, config)
      _any -> conn
    end
  end

  defp renew(conn, cookie_key, config) do
    opts = session_opts(config)

    case conn.req_cookies[cookie_key] do
      nil   -> conn
      value -> Conn.put_resp_cookie(conn, cookie_key, value, opts)
    end
  end

  defp cookie_id(config) do
    uuid = UUID.generate()

    case Config.get(config, :otp_app, nil) do
      nil     -> uuid
      otp_app -> "#{otp_app}_#{uuid}"
    end
  end

  defp cookie_key(config) do
    Config.get(config, :persistent_session_cookie_key, default_cookie_key(config))
  end

  defp default_cookie_key(config) do
    case Config.get(config, :otp_app, nil) do
      nil     -> @cookie_key
      otp_app -> "#{otp_app}_#{@cookie_key}"
    end
  end

  defp session_opts(config) do
    max_age = Config.get(config, :persistent_session_cookie_max_age, @ttl)

    [max_age: max_age, path: "/"]
  end
end
