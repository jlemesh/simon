defmodule Simon.Supervisor do
  def start_link() do
    # We only start HTTP, if SIMON_PORT environment variable is set.
    discovery = System.get_env("SIMON_DISCOVERY", "")
    http =
      case System.get_env("SIMON_PORT") do
        nil ->
          []

        http_port ->
          http_opts = [port: String.to_integer(http_port)]
          [
            {Plug.Cowboy, scheme: :http, plug: Simon.RPC, options: http_opts},
          ]
      end
    children =
      [
        %{id: Simon.Node, start: {Simon.Node, :start_link, [discovery]}},
        %{id: Simon.Client, start: {Simon.Client, :start_link, [discovery]}},
      ] ++ http

    Supervisor.start_link(children, strategy: :one_for_all)
  end
end
