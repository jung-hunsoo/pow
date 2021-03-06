defmodule Pow.Ecto.Context do
  @moduledoc """
  Handles pow users context for user.

  ## Usage

  This module will be used by pow by default. If you
  wish to have control over context methods, you can
  do configure `lib/my_project/users/users.ex`
  the following way:

      defmodule MyApp.Users do
        use Pow.Ecto.Context,
          repo: MyApp.Repo,
          user: MyApp.Users.User

        def create(params) do
          pow_create(params)
        end
      end

  Remember to update configuration with `users_context: MyApp.Users`.

  The following Pow methods can be accessed:

    * `pow_authenticate/1`
    * `pow_create/1`
    * `pow_update/2`
    * `pow_delete/1`
    * `pow_get_by/1`

  ## Configuration options

    * `:repo` - the ecto repo module (required)
    * `:user` - the user schema module (required)
  """
  alias Ecto.Changeset
  alias Pow.Config
  alias Pow.Ecto.Schema

  @type user :: map()

  @callback authenticate(map()) :: user() | nil
  @callback create(map()) :: {:ok, user()} | {:error, Changeset.t()}
  @callback update(user(), map()) :: {:ok, user()} | {:error, Changeset.t()}
  @callback delete(user()) :: {:ok, user()} | {:error, Changeset.t()}
  @callback get_by(Keyword.t() | map()) :: user() | nil

  @doc false
  defmacro __using__(config) do
    quote do
      @behaviour unquote(__MODULE__)

      @pow_config unquote(config)

      def authenticate(params), do: pow_authenticate(params)
      def create(params), do: pow_create(params)
      def update(user, params), do: pow_update(user, params)
      def delete(user), do: pow_delete(user)
      def get_by(clauses), do: pow_get_by(clauses)

      def pow_authenticate(params) do
        unquote(__MODULE__).authenticate(params, @pow_config)
      end

      def pow_create(params) do
        unquote(__MODULE__).create(params, @pow_config)
      end

      def pow_update(user, params) do
        unquote(__MODULE__).update(user, params, @pow_config)
      end

      def pow_delete(user) do
        unquote(__MODULE__).delete(user, @pow_config)
      end

      def pow_get_by(clauses) do
        unquote(__MODULE__).get_by(clauses, @pow_config)
      end

      defoverridable unquote(__MODULE__)
    end
  end

  @doc """
  Finds a user based on the user id, and verifies the password on the user.

  User schema module and repo module will be fetched from the config. The user
  id field is fetched from the user schema module.
  """
  @spec authenticate(map(), Config.t()) :: user() | nil
  def authenticate(params, config) do
    user_mod      = user_schema_mod(config)
    user_id_field = user_mod.pow_user_id_field()
    login_value   = params[Atom.to_string(user_id_field)]
    password      = params["password"]

    [{user_id_field, login_value}]
    |> get_by(config)
    |> maybe_verify_password(password)
  end

  defp maybe_verify_password(nil, _password),
    do: nil
  defp maybe_verify_password(user, password) do
    case user.__struct__.verify_password(user, password) do
      true -> user
      _    -> nil
    end
  end

  @doc """
  Creates a new user.

  User schema module and repo module will be fetched from config.
  """
  @spec create(map(), Config.t()) :: {:ok, user()} | {:error, Changeset.t()}
  def create(params, config) do
    user_mod = user_schema_mod(config)

    user_mod.__struct__()
    |> user_mod.changeset(params)
    |> do_insert(config)
  end

  @doc """
  Updates the user.

  User schema module will be fetched from provided user and repo will be
  fetched from the config.
  """
  @spec update(user(), map(), Config.t()) :: {:ok, user()} | {:error, Changeset.t()}
  def update(user, params, config) do
    user
    |> user.__struct__.changeset(params)
    |> do_update(config)
  end

  @doc """
  Deletes the user.

  Repo module will be fetched from the config.
  """
  @spec delete(user(), Config.t()) :: {:ok, user()} | {:error, Changeset.t()}
  def delete(user, config) do
    repo(config).delete(user)
  end

  @doc """
  Retrieves an user by the provided clauses.

  User schema module and repo module will be fetched from the config.
  """
  @spec get_by(Keyword.t() | map(), Config.t()) :: user() | nil
  def get_by(clauses, config) do
    user_mod = user_schema_mod(config)
    clauses  = normalize_user_id_field_value(user_mod, clauses)

    repo(config).get_by(user_mod, clauses)
  end

  defp normalize_user_id_field_value(user_mod, clauses) do
    user_id_field = user_mod.pow_user_id_field()

    Enum.map(clauses, fn
      {^user_id_field, value} -> {user_id_field, Schema.normalize_user_id_field_value(value)}
      any -> any
    end)
  end

  @doc """
  Inserts a changeset to the database.

  If succesful, the returned row will be reloaded from the database.
  """
  @spec do_insert(Changeset.t(), Config.t()) :: {:ok, user()} | {:error, Changeset.t()}
  def do_insert(changeset, config) do
    changeset
    |> repo(config).insert()
    |> reload_after_write(config)
  end

  @doc """
  Updates a changeset in the database.

  If succesful, the returned row will be reloaded from the database.
  """
  @spec do_update(Changeset.t(), Config.t()) :: {:ok, user()} | {:error, Changeset.t()}
  def do_update(changeset, config) do
    changeset
    |> repo(config).update()
    |> reload_after_write(config)
  end

  defp reload_after_write({:error, changeset}, _config), do: {:error, changeset}
  defp reload_after_write({:ok, user}, config) do
    # When ecto updates/inserts, has_many :through associations are set to nil.
    # So we'll just reload when writes happen.
    user = repo(config).get!(user.__struct__, user.id)

    {:ok, user}
  end

  @doc """
  Retrieves the repo module from the config, or raises an exception.
  """
  @spec repo(Config.t()) :: atom()
  def repo(config) do
    Config.get(config, :repo, nil) || raise_no_repo_error()
  end

  @doc """
  Retrieves the user schema module from the config, or raises an exception.
  """
  @spec user_schema_mod(Config.t()) :: atom()
  def user_schema_mod(config) do
    Config.get(config, :user, nil) || raise_no_user_error()
  end

  @spec raise_no_repo_error :: no_return
  defp raise_no_repo_error do
    Config.raise_error("No :repo configuration option found for users context module.")
  end

  @spec raise_no_user_error :: no_return
  defp raise_no_user_error do
    Config.raise_error("No :user configuration option found for user schema module.")
  end
end
