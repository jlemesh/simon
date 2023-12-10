defmodule Simon.Node do
  use GenServer
  require Logger

  ### Interface

  @spec start_link(discovery :: String.t()) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(discovery), do: GenServer.start_link(__MODULE__, {discovery}, name: __MODULE__, debug: [:statistics, :trace])

  @spec write(v :: String.t()) :: {:error, any} | :ok
  def write(v) do
    GenServer.call(__MODULE__, {:init_write, v})
  end

  @spec read :: {:error, any} | {answer :: String.t()}
  def read do
    {:ok, v} = GenServer.call(__MODULE__, {:init_read})
    v
  end

  @spec read :: {:error, any} | {answer :: String.t()}
  def get_log do
    {:ok, v} = GenServer.call(__MODULE__, :get_log)
    v
  end

  ### Callbacks

  defmodule State do
    @enforce_keys [:discovery, :view_num, :config, :replica_num, :status, :op_num, :log, :commit_num, :client_table, :prepare_ok_buf, :storage, :log_buf]
    defstruct discovery: "", view_num: 0, config: [], replica_num: 0, status: "", op_num: 0, log: [], commit_num: 0, client_table: %{}, prepare_ok_buf: %{}, storage: [], log_buf: []

    @typedoc """
    This is the state of our node.
    """
    @type t() :: %__MODULE__{
      discovery: String.t(),
      view_num: Integer.t(),
      config: List.t(),
      replica_num: Integer.t(),
      status: String.t(),
      op_num: Integer.t(),
      log: List.t(),
      commit_num: Integer.t(),
      client_table: Map.t(),
      prepare_ok_buf: Map.t(),
      storage: List.t(),
      log_buf: [],
    }
  end

  @impl GenServer
  def init({discovery}) do
    :ok = Logger.metadata [pid: self()]
    Logger.metadata [type: "replica"]

    if discovery != "" do
      :pong = Node.ping(String.to_atom(discovery))
    end

    replica_num = register()
    :ok = :syn.join(:simon, :replica, self())
    {:ok, %State{
      discovery: discovery,
      view_num: 1,
      config: [],
      replica_num: replica_num,
      status: "normal",
      op_num: 0,
      log: [],
      commit_num: 0,
      client_table: Map.new(),
      prepare_ok_buf: Map.new(),
      storage: [],
      log_buf: [],
    }}
  end

  @impl GenServer
  def handle_call(:get_log, _from, state) do
    {:reply, state.log, state}
  end

  @impl GenServer
  def handle_call(:get_storage, _from, state) do
    {:reply, state.storage, state}
  end

  @impl GenServer
  def handle_call(:reset, _from, state) do
    {:reply, :ok, %State{
      discovery: state.discovery,
      view_num: 1,
      config: [],
      replica_num: state.replica_num,
      status: "normal",
      op_num: 0,
      log: [],
      commit_num: 0,
      client_table: Map.new(),
      prepare_ok_buf: Map.new(),
      storage: [],
      log_buf: [],
    }}
  end

  @impl GenServer
  def handle_call({:write, v, client_id, req_num}, from, state) do
    Logger.debug(call: "write", from: from)
    case Map.get(state.client_table, client_id) do
      nil -> process_write(state, v, client_id, req_num, from)
      resp -> respond_existing(req_num, resp, state, v, client_id, from)
    end
  end

  @impl GenServer
  def handle_cast({:get_state, view_num, op_num, node}, state) do
    if state.status == "normal" && state.view_num == view_num do
      GenServer.cast(node, {:new_state, view_num, Enum.take(state.log, op_num - length(state.log)), state.op_num, state.commit_num})
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast({:prepare, view_num, req, op_num, commit_num}, state) do
    if state.op_num < op_num - 1 do
      config = for {pid, _} <- :syn.members(:simon, :replica), pid != self(), do: pid
      GenServer.cast(Enum.random(config), {:get_state, state.view_num, state.commit_num, self()})
      {:noreply, %State{state |
        op_num: state.commit_num,
        log: List.delete_at(state.log, op_num - length(state.log)),
        log_buf: state.log_buf ++ [req],
      }}
    else
      case Enum.at(state.log, commit_num - 1) do
        {entry, _pid, _num, _from} ->
          storage = commit_sm([entry], state.storage)
          :ok = cast_primary(state, {:prepare_ok, view_num, op_num, state.replica_num})
          {:noreply, %State{state |
            client_table: Map.put(state.client_table, elem(req, 1), req),
            log: state.log ++ state.log_buf ++ [req],
            op_num: op_num,
            storage: storage,
            commit_num: commit_num
          }}
        nil ->
          :ok = cast_primary(state, {:prepare_ok, view_num, op_num, state.replica_num})
          {:noreply, %State{state |
            client_table: Map.put(state.client_table, elem(req, 1), req),
            log: state.log ++ state.log_buf ++ [req],
            op_num: op_num
          }}
      end
    end
  end

  def handle_cast({:new_state, _view_num, log, op_num, commit_num}, state) do
    entries = for {entry, _a, _b, _c} <- Enum.take(log, commit_num - state.commit_num), do: entry
    storage = commit_sm(Enum.reverse(entries), state.storage)
    {:noreply, %State{state |
      op_num: op_num,
      log: state.log ++ log,
      commit_num: commit_num,
      storage: storage,
    }}
  end

  @impl GenServer
  def handle_cast({:prepare_ok, view_num, op_num, replica_num}, state) do
    buf_mod = Map.put(
      state.prepare_ok_buf,
      state.op_num,
      state.prepare_ok_buf[op_num] ++ [{:prepare_ok, view_num, op_num, replica_num}]
    )
    Logger.debug(len: length(buf_mod[op_num]))
    if length(buf_mod[op_num]) > :syn.member_count(:simon, :replica) / 2 do
      {{:write, v}, client_id, req_num, from} = Enum.at(state.log, op_num - 1)
      Logger.debug(log: state.log, op_num: op_num)
      resp = {:reply, state.view_num, req_num, 0}
      GenServer.reply(
        from,
        resp
      )
      {:noreply, %State{state |
        prepare_ok_buf: Map.put(
          state.prepare_ok_buf,
          state.op_num,
          []
        ),
        commit_num: state.commit_num + 1,
        client_table: Map.put(state.client_table, client_id, resp),
        storage: commit_sm([{:write, v}], state.storage)
      }}
    else
      {:noreply, %State{state | prepare_ok_buf: buf_mod}}
    end
  end

  def respond_existing(req_num, resp, state, v, client_id, from) do
    cond do
      req_num < elem(resp, 2) -> {:noreply, state}
      req_num == elem(resp, 2) -> {:reply, resp, state}
      req_num > elem(resp, 2) ->
        process_write(state, v, client_id, req_num, from)
    end
  end

  def process_write(state, v, client_id, req_num, from) do
    op_num = state.op_num + 1
    log = state.log ++ [{{:write, v}, client_id, req_num, from}]
    broadcast({
      :prepare,
      state.view_num,
      {{:write, v}, client_id, req_num, from},
      op_num,
      state.commit_num
    })
    {:noreply, %State{state |
      client_table: Map.put(state.client_table, client_id, {req_num, nil}),
      log: log,
      op_num: op_num,
      prepare_ok_buf: Map.put(state.prepare_ok_buf, op_num, [])
    }}
  end

  def commit_sm([], storage), do: storage

  def commit_sm([{:write, v}], storage) do
    storage ++ [v]
  end

  def commit_sm([item | rest], storage) do
    commit_sm(rest, storage) ++ [elem(item, 1)] #[item | concat(rest, list)]
  end

  @impl GenServer
  def handle_info({:sleep, time}, state) do
    Process.sleep(time)

    {:noreply, state}
  end

  def cast_primary(state, msg) do
    GenServer.cast(get_primary(state), msg)
  end

  def get_primary(state) do
    {primary, _meta} = :syn.lookup(
      :simon,
      rem(state.view_num, :syn.member_count(:simon, :replica))
    )
    primary
  end

  def register() do
    config = get_replicas()
    id = length(config) + 1

    Logger.debug(config: config)

    case :syn.register(:simon, id, self()) do
      :ok -> id
      {:error, :taken} ->
        Logger.debug("taken, sleeping...")
        Process.sleep(Enum.random([100, 300, 600]))
        register()
    end
  end

  def get_replicas() do
    for {pid, _} <- :syn.members(:simon, :replica), pid != self(), do: pid
  end

  def broadcast(msg) do
    for pid <- get_replicas(), do: GenServer.cast(pid, msg)
  end
end
