defmodule NsaiGateway.Auth.ApiKeyManagerTest do
  use ExUnit.Case, async: false

  alias NsaiGateway.Auth.ApiKeyManager

  # ApiKeyManager is already started by the application
  # No need to start_supervised!

  describe "create_key/2" do
    test "creates a new API key for a tenant" do
      assert {:ok, %{key_id: key_id, api_key: api_key}} = ApiKeyManager.create_key("test-tenant")

      assert is_binary(key_id)
      assert is_binary(api_key)
      assert String.length(api_key) > 0
    end

    test "creates keys with expiration" do
      assert {:ok, %{api_key: api_key}} =
               ApiKeyManager.create_key("test-tenant", expires_in: 3600)

      assert {:ok, info} = ApiKeyManager.get_key_info(api_key)
      assert %DateTime{} = info.expires_at
    end

    test "creates keys with metadata" do
      assert {:ok, %{api_key: api_key}} =
               ApiKeyManager.create_key("test-tenant", metadata: %{env: "production"})

      assert {:ok, info} = ApiKeyManager.get_key_info(api_key)
      assert info.metadata.env == "production"
    end
  end

  describe "verify_key/1" do
    test "verifies a valid key" do
      {:ok, %{api_key: api_key}} = ApiKeyManager.create_key("test-tenant")

      assert {:ok, "test-tenant"} = ApiKeyManager.verify_key(api_key)
    end

    test "rejects an invalid key" do
      assert {:error, :invalid_key} = ApiKeyManager.verify_key("invalid-key")
    end

    test "rejects a revoked key" do
      {:ok, %{api_key: api_key}} = ApiKeyManager.create_key("test-tenant")
      :ok = ApiKeyManager.revoke_key(api_key)

      assert {:error, :revoked} = ApiKeyManager.verify_key(api_key)
    end

    test "rejects an expired key" do
      {:ok, %{api_key: api_key}} = ApiKeyManager.create_key("test-tenant", expires_in: -1)

      assert {:error, :expired} = ApiKeyManager.verify_key(api_key)
    end
  end

  describe "rotate_key/1" do
    test "rotates a key successfully" do
      {:ok, %{api_key: old_key}} = ApiKeyManager.create_key("test-tenant")

      assert {:ok, %{old_key_id: _old_id, new_key_id: _new_id, new_api_key: new_key}} =
               ApiKeyManager.rotate_key(old_key)

      # Old key should be revoked
      assert {:error, :revoked} = ApiKeyManager.verify_key(old_key)

      # New key should be valid
      assert {:ok, "test-tenant"} = ApiKeyManager.verify_key(new_key)
    end

    test "cannot rotate a non-existent key" do
      assert {:error, :not_found} = ApiKeyManager.rotate_key("non-existent-key")
    end

    test "cannot rotate an already revoked key" do
      {:ok, %{api_key: api_key}} = ApiKeyManager.create_key("test-tenant")
      :ok = ApiKeyManager.revoke_key(api_key)

      assert {:error, :already_revoked} = ApiKeyManager.rotate_key(api_key)
    end
  end

  describe "revoke_key/1" do
    test "revokes a key successfully" do
      {:ok, %{api_key: api_key}} = ApiKeyManager.create_key("test-tenant")

      assert :ok = ApiKeyManager.revoke_key(api_key)
      assert {:error, :revoked} = ApiKeyManager.verify_key(api_key)
    end

    test "cannot revoke a non-existent key" do
      assert {:error, :not_found} = ApiKeyManager.revoke_key("non-existent-key")
    end

    test "cannot revoke an already revoked key" do
      {:ok, %{api_key: api_key}} = ApiKeyManager.create_key("test-tenant")
      :ok = ApiKeyManager.revoke_key(api_key)

      assert {:error, :already_revoked} = ApiKeyManager.revoke_key(api_key)
    end
  end

  describe "list_keys/1" do
    test "lists all keys for a tenant" do
      ApiKeyManager.create_key("tenant-a")
      ApiKeyManager.create_key("tenant-a")
      ApiKeyManager.create_key("tenant-b")

      keys = ApiKeyManager.list_keys("tenant-a")
      assert length(keys) == 2
      assert Enum.all?(keys, fn key -> key.tenant == "tenant-a" end)
    end

    test "returns empty list for tenant with no keys" do
      assert [] = ApiKeyManager.list_keys("unknown-tenant")
    end
  end
end
