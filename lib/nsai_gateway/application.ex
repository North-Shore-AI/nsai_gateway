defmodule NsaiGateway.Application do
  @moduledoc """
  The NsaiGateway Application.

  Starts the API Gateway supervisor tree with HTTP server and telemetry.
  """

  use Application

  @impl true
  def start(_type, _args) do
    # Attach telemetry handlers
    NsaiGateway.Telemetry.attach_handlers()

    children = [
      # HTTP Server
      {Plug.Cowboy, scheme: :http, plug: NsaiGateway.Router, options: [port: cowboy_port()]}
    ]

    opts = [strategy: :one_for_one, name: NsaiGateway.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp cowboy_port do
    Application.get_env(:nsai_gateway, :port, 4000)
  end
end
