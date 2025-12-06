defmodule NsaiGateway.Auth.JWTTest do
  use ExUnit.Case, async: true

  alias NsaiGateway.Auth.JWT

  describe "generate/3 and verify/1" do
    test "generates and verifies valid JWT token" do
      {:ok, token, claims} = JWT.generate("tenant-alpha", "user-123")

      assert is_binary(token)
      assert claims["tenant"] == "tenant-alpha"
      assert claims["sub"] == "user-123"

      assert {:ok, verified_claims} = JWT.verify_token(token)
      assert verified_claims["tenant"] == "tenant-alpha"
      assert verified_claims["sub"] == "user-123"
    end

    test "generates token with custom TTL" do
      {:ok, token, claims} = JWT.generate("tenant-beta", "user-456", 1800)

      assert is_binary(token)
      assert claims["tenant"] == "tenant-beta"

      assert {:ok, _verified_claims} = JWT.verify_token(token)
    end

    test "rejects invalid token" do
      assert {:error, _reason} = JWT.verify_token("invalid.jwt.token")
    end

    test "rejects malformed token" do
      assert {:error, _reason} = JWT.verify_token("not-even-a-jwt")
    end
  end
end
