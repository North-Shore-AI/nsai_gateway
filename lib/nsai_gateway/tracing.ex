defmodule NsaiGateway.Tracing do
  @moduledoc """
  Request tracing and structured logging with trace ID propagation.

  Provides distributed tracing capabilities by generating and propagating trace IDs
  across service boundaries. Integrates with structured logging for correlation.

  ## Headers

  - `X-Trace-Id`: Unique identifier for request tracing
  - `X-Request-Id`: Request-specific identifier
  - `X-Correlation-Id`: Cross-service correlation

  ## Usage

      # In a Plug pipeline
      plug NsaiGateway.Tracing

      # Manually
      conn = Tracing.generate_trace_id(conn)
      Tracing.log_request(conn, %{custom: "metadata"})
  """

  import Plug.Conn
  require Logger

  @behaviour Plug

  @trace_id_header "x-trace-id"
  @request_id_header "x-request-id"
  @correlation_id_header "x-correlation-id"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    start_time = System.monotonic_time()
    conn = ensure_trace_headers(conn)

    # Add trace context to Logger metadata
    Logger.metadata(
      trace_id: get_trace_id(conn),
      request_id: get_request_id(conn),
      tenant: conn.assigns[:tenant],
      method: conn.method,
      path: conn.request_path
    )

    conn
    |> register_before_send(fn conn ->
      log_request_complete(conn, start_time)
      conn
    end)
  end

  @doc """
  Ensures trace headers are present on the connection.

  Generates new IDs if not present, or uses existing headers from upstream.
  """
  @spec ensure_trace_headers(Plug.Conn.t()) :: Plug.Conn.t()
  def ensure_trace_headers(conn) do
    conn
    |> ensure_header(@trace_id_header)
    |> ensure_header(@request_id_header)
    |> ensure_header(@correlation_id_header)
    |> expose_trace_headers()
  end

  @doc """
  Gets the trace ID from the connection.
  """
  @spec get_trace_id(Plug.Conn.t()) :: String.t() | nil
  def get_trace_id(conn) do
    get_first_header(conn, @trace_id_header)
  end

  @doc """
  Gets the request ID from the connection.
  """
  @spec get_request_id(Plug.Conn.t()) :: String.t() | nil
  def get_request_id(conn) do
    get_first_header(conn, @request_id_header)
  end

  @doc """
  Logs structured request metadata.
  """
  @spec log_request(Plug.Conn.t(), map()) :: :ok
  def log_request(conn, metadata \\ %{}) do
    base_metadata = %{
      trace_id: get_trace_id(conn),
      request_id: get_request_id(conn),
      method: conn.method,
      path: conn.request_path,
      tenant: conn.assigns[:tenant],
      remote_ip: format_remote_ip(conn.remote_ip)
    }

    Logger.info("Request received", Map.merge(base_metadata, metadata))
  end

  @doc """
  Extracts trace headers for forwarding to backend services.
  """
  @spec extract_trace_headers(Plug.Conn.t()) :: map()
  def extract_trace_headers(conn) do
    %{
      @trace_id_header => get_trace_id(conn),
      @request_id_header => get_request_id(conn),
      @correlation_id_header => get_first_header(conn, @correlation_id_header)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  # Private functions

  defp ensure_header(conn, header_name) do
    case get_req_header(conn, header_name) do
      [] ->
        # Generate new ID
        id = generate_id()
        put_req_header(conn, header_name, id)

      [_existing | _] ->
        # Keep existing header
        conn
    end
  end

  defp expose_trace_headers(conn) do
    # Echo trace headers back in response for debugging
    conn
    |> put_resp_header(@trace_id_header, get_trace_id(conn))
    |> put_resp_header(@request_id_header, get_request_id(conn))
  end

  defp get_first_header(conn, header_name) do
    case get_req_header(conn, header_name) do
      [value | _] -> value
      [] -> nil
    end
  end

  defp log_request_complete(conn, start_time) do
    duration = System.monotonic_time() - start_time
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    metadata = %{
      trace_id: get_trace_id(conn),
      request_id: get_request_id(conn),
      status: conn.status,
      duration_ms: duration_ms,
      method: conn.method,
      path: conn.request_path,
      tenant: conn.assigns[:tenant]
    }

    level = status_to_log_level(conn.status)
    Logger.log(level, "Request completed", metadata)

    # Emit telemetry event
    :telemetry.execute(
      [:nsai_gateway, :request, :complete],
      %{duration: duration},
      metadata
    )
  end

  defp generate_id do
    # Generate a URL-safe base64 ID
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end

  defp format_remote_ip({a, b, c, d}) do
    "#{a}.#{b}.#{c}.#{d}"
  end

  defp format_remote_ip(ip), do: inspect(ip)

  defp status_to_log_level(status) when status >= 500, do: :error
  defp status_to_log_level(status) when status >= 400, do: :warning
  defp status_to_log_level(_status), do: :info
end
