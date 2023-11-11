defmodule Simon.RPC do
  @moduledoc """
  That's RPC API. See also Simon.Supervisor
  """
  use Plug.Router
  plug(Plug.Logger)
  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:dispatch)

  # Call it as:
  # ```
  # curl http://localhost:9000/ && echo
  # '''
  get "/" do
    respond_answer_json(conn, %{"Status" => "up"})
  end

  # Call it as:
  # ```
  # curl http://localhost:9000/read && echo
  # '''
  get "/read" do
    {:ok, v} = Simon.Node.read()
    respond_answer_json(conn, %{"Simon says" => v})
  end

  # Call it as
  # ```
  # curl -X PUT http://localhost:9000/write -H 'Content-Type: application/json' -d '{"msg":["great"]}' && echo
  # '''
  put "/write" do
    %{"msg" => msg} = conn.body_params
    :ok = Simon.Node.write(msg)
    respond_answer_json(conn, %{"Write" => "ok"})
  end

  # Fallback handler when there was no match
  match _ do
    send_resp(conn, 404, "Not Found")
  end

  defp respond_answer_json(conn, response) do
    send_resp(conn, 200, Jason.encode!(response))
  end
end
