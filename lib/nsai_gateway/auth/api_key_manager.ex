defmodule NsaiGateway.Auth.ApiKeyManager do
  @moduledoc """
  API Key lifecycle management with rotation and revocation.

  Manages API keys with expiration, rotation, and revocation features.
  In production, this should be backed by a persistent store (database/cache).

  ## Features

  - Key generation with expiration
  - Key rotation
  - Key revocation
  - Tenant scoping
  - Metadata tracking
  """

  use GenServer
  require Logger

  @type key_id :: String.t()
  @type api_key :: String.t()
  @type tenant :: String.t()
  @type key_info :: %{
          key: api_key(),
          tenant: tenant(),
          created_at: DateTime.t(),
          expires_at: DateTime.t() | nil,
          last_used: DateTime.t() | nil,
          metadata: map(),
          revoked: boolean()
        }

  defstruct keys: %{}, revoked: MapSet.new()

  # Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Creates a new API key for a tenant with optional expiration.

  ## Options

    * `:expires_in` - Number of seconds until key expires (default: nil for no expiration)
    * `:metadata` - Additional metadata to store with the key

  ## Examples

      iex> create_key("tenant-alpha", expires_in: 86400, metadata: %{description: "Production key"})
      {:ok, %{key_id: "...", api_key: "..."}}
  """
  @spec create_key(tenant(), keyword()) :: {:ok, %{key_id: key_id(), api_key: api_key()}}
  def create_key(tenant, opts \\ []) do
    GenServer.call(__MODULE__, {:create_key, tenant, opts})
  end

  @doc """
  Rotates an API key, invalidating the old one and creating a new one.

  Returns both the old key ID and the new key information.
  """
  @spec rotate_key(api_key()) ::
          {:ok, %{old_key_id: key_id(), new_key_id: key_id(), new_api_key: api_key()}}
          | {:error, :not_found | :already_revoked}
  def rotate_key(old_key) do
    GenServer.call(__MODULE__, {:rotate_key, old_key})
  end

  @doc """
  Revokes an API key, making it invalid for future requests.

  Returns `:ok` if successful, `{:error, reason}` otherwise.
  """
  @spec revoke_key(api_key()) :: :ok | {:error, :not_found | :already_revoked}
  def revoke_key(api_key) do
    GenServer.call(__MODULE__, {:revoke_key, api_key})
  end

  @doc """
  Verifies an API key and returns the associated tenant if valid.

  Checks for expiration and revocation status.
  """
  @spec verify_key(api_key()) :: {:ok, tenant()} | {:error, :invalid_key | :expired | :revoked}
  def verify_key(api_key) do
    GenServer.call(__MODULE__, {:verify_key, api_key})
  end

  @doc """
  Lists all keys for a specific tenant.
  """
  @spec list_keys(tenant()) :: list(key_info())
  def list_keys(tenant) do
    GenServer.call(__MODULE__, {:list_keys, tenant})
  end

  @doc """
  Gets detailed information about a specific key.
  """
  @spec get_key_info(api_key()) :: {:ok, key_info()} | {:error, :not_found}
  def get_key_info(api_key) do
    GenServer.call(__MODULE__, {:get_key_info, api_key})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Load existing keys from config for backward compatibility
    keys = load_legacy_keys()
    {:ok, %__MODULE__{keys: keys}}
  end

  @impl true
  def handle_call({:create_key, tenant, opts}, _from, state) do
    key_id = generate_key_id()
    api_key = generate_api_key()
    expires_in = Keyword.get(opts, :expires_in)
    metadata = Keyword.get(opts, :metadata, %{})

    key_info = %{
      key: api_key,
      tenant: tenant,
      created_at: DateTime.utc_now(),
      expires_at: calculate_expiration(expires_in),
      last_used: nil,
      metadata: metadata,
      revoked: false
    }

    new_keys = Map.put(state.keys, key_id, key_info)
    new_state = %{state | keys: new_keys}

    Logger.info("Created new API key for tenant=#{tenant} key_id=#{key_id}")

    {:reply, {:ok, %{key_id: key_id, api_key: api_key}}, new_state}
  end

  @impl true
  def handle_call({:rotate_key, old_key}, _from, state) do
    case find_key_by_value(state.keys, old_key) do
      nil ->
        {:reply, {:error, :not_found}, state}

      {old_key_id, key_info} ->
        if key_info.revoked do
          {:reply, {:error, :already_revoked}, state}
        else
          # Create new key
          new_key_id = generate_key_id()
          new_api_key = generate_api_key()

          new_key_info = %{
            key: new_api_key,
            tenant: key_info.tenant,
            created_at: DateTime.utc_now(),
            expires_at: key_info.expires_at,
            last_used: nil,
            metadata: Map.put(key_info.metadata, :rotated_from, old_key_id),
            revoked: false
          }

          # Revoke old key
          updated_old_key = %{key_info | revoked: true}

          new_keys =
            state.keys
            |> Map.put(old_key_id, updated_old_key)
            |> Map.put(new_key_id, new_key_info)

          new_state = %{state | keys: new_keys, revoked: MapSet.put(state.revoked, old_key)}

          Logger.info(
            "Rotated API key for tenant=#{key_info.tenant} old_key_id=#{old_key_id} new_key_id=#{new_key_id}"
          )

          {:reply,
           {:ok, %{old_key_id: old_key_id, new_key_id: new_key_id, new_api_key: new_api_key}},
           new_state}
        end
    end
  end

  @impl true
  def handle_call({:revoke_key, api_key}, _from, state) do
    case find_key_by_value(state.keys, api_key) do
      nil ->
        {:reply, {:error, :not_found}, state}

      {key_id, key_info} ->
        if key_info.revoked do
          {:reply, {:error, :already_revoked}, state}
        else
          updated_key = %{key_info | revoked: true}
          new_keys = Map.put(state.keys, key_id, updated_key)
          new_state = %{state | keys: new_keys, revoked: MapSet.put(state.revoked, api_key)}

          Logger.info("Revoked API key for tenant=#{key_info.tenant} key_id=#{key_id}")

          {:reply, :ok, new_state}
        end
    end
  end

  @impl true
  def handle_call({:verify_key, api_key}, _from, state) do
    # Quick check against revoked set
    if MapSet.member?(state.revoked, api_key) do
      {:reply, {:error, :revoked}, state}
    else
      case find_key_by_value(state.keys, api_key) do
        nil ->
          # Fallback to legacy verification for backward compatibility
          case NsaiGateway.Auth.ApiKey.verify(api_key) do
            {:ok, tenant} -> {:reply, {:ok, tenant}, state}
            {:error, _} -> {:reply, {:error, :invalid_key}, state}
          end

        {key_id, key_info} ->
          cond do
            key_info.revoked ->
              {:reply, {:error, :revoked}, state}

            expired?(key_info) ->
              {:reply, {:error, :expired}, state}

            true ->
              # Update last_used timestamp
              updated_key = %{key_info | last_used: DateTime.utc_now()}
              new_keys = Map.put(state.keys, key_id, updated_key)
              new_state = %{state | keys: new_keys}

              {:reply, {:ok, key_info.tenant}, new_state}
          end
      end
    end
  end

  @impl true
  def handle_call({:list_keys, tenant}, _from, state) do
    keys =
      state.keys
      |> Enum.filter(fn {_id, info} -> info.tenant == tenant end)
      |> Enum.map(fn {_id, info} -> info end)

    {:reply, keys, state}
  end

  @impl true
  def handle_call({:get_key_info, api_key}, _from, state) do
    case find_key_by_value(state.keys, api_key) do
      nil -> {:reply, {:error, :not_found}, state}
      {_key_id, key_info} -> {:reply, {:ok, key_info}, state}
    end
  end

  # Private functions

  @spec generate_key_id() :: key_id()
  defp generate_key_id do
    "key_" <> (:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower))
  end

  @spec generate_api_key() :: api_key()
  defp generate_api_key do
    :crypto.strong_rand_bytes(32) |> Base.encode64(padding: false)
  end

  @spec calculate_expiration(integer() | nil) :: DateTime.t() | nil
  defp calculate_expiration(nil), do: nil

  defp calculate_expiration(expires_in) do
    DateTime.utc_now() |> DateTime.add(expires_in, :second)
  end

  @spec expired?(key_info()) :: boolean()
  defp expired?(%{expires_at: nil}), do: false

  defp expired?(%{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @spec find_key_by_value(map(), api_key()) :: {key_id(), key_info()} | nil
  defp find_key_by_value(keys, api_key) do
    Enum.find(keys, fn {_id, info} -> info.key == api_key end)
  end

  @spec load_legacy_keys() :: map()
  defp load_legacy_keys do
    # Load API keys from config for backward compatibility
    Application.get_env(:nsai_gateway, :api_keys, %{})
    |> Enum.map(fn {key, tenant} ->
      key_id = generate_key_id()

      key_info = %{
        key: key,
        tenant: tenant,
        created_at: DateTime.utc_now(),
        expires_at: nil,
        last_used: nil,
        metadata: %{legacy: true},
        revoked: false
      }

      {key_id, key_info}
    end)
    |> Map.new()
  end
end
