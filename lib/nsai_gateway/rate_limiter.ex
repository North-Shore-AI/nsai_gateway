defmodule NsaiGateway.RateLimiter do
  @moduledoc """
  Rate limiting using Hammer with sliding window algorithm.

  Limits requests per tenant and per endpoint.
  """

  import Plug.Conn
  require Logger

  @doc """
  Checks rate limits for the current request.

  Returns the connection if within limits, or halts with 429 if rate limited.
  """
  @spec check(Plug.Conn.t()) :: Plug.Conn.t()
  def check(conn) do
    tenant = conn.assigns[:tenant] || "anonymous"
    endpoint = get_endpoint(conn)

    # Check both tenant-level and endpoint-level limits
    with :ok <- check_tenant_limit(tenant),
         :ok <- check_endpoint_limit(tenant, endpoint) do
      conn
    else
      {:error, :rate_limited} ->
        rate_limited(conn)
    end
  end

  defp check_tenant_limit(tenant) do
    limit = Application.get_env(:nsai_gateway, :tenant_rate_limit, 1000)
    # 1 minute
    window_ms = 60_000

    case Hammer.check_rate("tenant:#{tenant}", window_ms, limit) do
      {:allow, _count} ->
        :ok

      {:deny, _limit} ->
        Logger.warning("Rate limit exceeded for tenant: #{tenant}")
        {:error, :rate_limited}
    end
  end

  defp check_endpoint_limit(tenant, endpoint) do
    limit = get_endpoint_limit(endpoint)
    # 1 minute
    window_ms = 60_000

    case Hammer.check_rate("endpoint:#{tenant}:#{endpoint}", window_ms, limit) do
      {:allow, _count} ->
        :ok

      {:deny, _limit} ->
        Logger.warning("Rate limit exceeded for tenant #{tenant} on endpoint #{endpoint}")
        {:error, :rate_limited}
    end
  end

  defp get_endpoint(conn) do
    # Extract the service and first path segment
    case conn.path_info do
      ["api", "v1", service | _] -> service
      _ -> "unknown"
    end
  end

  defp get_endpoint_limit(endpoint) do
    limits = Application.get_env(:nsai_gateway, :endpoint_rate_limits, %{})
    Map.get(limits, endpoint, 100)
  end

  defp rate_limited(conn) do
    body =
      Jason.encode!(%{
        error: "Rate Limit Exceeded",
        message: "Too many requests. Please try again later."
      })

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("retry-after", "60")
    |> send_resp(429, body)
    |> halt()
  end
end
