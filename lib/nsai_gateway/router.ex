defmodule NsaiGateway.Router do
  @moduledoc """
  Main HTTP router for the NSAI Gateway.

  Routes requests to appropriate backend services with authentication,
  rate limiting, and telemetry.
  """

  use Plug.Router

  alias NsaiGateway.{Auth, RateLimiter, Proxy}

  plug(:match)
  plug(Plug.Parsers, parsers: [:json], json_decoder: Jason)
  plug(Plug.Logger)
  plug(:auth)
  plug(:rate_limit)
  plug(:dispatch)

  # Health check endpoint
  get "/health" do
    send_resp(conn, 200, Jason.encode!(%{status: "healthy", service: "nsai_gateway"}))
  end

  # API routes to backend services
  match("/api/v1/jobs/*path", to: Proxy, init_opts: [service: "work"])
  match("/api/v1/samples/*path", to: Proxy, init_opts: [service: "forge"])
  match("/api/v1/labels/*path", to: Proxy, init_opts: [service: "anvil"])
  match("/api/v1/experiments/*path", to: Proxy, init_opts: [service: "crucible"])

  # Catch-all for unmatched routes
  match _ do
    send_resp(conn, 404, Jason.encode!(%{error: "Not Found"}))
  end

  # Authentication plug
  defp auth(conn, _opts) do
    # Skip auth for health check
    if conn.request_path == "/health" do
      conn
    else
      Auth.authenticate(conn)
    end
  end

  # Rate limiting plug
  defp rate_limit(conn, _opts) do
    # Skip rate limiting for health check
    if conn.request_path == "/health" do
      conn
    else
      RateLimiter.check(conn)
    end
  end
end
