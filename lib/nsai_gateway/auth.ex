defmodule NsaiGateway.Auth do
  @moduledoc """
  Authentication layer for the API Gateway.

  Supports both API key and JWT token authentication.
  """

  import Plug.Conn
  require Logger

  alias NsaiGateway.Auth.{ApiKey, JWT}

  @doc """
  Authenticates the connection using either API key or JWT token.
  """
  def authenticate(conn) do
    case get_auth_header(conn) do
      {:bearer, token} ->
        authenticate_jwt(conn, token)

      {:api_key, key} ->
        authenticate_api_key(conn, key)

      :none ->
        unauthorized(conn, "Missing authentication")
    end
  end

  defp get_auth_header(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        {:bearer, token}

      ["ApiKey " <> key] ->
        {:api_key, key}

      [key] when is_binary(key) ->
        # Fallback: treat raw header as API key
        {:api_key, key}

      _ ->
        # Check for API key in query params as fallback
        case conn.params do
          %{"api_key" => key} -> {:api_key, key}
          _ -> :none
        end
    end
  end

  defp authenticate_jwt(conn, token) do
    case JWT.verify_token(token) do
      {:ok, claims} ->
        conn
        |> assign(:authenticated, true)
        |> assign(:auth_method, :jwt)
        |> assign(:tenant, Map.get(claims, "tenant"))
        |> assign(:user_id, Map.get(claims, "sub"))

      {:error, reason} ->
        Logger.debug("JWT authentication failed: #{inspect(reason)}")
        unauthorized(conn, "Invalid token")
    end
  end

  defp authenticate_api_key(conn, key) do
    case ApiKey.verify(key) do
      {:ok, tenant} ->
        conn
        |> assign(:authenticated, true)
        |> assign(:auth_method, :api_key)
        |> assign(:tenant, tenant)

      {:error, reason} ->
        Logger.debug("API key authentication failed: #{inspect(reason)}")
        unauthorized(conn, "Invalid API key")
    end
  end

  defp unauthorized(conn, message) do
    body = Jason.encode!(%{error: "Unauthorized", message: message})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, body)
    |> halt()
  end
end
