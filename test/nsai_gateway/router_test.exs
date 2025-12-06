defmodule NsaiGateway.RouterTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias NsaiGateway.Router

  @opts Router.init([])

  describe "health endpoint" do
    test "returns healthy status" do
      conn = conn(:get, "/health") |> Router.call(@opts)

      assert conn.status == 200

      assert Jason.decode!(conn.resp_body) == %{
               "status" => "healthy",
               "service" => "nsai_gateway"
             }
    end

    test "does not require authentication" do
      # No auth header
      conn = conn(:get, "/health") |> Router.call(@opts)

      assert conn.status == 200
    end
  end

  describe "authentication" do
    test "requires authentication for API routes" do
      conn = conn(:get, "/api/v1/jobs") |> Router.call(@opts)

      assert conn.status == 401
      assert conn.halted
    end

    test "allows authenticated requests" do
      conn =
        conn(:get, "/api/v1/jobs")
        |> put_req_header("authorization", "ApiKey demo-key-1")
        |> Router.call(@opts)

      # Will get 502 (bad gateway) since backend is not available,
      # but authentication passed
      assert conn.status in [404, 502]
      refute conn.assigns[:authenticated] == nil
    end
  end

  describe "unknown routes" do
    test "returns 404 for unmatched routes" do
      conn =
        conn(:get, "/unknown/path")
        |> put_req_header("authorization", "ApiKey demo-key-1")
        |> Router.call(@opts)

      assert conn.status == 404
      assert Jason.decode!(conn.resp_body) == %{"error" => "Not Found"}
    end
  end
end
