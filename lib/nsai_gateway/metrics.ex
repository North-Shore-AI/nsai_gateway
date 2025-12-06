defmodule NsaiGateway.Metrics do
  @moduledoc """
  Prometheus-compatible metrics endpoint and collectors.

  Exposes gateway metrics in Prometheus text format for scraping.

  ## Metrics

  ### Counters
  - `nsai_gateway_requests_total` - Total requests by method, path, status
  - `nsai_gateway_auth_failures_total` - Authentication failures by method
  - `nsai_gateway_rate_limits_total` - Rate limit violations by tenant

  ### Histograms
  - `nsai_gateway_request_duration_seconds` - Request latency distribution
  - `nsai_gateway_proxy_duration_seconds` - Backend proxy latency

  ### Gauges
  - `nsai_gateway_active_connections` - Current active connections
  - `nsai_gateway_circuit_breaker_state` - Circuit breaker states (0=closed, 1=open)

  ## Usage

      # Start metrics collector
      NsaiGateway.Metrics.setup()

      # Access metrics endpoint
      GET /metrics
  """

  require Logger

  @type metric :: {String.t(), map(), number()}

  # Metric definitions
  @metrics %{
    requests_total: %{
      type: :counter,
      name: "nsai_gateway_requests_total",
      help: "Total number of HTTP requests",
      labels: [:method, :path, :status, :tenant]
    },
    request_duration: %{
      type: :histogram,
      name: "nsai_gateway_request_duration_seconds",
      help: "HTTP request latency in seconds",
      labels: [:method, :path, :tenant],
      buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
    },
    auth_failures: %{
      type: :counter,
      name: "nsai_gateway_auth_failures_total",
      help: "Total authentication failures",
      labels: [:method, :tenant]
    },
    rate_limits: %{
      type: :counter,
      name: "nsai_gateway_rate_limits_total",
      help: "Total rate limit violations",
      labels: [:tenant, :endpoint]
    },
    proxy_duration: %{
      type: :histogram,
      name: "nsai_gateway_proxy_duration_seconds",
      help: "Backend proxy request latency in seconds",
      labels: [:service, :tenant],
      buckets: [0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
    },
    circuit_breaker_state: %{
      type: :gauge,
      name: "nsai_gateway_circuit_breaker_state",
      help: "Circuit breaker state (0=closed, 1=open)",
      labels: [:service]
    },
    active_connections: %{
      type: :gauge,
      name: "nsai_gateway_active_connections",
      help: "Number of active connections"
    }
  }

  @doc """
  Sets up telemetry handlers for metrics collection.
  """
  @spec setup() :: :ok
  def setup do
    events = [
      [:nsai_gateway, :request, :complete],
      [:nsai_gateway, :proxy, :success],
      [:nsai_gateway, :proxy, :error],
      [:nsai_gateway, :auth, :failure],
      [:nsai_gateway, :rate_limit, :exceeded]
    ]

    :telemetry.attach_many(
      "nsai-gateway-metrics",
      events,
      &handle_event/4,
      nil
    )
  end

  @doc """
  Renders metrics in Prometheus text format.
  """
  @spec render() :: String.t()
  def render do
    metrics = collect_metrics()

    Enum.map_join(metrics, "\n", fn {name, help, type, values} ->
      help_line = "# HELP #{name} #{help}\n"
      type_line = "# TYPE #{name} #{type}\n"

      value_lines =
        Enum.map_join(values, "\n", fn {labels, value} ->
          label_str = format_labels(labels)
          "#{name}#{label_str} #{value}"
        end)

      "#{help_line}#{type_line}#{value_lines}"
    end) <> "\n"
  end

  @doc """
  Handles telemetry events and updates metrics.
  """
  @spec handle_event(list(atom()), map(), map(), term()) :: :ok
  def handle_event([:nsai_gateway, :request, :complete], measurements, metadata, _config) do
    duration_seconds = System.convert_time_unit(measurements.duration, :native, :second)

    # Increment request counter
    increment_counter(:requests_total, %{
      method: metadata.method,
      path: truncate_path(metadata.path),
      status: metadata.status,
      tenant: metadata.tenant || "anonymous"
    })

    # Record request duration
    observe_histogram(:request_duration, duration_seconds, %{
      method: metadata.method,
      path: truncate_path(metadata.path),
      tenant: metadata.tenant || "anonymous"
    })

    :ok
  end

  def handle_event([:nsai_gateway, :proxy, :success], measurements, metadata, _config) do
    duration_seconds = System.convert_time_unit(measurements.duration, :native, :second)

    observe_histogram(:proxy_duration, duration_seconds, %{
      service: metadata[:service] || "unknown",
      tenant: metadata[:tenant] || "anonymous"
    })

    :ok
  end

  def handle_event([:nsai_gateway, :proxy, :error], _measurements, _metadata, _config) do
    # Could track proxy errors here
    :ok
  end

  def handle_event([:nsai_gateway, :auth, :failure], _measurements, metadata, _config) do
    increment_counter(:auth_failures, %{
      method: metadata.method || "unknown",
      tenant: metadata.tenant || "anonymous"
    })

    :ok
  end

  def handle_event([:nsai_gateway, :rate_limit, :exceeded], _measurements, metadata, _config) do
    increment_counter(:rate_limits, %{
      tenant: metadata.tenant,
      endpoint: metadata.endpoint
    })

    :ok
  end

  def handle_event(_event, _measurements, _metadata, _config) do
    :ok
  end

  # Private functions - Metric storage

  # In a real implementation, these would use a proper metrics library like Telemetry.Metrics
  # with a reporter. For now, we'll use ETS tables for simplicity.

  defp increment_counter(metric_name, labels) do
    table_name = metric_table_name(metric_name)
    ensure_table(table_name)

    key = {metric_name, labels}

    :ets.update_counter(table_name, key, {2, 1}, {key, 0})
    :ok
  end

  defp observe_histogram(metric_name, value, labels) do
    table_name = metric_table_name(metric_name)
    ensure_table(table_name)

    # Store individual observations (in production, would use proper histogram buckets)
    key = {metric_name, labels, System.monotonic_time()}
    :ets.insert(table_name, {key, value})

    :ok
  end

  defp collect_metrics do
    Enum.flat_map(@metrics, fn {metric_key, config} ->
      table_name = metric_table_name(metric_key)

      case :ets.whereis(table_name) do
        :undefined ->
          []

        _tid ->
          values = collect_metric_values(table_name, config.type)
          [{config.name, config.help, config.type, values}]
      end
    end)
  end

  defp collect_metric_values(table_name, :counter) do
    :ets.tab2list(table_name)
    |> Enum.map(fn {{_metric, labels}, count} -> {labels, count} end)
  end

  defp collect_metric_values(table_name, :histogram) do
    # Simplified histogram - in production would use proper buckets
    :ets.tab2list(table_name)
    |> Enum.group_by(fn {{_metric, labels, _ts}, _value} -> labels end)
    |> Enum.flat_map(fn {labels, observations} ->
      values = Enum.map(observations, fn {_, value} -> value end)

      if Enum.empty?(values) do
        []
      else
        sum = Enum.sum(values)
        count = length(values)

        [
          {Map.put(labels, :le, "+Inf"), count},
          {Map.put(labels, :type, "sum"), sum},
          {Map.put(labels, :type, "count"), count}
        ]
      end
    end)
  end

  defp collect_metric_values(table_name, :gauge) do
    :ets.tab2list(table_name)
    |> Enum.map(fn {{_metric, labels}, value} -> {labels, value} end)
  end

  defp metric_table_name(metric_key) do
    String.to_atom("nsai_metrics_#{metric_key}")
  end

  defp ensure_table(table_name) do
    case :ets.whereis(table_name) do
      :undefined ->
        :ets.new(table_name, [:named_table, :public, :set, {:write_concurrency, true}])

      _tid ->
        :ok
    end
  end

  defp format_labels(labels) when map_size(labels) == 0, do: ""

  defp format_labels(labels) do
    label_str =
      Enum.map_join(labels, ",", fn {k, v} -> ~s(#{k}="#{escape_label_value(v)}") end)

    "{#{label_str}}"
  end

  defp escape_label_value(value) when is_binary(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end

  defp escape_label_value(value), do: to_string(value)

  defp truncate_path(path) do
    # Truncate dynamic path segments to reduce cardinality
    path
    |> String.split("/")
    |> Enum.take(4)
    |> Enum.join("/")
  end
end
