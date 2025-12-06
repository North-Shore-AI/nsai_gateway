defmodule NsaiGateway.ServiceResolver do
  @moduledoc """
  Service discovery and resolution.

  In production, this would integrate with nsai_registry for dynamic service discovery.
  For now, uses configured service URLs with health checking.
  """

  use GenServer
  require Logger

  # 30 seconds
  @health_check_interval 30_000

  defstruct services: %{}, last_check: nil

  # Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Resolves a service name to a backend URL.
  """
  @spec resolve(String.t()) :: {:ok, String.t()} | {:error, :not_found | :unhealthy}
  def resolve(service) do
    GenServer.call(__MODULE__, {:resolve, service})
  end

  @doc """
  Gets the health status of all services.
  """
  @spec health_status() :: map()
  def health_status do
    GenServer.call(__MODULE__, :health_status)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    services = load_services()
    schedule_health_check()

    {:ok, %__MODULE__{services: services, last_check: DateTime.utc_now()}}
  end

  @impl true
  def handle_call({:resolve, service}, _from, state) do
    case Map.get(state.services, service) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{url: url, healthy: true} ->
        {:reply, {:ok, url}, state}

      %{healthy: false} ->
        {:reply, {:error, :unhealthy}, state}
    end
  end

  @impl true
  def handle_call(:health_status, _from, state) do
    status =
      state.services
      |> Enum.map(fn {name, info} ->
        {name, %{url: info.url, healthy: info.healthy, last_check: state.last_check}}
      end)
      |> Map.new()

    {:reply, status, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    services = check_services_health(state.services)
    schedule_health_check()

    {:noreply, %{state | services: services, last_check: DateTime.utc_now()}}
  end

  # Private Functions

  defp load_services do
    Application.get_env(:nsai_gateway, :services, %{})
    |> Enum.map(fn {name, url} ->
      {name, %{url: url, healthy: true}}
    end)
    |> Map.new()
  end

  defp check_services_health(services) do
    services
    |> Enum.map(fn {name, info} ->
      healthy = check_health(info.url)
      {name, %{info | healthy: healthy}}
    end)
    |> Map.new()
  end

  defp check_health(url) do
    health_url = "#{url}/health"

    case Req.get(health_url, receive_timeout: 5_000) do
      {:ok, %{status: 200}} ->
        true

      {:ok, %{status: status}} ->
        Logger.warning("Health check failed for #{url}: status #{status}")
        false

      {:error, reason} ->
        Logger.warning("Health check failed for #{url}: #{inspect(reason)}")
        false
    end
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end
end
