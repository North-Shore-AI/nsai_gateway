defmodule NsaiGateway.Auth.ApiKeyTest do
  use ExUnit.Case, async: true

  alias NsaiGateway.Auth.ApiKey

  describe "verify/1" do
    test "verifies valid API key" do
      assert {:ok, "tenant-alpha"} = ApiKey.verify("demo-key-1")
      assert {:ok, "tenant-beta"} = ApiKey.verify("demo-key-2")
    end

    test "rejects invalid API key" do
      assert {:error, :invalid_key} = ApiKey.verify("invalid-key")
    end

    test "rejects nil key" do
      assert {:error, :invalid_key} = ApiKey.verify(nil)
    end

    test "rejects non-string key" do
      assert {:error, :invalid_key} = ApiKey.verify(12345)
    end
  end

  describe "generate/0" do
    test "generates a valid base64 encoded key" do
      key = ApiKey.generate()

      assert is_binary(key)
      assert String.length(key) > 0
      assert String.match?(key, ~r/^[A-Za-z0-9\+\/\-_]+$/)
    end

    test "generates unique keys" do
      key1 = ApiKey.generate()
      key2 = ApiKey.generate()

      assert key1 != key2
    end
  end
end
