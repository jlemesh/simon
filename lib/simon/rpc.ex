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
  # curl http://localhost:9000/read_log?idx=0&count=2 && echo
  # '''
  get "/read_log" do
    #conn = fetch_query_params(conn)
    %{"idx" => idx, "count" => count} = conn.query_params
    {:ok, log} = Simon.Node.read_log(String.to_integer(idx), String.to_integer(count))
    respond_answer_json(conn, %{"Simon says" => log})
  end

  # Call it as
  # ```
  # curl -X PUT http://localhost:9000/write_log -H 'Content-Type: application/json' -d '{"msg":["great"]}' && echo
  # '''
  put "/write_log" do
    %{"msg" => msg} = conn.body_params
    :ok = Simon.Node.write_log(msg)
    respond_answer_json(conn, %{"Write" => "ok"})
  end

  # Call it as
  # ```
  # curl -X PUT http://localhost:9000/start_replicate -H 'Content-Type: application/json' -d '{"node":"aaa@127.0.0.1"}' && echo
  # '''
  put "/start_replicate" do
    %{"node" => node} = conn.body_params
    :ok = Simon.Replicator.start_replicate(String.to_atom(node))
    respond_answer_json(conn, %{"Replicate" => node})
  end

  # Call it as
  # ```
  # curl -X PUT http://localhost:9000/stop_replicate && echo
  # '''
  put "/stop_replicate" do
    Simon.Replicator.stop_replicate()
    respond_answer_json(conn, %{"Replicate" => "off"})
  end

  # Fallback handler when there was no match
  match _ do
    send_resp(conn, 404, "Not Found")
  end

  defp respond_answer_json(conn, response) do
    send_resp(conn, 200, Jason.encode!(response))
  end
end
