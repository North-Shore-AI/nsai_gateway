defmodule NsaiGateway.Auth.OAuth2 do
  @moduledoc """
  OAuth2 authentication handler with Authorization Code Flow support.

  Provides OAuth2/OIDC integration for third-party authentication providers.

  ## Configuration

      config :nsai_gateway, :oauth2,
        providers: %{
          "google" => %{
            client_id: "your-client-id",
            client_secret: "your-client-secret",
            authorize_url: "https://accounts.google.com/o/oauth2/v2/auth",
            token_url: "https://oauth2.googleapis.com/token",
            userinfo_url: "https://www.googleapis.com/oauth2/v3/userinfo",
            scopes: ["openid", "email", "profile"]
          }
        }
  """

  require Logger

  @type provider :: String.t()
  @type config :: map()
  @type token_response :: %{
          access_token: String.t(),
          token_type: String.t(),
          expires_in: integer(),
          refresh_token: String.t() | nil,
          id_token: String.t() | nil
        }

  @doc """
  Generates an OAuth2 authorization URL for the specified provider.
  """
  @spec authorize_url(provider(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :provider_not_found}
  def authorize_url(provider, redirect_uri, state) do
    case get_provider_config(provider) do
      nil ->
        {:error, :provider_not_found}

      config ->
        params = %{
          client_id: config.client_id,
          redirect_uri: redirect_uri,
          response_type: "code",
          scope: Enum.join(config.scopes, " "),
          state: state
        }

        url = "#{config.authorize_url}?#{URI.encode_query(params)}"
        {:ok, url}
    end
  end

  @doc """
  Exchanges an authorization code for an access token.
  """
  @spec exchange_code(provider(), String.t(), String.t()) ::
          {:ok, token_response()} | {:error, term()}
  def exchange_code(provider, code, redirect_uri) do
    case get_provider_config(provider) do
      nil ->
        {:error, :provider_not_found}

      config ->
        body = %{
          client_id: config.client_id,
          client_secret: config.client_secret,
          code: code,
          grant_type: "authorization_code",
          redirect_uri: redirect_uri
        }

        case Req.post(config.token_url, form: body) do
          {:ok, %{status: 200, body: response}} ->
            {:ok, parse_token_response(response)}

          {:ok, %{status: status, body: body}} ->
            Logger.error("OAuth2 token exchange failed: status=#{status} body=#{inspect(body)}")
            {:error, :token_exchange_failed}

          {:error, reason} ->
            Logger.error("OAuth2 token exchange error: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  @doc """
  Refreshes an access token using a refresh token.
  """
  @spec refresh_token(provider(), String.t()) :: {:ok, token_response()} | {:error, term()}
  def refresh_token(provider, refresh_token) do
    case get_provider_config(provider) do
      nil ->
        {:error, :provider_not_found}

      config ->
        body = %{
          client_id: config.client_id,
          client_secret: config.client_secret,
          refresh_token: refresh_token,
          grant_type: "refresh_token"
        }

        case Req.post(config.token_url, form: body) do
          {:ok, %{status: 200, body: response}} ->
            {:ok, parse_token_response(response)}

          {:ok, %{status: status}} ->
            Logger.error("OAuth2 token refresh failed: status=#{status}")
            {:error, :token_refresh_failed}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Fetches user information using an access token.
  """
  @spec get_userinfo(provider(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_userinfo(provider, access_token) do
    case get_provider_config(provider) do
      nil ->
        {:error, :provider_not_found}

      config ->
        headers = %{"Authorization" => "Bearer #{access_token}"}

        case Req.get(config.userinfo_url, headers: headers) do
          {:ok, %{status: 200, body: userinfo}} ->
            {:ok, userinfo}

          {:ok, %{status: status}} ->
            Logger.error("OAuth2 userinfo fetch failed: status=#{status}")
            {:error, :userinfo_fetch_failed}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # Private functions

  @spec get_provider_config(provider()) :: config() | nil
  defp get_provider_config(provider) do
    Application.get_env(:nsai_gateway, :oauth2, %{})
    |> Map.get(:providers, %{})
    |> Map.get(provider)
  end

  @spec parse_token_response(map()) :: token_response()
  defp parse_token_response(response) do
    %{
      access_token: response["access_token"],
      token_type: response["token_type"],
      expires_in: response["expires_in"],
      refresh_token: response["refresh_token"],
      id_token: response["id_token"]
    }
  end
end
