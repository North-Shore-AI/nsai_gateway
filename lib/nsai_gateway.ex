defmodule NsaiGateway do
  @moduledoc """
  NsaiGateway - Unified API Gateway for North Shore AI Services.

  Provides:
  - Authentication (API Key & JWT)
  - Rate limiting
  - Request routing and proxying
  - Service discovery
  - Telemetry and monitoring

  ## Architecture

  The gateway sits between clients and backend NSAI services:

  ```
  Client -> Gateway -> [Work, Forge, Anvil, Crucible] Services
  ```

  ## Usage

  Start the gateway:

      mix run --no-halt

  Or as part of a supervision tree:

      children = [
        {NsaiGateway.Application, []}
      ]
  """

  @doc """
  Returns the current version of the gateway.
  """
  @spec version() :: String.t()
  def version do
    Application.spec(:nsai_gateway, :vsn) |> to_string()
  end
end
