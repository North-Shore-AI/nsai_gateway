defmodule NsaiGateway.CircuitBreaker do
  @moduledoc """
  Circuit Breaker pattern implementation for backend service resilience.

  Protects backend services from cascading failures by monitoring errors
  and temporarily opening the circuit when error thresholds are exceeded.

  ## States

  - **Closed**: Normal operation, requests pass through
  - **Open**: Circuit tripped, requests fail fast without hitting backend
  - **Half-Open**: Testing if service has recovered

  ## Configuration

      config :nsai_gateway, :circuit_breaker,
        error_threshold: 5,      # Errors before opening circuit
        timeout: 60_000,         # Time before half-open attempt (ms)
        success_threshold: 2     # Successes needed to close circuit

  ## Usage

      CircuitBreaker.call("work_service", fn ->
        # Make backend request
        Req.get("http://work-service/health")
      end)
  """

  require Logger

  @type service_name :: String.t()
  @type result :: {:ok, term()} | {:error, term()}

  @doc """
  Executes a function with circuit breaker protection.

  Returns `{:ok, result}` if successful, `{:error, reason}` if failed or circuit is open.
  """
  @spec call(service_name(), (-> result())) :: result()
  def call(service_name, fun) when is_function(fun, 0) do
    fuse_name = fuse_name(service_name)

    case :fuse.ask(fuse_name, :sync) do
      :ok ->
        execute_with_fuse(fuse_name, fun)

      :blown ->
        Logger.warning("Circuit breaker open for service: #{service_name}")
        {:error, :circuit_open}

      {:error, :not_found} ->
        # Fuse doesn't exist yet, install it
        install_fuse(fuse_name)
        execute_with_fuse(fuse_name, fun)
    end
  end

  @doc """
  Gets the current circuit state for a service.
  """
  @spec get_state(service_name()) :: :ok | :blown | :not_found
  def get_state(service_name) do
    fuse_name = fuse_name(service_name)

    case :fuse.ask(fuse_name, :sync) do
      :ok -> :closed
      :blown -> :open
      {:error, :not_found} -> :not_found
    end
  end

  @doc """
  Manually resets a circuit breaker.
  """
  @spec reset(service_name()) :: :ok
  def reset(service_name) do
    fuse_name = fuse_name(service_name)
    :fuse.reset(fuse_name)
    Logger.info("Circuit breaker reset for service: #{service_name}")
    :ok
  end

  @doc """
  Gets statistics for all circuit breakers.

  Note: Returns empty map as fuse doesn't expose a list of all breakers.
  Use get_state/1 for individual circuit status.
  """
  @spec stats() :: map()
  def stats do
    # Fuse doesn't provide a way to list all circuit breakers
    # Return empty map for now
    %{}
  end

  # Private functions

  defp execute_with_fuse(fuse_name, fun) do
    try do
      case fun.() do
        {:ok, _result} = success ->
          # Melt the fuse on success (helps recovery)
          :fuse.melt(fuse_name)
          success

        {:error, _reason} = error ->
          # Blow the fuse on error
          :fuse.melt(fuse_name)
          error
      end
    catch
      kind, reason ->
        # Blow the fuse on exception
        :fuse.melt(fuse_name)
        Logger.error("Circuit breaker caught #{kind}: #{inspect(reason)}")
        {:error, :exception}
    end
  end

  defp install_fuse(fuse_name) do
    config = get_config()

    # Fuse options must be a tuple, not a map
    fuse_options = {{:standard, config.error_threshold, config.timeout}, {:reset, config.timeout}}

    case :fuse.install(fuse_name, fuse_options) do
      :ok ->
        Logger.info("Installed circuit breaker: #{fuse_name}")
        :ok

      {:error, :already_installed} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to install circuit breaker: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fuse_name(service_name) do
    String.to_atom("circuit_breaker_#{service_name}")
  end

  defp get_config do
    config = Application.get_env(:nsai_gateway, :circuit_breaker, [])

    %{
      error_threshold: Keyword.get(config, :error_threshold, 5),
      timeout: Keyword.get(config, :timeout, 60_000),
      success_threshold: Keyword.get(config, :success_threshold, 2)
    }
  end
end
