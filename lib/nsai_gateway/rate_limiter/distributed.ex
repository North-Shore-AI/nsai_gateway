defmodule NsaiGateway.RateLimiter.Distributed do
  @moduledoc """
  Distributed rate limiting with Redis backend support.

  Provides rate limiting that works across multiple gateway instances using Redis.
  Falls back to local Hammer backend if Redis is not available.

  ## Configuration

      config :nsai_gateway, :rate_limiter,
        backend: :redis,  # or :local
        redis_url: "redis://localhost:6379",
        burst_allowance: 1.2  # Allow 20% burst above normal limit
  """

  import Plug.Conn
  require Logger

  @type limit_info :: %{
          limit: pos_integer(),
          remaining: non_neg_integer(),
          reset_at: non_neg_integer()
        }

  @doc """
  Checks rate limits and adds rate limit headers to the response.

  Returns the connection with rate limit headers or halts with 429 if limited.
  """
  @spec check(Plug.Conn.t()) :: Plug.Conn.t()
  def check(conn) do
    tenant = conn.assigns[:tenant] || "anonymous"
    endpoint = get_endpoint(conn)

    # Check tenant-level limit
    case check_limit("tenant:#{tenant}", get_tenant_limit(), get_window_ms()) do
      {:allow, tenant_info} ->
        conn = add_rate_limit_headers(conn, tenant_info)

        # Check endpoint-specific limit
        case check_limit(
               "endpoint:#{tenant}:#{endpoint}",
               get_endpoint_limit(endpoint),
               get_window_ms()
             ) do
          {:allow, endpoint_info} ->
            add_rate_limit_headers(conn, endpoint_info, "Endpoint")

          {:deny, endpoint_info} ->
            rate_limited(conn, endpoint_info)
        end

      {:deny, tenant_info} ->
        rate_limited(conn, tenant_info)
    end
  end

  @doc """
  Checks a specific rate limit bucket.
  """
  @spec check_limit(String.t(), pos_integer(), pos_integer()) ::
          {:allow, limit_info()} | {:deny, limit_info()}
  def check_limit(bucket, limit, window_ms) do
    backend = get_backend()
    burst_limit = apply_burst_allowance(limit)

    case backend do
      :redis ->
        check_redis_limit(bucket, burst_limit, limit, window_ms)

      :local ->
        check_local_limit(bucket, burst_limit, limit, window_ms)
    end
  end

  # Private functions

  defp check_redis_limit(_bucket, _burst_limit, limit, window_ms) do
    # TODO: Implement Redis-based rate limiting
    # For now, fall back to local
    Logger.warning("Redis backend not yet implemented, falling back to local")
    check_local_limit("fallback", limit, limit, window_ms)
  end

  defp check_local_limit(bucket, burst_limit, base_limit, window_ms) do
    case Hammer.check_rate(bucket, window_ms, burst_limit) do
      {:allow, count} ->
        remaining = max(0, burst_limit - count)
        reset_at = calculate_reset_time(window_ms)

        {:allow, %{limit: base_limit, remaining: remaining, reset_at: reset_at}}

      {:deny, _limit} ->
        reset_at = calculate_reset_time(window_ms)

        {:deny, %{limit: base_limit, remaining: 0, reset_at: reset_at}}
    end
  end

  defp add_rate_limit_headers(conn, limit_info, prefix \\ "") do
    prefix = if prefix == "", do: "", else: "#{prefix}-"

    conn
    |> put_resp_header("x-ratelimit-#{prefix}limit", to_string(limit_info.limit))
    |> put_resp_header("x-ratelimit-#{prefix}remaining", to_string(limit_info.remaining))
    |> put_resp_header("x-ratelimit-#{prefix}reset", to_string(limit_info.reset_at))
  end

  defp rate_limited(conn, limit_info) do
    retry_after = max(1, div(limit_info.reset_at - unix_now(), 1000))

    body =
      Jason.encode!(%{
        error: "Rate Limit Exceeded",
        message: "Too many requests. Please try again later.",
        limit: limit_info.limit,
        reset_at: limit_info.reset_at
      })

    conn
    |> add_rate_limit_headers(limit_info)
    |> put_resp_content_type("application/json")
    |> put_resp_header("retry-after", to_string(retry_after))
    |> send_resp(429, body)
    |> halt()
  end

  defp get_endpoint(conn) do
    case conn.path_info do
      ["api", "v1", service | _] -> service
      _ -> "unknown"
    end
  end

  defp get_backend do
    Application.get_env(:nsai_gateway, :rate_limiter, [])
    |> Keyword.get(:backend, :local)
  end

  defp get_tenant_limit do
    Application.get_env(:nsai_gateway, :tenant_rate_limit, 1000)
  end

  defp get_endpoint_limit(endpoint) do
    limits = Application.get_env(:nsai_gateway, :endpoint_rate_limits, %{})
    Map.get(limits, endpoint, 100)
  end

  defp get_window_ms do
    # 1 minute window
    60_000
  end

  defp apply_burst_allowance(limit) do
    burst =
      Application.get_env(:nsai_gateway, :rate_limiter, []) |> Keyword.get(:burst_allowance, 1.2)

    round(limit * burst)
  end

  defp calculate_reset_time(window_ms) do
    unix_now() + window_ms
  end

  defp unix_now do
    System.system_time(:millisecond)
  end
end
