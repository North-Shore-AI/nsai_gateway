defmodule NsaiGateway.Telemetry do
  @moduledoc """
  Telemetry setup for the API Gateway.

  Tracks request metrics, latency, error rates, and service health.
  """

  use Supervisor
  require Logger

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Telemetry handler
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Returns the telemetry setup for use in the application supervisor.
  """
  def setup do
    [
      name: __MODULE__,
      measurements: periodic_measurements(),
      period: 10_000
    ]
  end

  @doc """
  Attaches telemetry handlers for logging and metrics.
  """
  def attach_handlers do
    events = [
      [:nsai_gateway, :proxy, :success],
      [:nsai_gateway, :proxy, :error],
      [:nsai_gateway, :auth, :success],
      [:nsai_gateway, :auth, :failure],
      [:nsai_gateway, :rate_limit, :exceeded]
    ]

    :telemetry.attach_many(
      "nsai-gateway-handler",
      events,
      &handle_event/4,
      nil
    )
  end

  defp periodic_measurements do
    [
      {__MODULE__, :system_memory, []},
      {__MODULE__, :process_count, []}
    ]
  end

  def system_memory do
    :erlang.memory(:total)
  end

  def process_count do
    :erlang.system_info(:process_count)
  end

  # Event handlers

  def handle_event([:nsai_gateway, :proxy, :success], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.info(
      "Proxy success: service=#{metadata.service} status=#{metadata.status} duration=#{duration_ms}ms"
    )
  end

  def handle_event([:nsai_gateway, :proxy, :error], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.error(
      "Proxy error: service=#{metadata.service} reason=#{inspect(metadata.reason)} duration=#{duration_ms}ms"
    )
  end

  def handle_event([:nsai_gateway, :auth, :success], _measurements, metadata, _config) do
    Logger.debug("Authentication success: method=#{metadata.method} tenant=#{metadata.tenant}")
  end

  def handle_event([:nsai_gateway, :auth, :failure], _measurements, metadata, _config) do
    Logger.warning("Authentication failure: reason=#{inspect(metadata.reason)}")
  end

  def handle_event([:nsai_gateway, :rate_limit, :exceeded], _measurements, metadata, _config) do
    Logger.warning("Rate limit exceeded: tenant=#{metadata.tenant} endpoint=#{metadata.endpoint}")
  end

  def handle_event(_event, _measurements, _metadata, _config) do
    :ok
  end
end
