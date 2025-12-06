defmodule NsaiGateway.Auth.JWT do
  @moduledoc """
  JWT token authentication handler.

  Uses Joken for JWT verification with configurable signing keys.
  """

  use Joken.Config

  @doc """
  Verifies a JWT token and returns the claims.
  """
  @spec verify_token(String.t()) :: {:ok, map()} | {:error, term()}
  def verify_token(token) when is_binary(token) do
    signer = get_signer()
    config = build_token_config()
    Joken.verify_and_validate(config, token, signer)
  end

  @doc """
  Generates a JWT token for a tenant (for testing/administrative use).
  """
  @spec generate(String.t(), String.t(), integer()) :: {:ok, String.t(), map()} | {:error, term()}
  def generate(tenant, user_id, _ttl_seconds \\ 3600) do
    signer = get_signer()

    extra_claims = %{
      "tenant" => tenant,
      "sub" => user_id
    }

    config = build_token_config()
    Joken.generate_and_sign(config, extra_claims, signer)
  end

  @impl Joken.Config
  def token_config do
    default_claims(skip: [:aud, :iss])
  end

  defp build_token_config do
    default_claims(skip: [:aud, :iss])
  end

  defp get_signer do
    secret = Application.get_env(:nsai_gateway, :jwt_secret, "default-secret-change-me")
    Joken.Signer.create("HS256", secret)
  end
end
