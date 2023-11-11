defmodule Simon.Supervisor do
  def start_link() do
    # We only start HTTP, if SIMON_PORT environment variable is set.
    http =
      case System.get_env("SIMON_PORT") do
        nil ->
          []

        http_port ->
          http_opts = [port: String.to_integer(http_port)]
          [{Plug.Cowboy, scheme: :http, plug: Simon.RPC, options: http_opts}]
      end
    is_writer = System.get_env("SIMON_WRITER") == "1"
    children =
      [
        %{id: Simon.Node, start: {Simon.Node, :start_link, [is_writer]}},
      ] ++ http

    Supervisor.start_link(children, strategy: :one_for_all)
  end
end
