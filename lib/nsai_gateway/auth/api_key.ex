defmodule NsaiGateway.Auth.ApiKey do
  @moduledoc """
  API Key authentication handler.

  In production, this would validate against a database or cache.
  For now, uses configured keys for demonstration.
  """

  @doc """
  Verifies an API key and returns the associated tenant.
  """
  @spec verify(String.t()) :: {:ok, String.t()} | {:error, :invalid_key}
  def verify(key) when is_binary(key) do
    api_keys = Application.get_env(:nsai_gateway, :api_keys, %{})

    case Map.get(api_keys, key) do
      nil -> {:error, :invalid_key}
      tenant -> {:ok, tenant}
    end
  end

  @spec verify(term()) :: {:error, :invalid_key}
  def verify(_), do: {:error, :invalid_key}

  @doc """
  Generates a new API key (for administrative use).
  """
  @spec generate() :: String.t()
  def generate do
    :crypto.strong_rand_bytes(32)
    |> Base.encode64(padding: false)
  end
end
