defmodule NsaiGateway.Proxy do
  @moduledoc """
  HTTP proxy for forwarding requests to backend services.

  Handles service discovery, request forwarding, and response proxying
  with retry logic and error handling.
  """

  import Plug.Conn
  require Logger

  alias NsaiGateway.{CircuitBreaker, Tracing}

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    service = Keyword.get(opts, :service)
    tenant = conn.assigns[:tenant]

    start_time = System.monotonic_time()

    case proxy_request(conn, service, tenant) do
      {:ok, response} ->
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          [:nsai_gateway, :proxy, :success],
          %{duration: duration},
          %{service: service, status: response.status, tenant: tenant}
        )

        send_response(conn, response)

      {:error, reason} ->
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          [:nsai_gateway, :proxy, :error],
          %{duration: duration},
          %{service: service, reason: reason, tenant: tenant}
        )

        Logger.error("Proxy error for service #{service}: #{inspect(reason)}")
        send_error(conn, reason)
    end
  end

  defp proxy_request(conn, service, tenant) do
    with {:ok, backend_url} <- resolve_service(service, tenant),
         {:ok, forwarded_path} <- build_path(conn) do
      forward_request(backend_url, forwarded_path, conn)
    end
  end

  defp resolve_service(service, _tenant) do
    # For now, use configured service URLs
    # In production, this would use nsai_registry for service discovery
    base_url =
      Application.get_env(:nsai_gateway, :services, %{})
      |> Map.get(service)

    case base_url do
      nil -> {:error, :service_not_found}
      url -> {:ok, url}
    end
  end

  defp build_path(conn) do
    # Strip the /api/v1/{service} prefix
    path =
      conn.path_info
      |> Enum.drop(3)
      |> Enum.join("/")

    path = if path == "", do: "/", else: "/#{path}"

    # Add query string if present
    path =
      if conn.query_string && conn.query_string != "" do
        "#{path}?#{conn.query_string}"
      else
        path
      end

    {:ok, path}
  end

  defp forward_request(base_url, path, conn) do
    url = "#{base_url}#{path}"
    headers = build_headers(conn)
    body = extract_body(conn)
    service = extract_service(base_url)

    # Use circuit breaker for resilience
    CircuitBreaker.call(service, fn ->
      case Req.request(
             method: String.downcase(conn.method) |> String.to_atom(),
             url: url,
             headers: headers,
             body: body,
             retry: :transient,
             max_retries: 3,
             retry_delay: fn attempt -> 100 * :math.pow(2, attempt) end,
             receive_timeout: 30_000
           ) do
        {:ok, %Req.Response{} = response} ->
          {:ok, response}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  defp build_headers(conn) do
    # Forward most headers, but filter out some
    filtered_headers = ["host", "connection", "content-length"]

    base_headers =
      conn.req_headers
      |> Enum.reject(fn {name, _} -> name in filtered_headers end)
      |> Map.new()

    # Add trace headers
    trace_headers = Tracing.extract_trace_headers(conn)

    Map.merge(base_headers, trace_headers)
  end

  defp extract_service(base_url) do
    # Extract service name from URL for circuit breaker
    base_url
    |> String.replace(~r/^https?:\/\//, "")
    |> String.split(":")
    |> List.first()
    |> String.replace(".", "_")
  end

  defp extract_body(conn) do
    case Plug.Conn.read_body(conn, []) do
      {:ok, body, _conn} -> body
      {:more, _partial, _conn} -> ""
      _ -> ""
    end
  end

  defp send_response(conn, response) do
    conn = %{conn | resp_headers: response.headers}

    conn
    |> send_resp(response.status, response.body || "")
  end

  defp send_error(conn, :service_not_found) do
    body = Jason.encode!(%{error: "Service not found"})
    send_resp(conn, 502, body)
  end

  defp send_error(conn, :circuit_open) do
    body = Jason.encode!(%{error: "Service Unavailable", message: "Circuit breaker is open"})
    send_resp(conn, 503, body)
  end

  defp send_error(conn, _reason) do
    body = Jason.encode!(%{error: "Bad Gateway"})
    send_resp(conn, 502, body)
  end
end
