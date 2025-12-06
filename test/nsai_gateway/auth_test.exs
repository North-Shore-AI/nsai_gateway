defmodule NsaiGateway.AuthTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias NsaiGateway.Auth
  alias NsaiGateway.Auth.JWT

  describe "authenticate/1" do
    test "authenticates with valid API key" do
      conn =
        conn(:get, "/api/v1/jobs")
        |> put_req_header("authorization", "ApiKey demo-key-1")

      result = Auth.authenticate(conn)

      assert result.assigns[:authenticated] == true
      assert result.assigns[:auth_method] == :api_key
      assert result.assigns[:tenant] == "tenant-alpha"
      refute result.halted
    end

    test "rejects invalid API key" do
      conn =
        conn(:get, "/api/v1/jobs")
        |> put_req_header("authorization", "ApiKey invalid-key")

      result = Auth.authenticate(conn)

      assert result.halted
      assert result.status == 401
    end

    test "authenticates with valid JWT token" do
      {:ok, token, _claims} = JWT.generate("tenant-alpha", "user-123", 3600)

      conn =
        conn(:get, "/api/v1/jobs")
        |> put_req_header("authorization", "Bearer #{token}")

      result = Auth.authenticate(conn)

      assert result.assigns[:authenticated] == true
      assert result.assigns[:auth_method] == :jwt
      assert result.assigns[:tenant] == "tenant-alpha"
      assert result.assigns[:user_id] == "user-123"
      refute result.halted
    end

    test "rejects invalid JWT token" do
      conn =
        conn(:get, "/api/v1/jobs")
        |> put_req_header("authorization", "Bearer invalid.token.here")

      result = Auth.authenticate(conn)

      assert result.halted
      assert result.status == 401
    end

    test "rejects requests with no authentication" do
      conn = conn(:get, "/api/v1/jobs")

      result = Auth.authenticate(conn)

      assert result.halted
      assert result.status == 401
    end
  end
end
