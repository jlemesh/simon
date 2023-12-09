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

  ### Callbacks

  defmodule State do
    @enforce_keys [:discovery, :view_num, :config, :replica_num, :status, :op_num, :log, :commit_num, :client_table, :prepare_ok_buf, :store, :log_buf]
    defstruct discovery: "", view_num: 0, config: [], replica_num: 0, status: "", op_num: 0, log: [], commit_num: 0, client_table: %{}, prepare_ok_buf: %{}, store: [], log_buf: []

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
      store: List.t(),
      log_buf: [],
    }
  end


  @impl GenServer
  def init(arg) do
    #Logger.configure(format: "[$level] $metadata$message\n", metadata: [:module, :function, :my_id])
    :ok = Logger.metadata [pid: self()]
    Logger.metadata [type: "replica"]
    discovery = elem(arg, 0)
    if discovery != "" do
      :pong = Node.ping(String.to_atom(discovery))
    end
    # Process.sleep(2000)
    # config = for {pid, _} <- :syn.members(:simon, :replica), do: pid
    # Logger.debug(config: config)
    # :ok = :syn.register(:simon, length(config) + 1, self())
    replica_num = register()
    :ok = :syn.join(:simon, :replica, self())
    {:ok, %State{
      discovery: discovery,
      view_num: 1,
      config: [],
      replica_num: replica_num,
      status: "recovering",
      op_num: 0,
      log: [],
      commit_num: 0,
      client_table: Map.new(),
      prepare_ok_buf: Map.new(),
      store: [],
      log_buf: [],
    }}
  end

  @impl GenServer
  def handle_call({:write, v, client_id, req_num}, from, state) do
    Logger.debug(from: from)
    Logger.debug("write")
    case Map.get(state.client_table, client_id) do
      nil -> process_write(state, v, client_id, req_num, from)
      {req_num, resp} -> respond_existing(req_num, resp, state, v, client_id, req_num, from)
    end
  end

  @impl GenServer
  def handle_call({:get_state, view_num, op_num, _node}, _from, state) do
    if state.status == "normal" && state.view_num == view_num do
      {:reply, {:new_state, view_num, Enum.take(state.log, op_num - length(state.log)), state.commit_num}}
    else
      {:stop, :misconfig, state}
    end
  end

  @impl GenServer
  def handle_cast({:prepare, view_num, req, op_num, _commit_num}, state) do
    if state.op_num < op_num - 1 do
      new_op_num = state.commit_num
      log = List.delete_at(state.log, op_num - length(state.log))
      # put to log buf
      log_buf = state.log_buf ++ [req]
      # request missing data
      config = for {pid, _} <- :syn.members(:simon, :replica), pid != self(), do: pid
      GenServer.cast(Enum.random(config), {:get_state, state.view_num, new_op_num, self()})
      {:noreply, %State{state |
        op_num: new_op_num,
        log: log,
        log_buf: log_buf,
      }}
    else
      client_id = Map.get(state.client_table, elem(req, 1)) # {{:write, v}, client_id, req_num, from}
      :ok = cast_primary(state, {:prepare_ok, view_num, op_num, state.replica_num})
      {:noreply, %State{state |
        client_table: Map.put(state.client_table, client_id, req),
        log: state.log ++ state.log_buf ++ [req],
        op_num: op_num
      }}
    end
  end

  def handle_cast({:new_state, _view_num, log, op_num, commit_num}, state) do
    {:noreply, %State{state |
      op_num: op_num,
      log: state.log ++ log,
      commit_num: commit_num,
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
      req = Enum.at(state.log, op_num - 1) # {{:write, v}, client_id, req_num, from}
      Logger.debug(req: req, log: state.log, op_num: op_num)
      resp = {:reply, state.view_num, elem(req, 2), 0}
      client_id = Map.get(state.client_table, elem(req, 1)) # {{:write, v}, client_id, req_num, from}
      GenServer.reply(
        elem(req, 3),
        resp
      )
      {:noreply, %State{state |
        prepare_ok_buf: buf_mod,
        commit_num: state.commit_num + 1,
        client_table: Map.put(state.client_table, client_id, resp),
        store: commit_sm(elem(req, 0), state)
      }}
    else
      {:noreply, %State{state | prepare_ok_buf: buf_mod}}
    end
  end

  def respond_existing(req_num, resp, state, v, client_id, req_num, from) do
    cond do
      req_num < state.req_num -> {:noreply, state}
      req_num == state.req_num -> {:reply, resp, state}
      req_num > state.req_num ->
        process_write(state, v, client_id, req_num, from)
    end
  end

  def process_write(state, v, client_id, req_num, from) do
    op_num = state.op_num + 1
    log = state.log ++ [{{:write, v}, client_id, req_num, from}]
    broadcast2({
      :prepare,
      state.view_num,
      {:write, v, client_id, req_num},
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

  def commit_sm({:write, v}, state) do
    state.store ++ [v]
  end

  @impl GenServer
  def handle_info({:sleep, time}, state) do
    Process.sleep(time)

    {:noreply, state}
  end

  def cast_primary(state, msg) do
    config = for {pid, _} <- :syn.members(:simon, :replica), do: pid
    Logger.debug(config: config)
    n = length(config)
    primary_num = rem(state.view_num, n)
    Logger.debug(n: n, primary_num: primary_num)
    {primary, _meta} = :syn.lookup(:simon, primary_num)
    Logger.debug(primary: node(primary))
    GenServer.cast(primary, msg)
  end

  def register() do
    config = for {pid, _} <- :syn.members(:simon, :replica), do: pid
    Logger.debug(config: config)
    case :syn.register(:simon, length(config) + 1, self()) do
      :ok -> length(config) + 1
      {:error, :taken} ->
        Process.sleep(500)
        register()
    end
  end

  def broadcast(msg) do
    Logger.debug("broadcast")
    self = self()
    members = for {pid, _} <- :syn.members(:simon, :replica), pid != self, do: pid
    replies = for pid <- members, do: send_msg(pid, msg)

    # will loop infinitely until there are enough replies
    if length(replies) < length(members) / 2 do
      broadcast(msg)
    else
      replies
    end
  end

  def broadcast2(msg) do
    Logger.debug("broadcast2")
    self = self()
    members = for {pid, _} <- :syn.members(:simon, :replica), pid != self, do: pid
    for pid <- members, do: GenServer.cast(pid, msg)
  end

  def send_msg(pid, msg) do
    try do
      GenServer.call(pid, msg)
    catch
      :exit, _e ->
        nil
    end
  end

  def get_max(replies) do
    Enum.max_by(replies, fn x -> elem(x, 2) end)
  end

  def get_min(replies) do
    Enum.min_by(replies, fn x -> elem(x, 2) end)
  end

  def propagate(minsn, state) do
    reqsn = state.reqsn + 1
    for {wsn, rsn} <- Enum.zip(minsn..length(state.reg), reqsn..(reqsn + length(state.reg) - minsn)), do: broadcast({:write, rsn, Enum.at(state.reg, wsn - 1), wsn, state.i})
  end
end
