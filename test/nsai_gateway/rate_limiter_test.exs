defmodule NsaiGateway.RateLimiterTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias NsaiGateway.RateLimiter

  setup do
    # Clear Hammer state between tests
    :ets.delete_all_objects(:hammer_ets_buckets)
    :ok
  end

  describe "check/1" do
    test "allows requests under the limit" do
      conn =
        conn(:get, "/api/v1/jobs")
        |> assign(:tenant, "test-tenant")

      result = RateLimiter.check(conn)

      refute result.halted
    end

    test "rate limits tenant after exceeding limit" do
      # Set a low limit for testing
      Application.put_env(:nsai_gateway, :tenant_rate_limit, 5)

      conn_base =
        conn(:get, "/api/v1/jobs")
        |> assign(:tenant, "test-tenant-2")

      # Make requests up to the limit
      for _ <- 1..5 do
        result = RateLimiter.check(conn_base)
        refute result.halted
      end

      # Next request should be rate limited
      result = RateLimiter.check(conn_base)
      assert result.halted
      assert result.status == 429

      # Reset limit
      Application.put_env(:nsai_gateway, :tenant_rate_limit, 1000)
    end

    test "rate limits endpoint after exceeding limit" do
      # Set a low endpoint limit
      Application.put_env(:nsai_gateway, :endpoint_rate_limits, %{"jobs" => 3})

      conn_base =
        conn(:get, "/api/v1/jobs/list")
        |> assign(:tenant, "test-tenant-3")

      # Make requests up to the endpoint limit
      for _ <- 1..3 do
        result = RateLimiter.check(conn_base)
        refute result.halted
      end

      # Next request should be rate limited
      result = RateLimiter.check(conn_base)
      assert result.halted
      assert result.status == 429

      # Reset limits
      Application.delete_env(:nsai_gateway, :endpoint_rate_limits)
    end

    test "includes retry-after header in rate limit response" do
      Application.put_env(:nsai_gateway, :tenant_rate_limit, 1)

      conn_base =
        conn(:get, "/api/v1/jobs")
        |> assign(:tenant, "test-tenant-4")

      # First request allowed
      RateLimiter.check(conn_base)

      # Second request rate limited
      result = RateLimiter.check(conn_base)

      assert result.halted
      assert get_resp_header(result, "retry-after") == ["60"]

      # Reset limit
      Application.put_env(:nsai_gateway, :tenant_rate_limit, 1000)
    end
  end
end
