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

  def leave do
    :ok = GenServer.call(__MODULE__, :leave)
  end

  ### Callbacks

  defmodule State do
    @enforce_keys [:discovery, :view_num, :config, :replica_num, :status, :op_num, :log, :commit_num, :client_table, :prepare_ok_buf, :storage, :log_buf, :timer, :start_view_change_buf, :do_view_change_buf]
    defstruct discovery: "", view_num: 0, config: [], replica_num: 0, status: "", op_num: 0, log: [], commit_num: 0, client_table: %{}, prepare_ok_buf: %{}, storage: [], log_buf: [], timer: 0, start_view_change_buf: %{}, do_view_change_buf: %{}

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
      timer: Integer.t(),
      start_view_change_buf: Map.t(),
      do_view_change_buf: Map.t(),
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
    Logger.debug(registered: replica_num, pid: self())
    :ok = :syn.join(:simon, :replica, self())
    start_timer()
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
      timer: System.os_time(:millisecond) + 5000,
      start_view_change_buf: Map.new(),
      do_view_change_buf: Map.new(),
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
      timer: System.os_time(:millisecond),
      start_view_change_buf: Map.new(),
      do_view_change_buf: Map.new(),
    }}
  end

  @impl GenServer
  def handle_call(:leave, _from, state) do
    case :syn.leave(:simon, :replica, self()) do
      :ok -> nil
      {:error, reason} -> Logger.debug(leave: reason)
    end
    case :syn.unregister(:simon, state.replica_num) do
      :ok -> nil
      {:error, reason} -> Logger.debug(leave: reason)
    end

    {:reply, :ok, %State{state |
      replica_num: 0
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
        timer: System.os_time(:millisecond),
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
            commit_num: commit_num,
            timer: System.os_time(:millisecond),
          }}
        nil ->
          :ok = cast_primary(state, {:prepare_ok, view_num, op_num, state.replica_num})
          {:noreply, %State{state |
            client_table: Map.put(state.client_table, elem(req, 1), req),
            log: state.log ++ state.log_buf ++ [req],
            op_num: op_num,
            timer: System.os_time(:millisecond),
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
    old_buf = Map.get(state.prepare_ok_buf, op_num, [])
    buf_mod = Map.put(
      state.prepare_ok_buf,
      state.op_num,
      old_buf ++ [{:prepare_ok, view_num, op_num, replica_num}]
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

  @impl GenServer
  def handle_cast({:start_view_change, view_num, from}, state) do
    old_buf = Map.get(state.start_view_change_buf, view_num, [])
    buf_mod = Map.put(
      state.start_view_change_buf,
      view_num,
      old_buf ++ [{:start_view_change, view_num, from}]
    )
    Logger.debug(len: length(buf_mod[view_num]))
    if length(buf_mod[view_num]) >= :syn.member_count(:simon, :replica) / 2 do
      primary = get_primary(view_num)
      GenServer.cast(
        primary,
        {:do_view_change, view_num, state.log, state.view_num, state.op_num, state.commit_num, self()}
      )
      {:noreply, %State{state |
        start_view_change_buf: Map.put(
          state.start_view_change_buf,
          view_num,
          []
        ),
        view_num: view_num
      }}
    else
      {:noreply, %State{state | start_view_change_buf: buf_mod}}
    end
  end

  @impl GenServer
  def handle_cast({:do_view_change, view_num, log, old_view_num, op_num, commit_num, from}, state) do
    old_buf = Map.get(state.do_view_change_buf, view_num, [])
    buf_mod = Map.put(
      state.do_view_change_buf,
      view_num,
      old_buf ++ [{:do_view_change, view_num, log, old_view_num, op_num, commit_num, from}]
    )
    Logger.debug(len: length(buf_mod[view_num]))
    if length(buf_mod[view_num]) > :syn.member_count(:simon, :replica) / 2 do
      max = get_with_largest_op_num(get_with_largest_view_num(buf_mod[view_num]))
      new_log = elem(max, 2)
      new_op_num = elem(max, 4)
      new_commit_num = elem(max, 5)
      new_status = "normal"

      broadcast(
        {
          :start_view,
          view_num,
          new_log,
          new_op_num,
          new_commit_num
        }
      )

      logs = Enum.slice(log, state.commit_num..new_commit_num)
      entries = for {entry, _a, _b, _c} <- logs, do: entry
      storage = commit_sm(Enum.reverse(entries), state.storage)
      for {_entry, _client_id, req_num, from} <- logs, do: GenServer.reply(
        from,
        {:reply, view_num, req_num, 0}
      )

      replies = for {_entry, client_id, req_num, _from} <- logs, do: {client_id, {:reply, view_num, req_num, 0}}

      client_table = update_client_table(replies, state.client_table)

      {:noreply, %State{state |
        do_view_change_buf: Map.put(
          state.do_view_change_buf,
          view_num,
          []
        ),
        view_num: view_num,
        client_table: client_table,
        storage: storage,
        log: new_log,
        op_num: new_op_num,
        commit_num: new_commit_num,
        status: new_status
      }}
    else
      {:noreply, %State{state | do_view_change_buf: buf_mod}}
    end
  end

  def handle_cast({:start_view, view_num, log, op_num, commit_num}, state) do
    uncommited = Enum.slice(log, commit_num..length(log))
    for {_entry, _client_id, op_num, _from} <- uncommited, do: cast_primary(state, {:prepare_ok, view_num, op_num, state.replica_num})
    replies = for {_entry, client_id, req_num, _from} <- uncommited, do: {client_id, {:reply, view_num, req_num, 0}}
    client_table = update_client_table(replies, state.client_table)

    logs = Enum.slice(log, state.commit_num..commit_num)
    entries = for {entry, _a, _b, _c} <- logs, do: entry
    storage = commit_sm(Enum.reverse(entries), state.storage)
    replies = for {_entry, client_id, req_num, _from} <- logs, do: {client_id, {:reply, view_num, req_num, 0}}
    client_table1 = update_client_table(replies, client_table)

    {:noreply, %State{state |
      op_num: op_num,
      log: log,
      commit_num: commit_num,
      storage: storage,
      view_num: view_num,
      status: "normal",
      client_table: client_table1,
    }}
  end

  def update_client_table([], client_table), do: client_table

  def update_client_table([{client_id, resp}], client_table) do
    Map.put(client_table, client_id, resp)
  end

  def update_client_table([{client_id, resp} | rest], client_table) do
    Map.put(update_client_table(rest, client_table), client_id, resp)  #commit_sm(rest, storage) ++ [elem(item, 1)] #[item | concat(rest, list)]
  end

  def get_with_largest_view_num(buffer) do
    {:do_view_change, _view_num, _log, old_view_num, _op_num, _commit_num, _from} = Enum.max_by(buffer, fn x -> elem(x, 3) end)
    Enum.filter(buffer, fn x -> elem(x, 3) == old_view_num end)
  end

  def get_with_largest_op_num(buffer) do
    Enum.max_by(buffer, fn x -> elem(x, 4) end)
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

  def cast_primary(state, msg) do
    GenServer.cast(get_primary(state.view_num), msg)
  end

  def get_primary(view_num) do
    pr_num = rem(view_num, :syn.member_count(:simon, :replica)) + 1
    Logger.debug(view_num: view_num, pr_num: pr_num)
    {primary, _meta} = :syn.lookup(
      :simon,
      pr_num
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

  def start_timer() do
    Process.send_after(self(), :timer, 5 * 1000) # In 1 seconds
  end

  @impl GenServer
  def handle_info(:timer, state) do
    if System.os_time(:millisecond) > state.timer + 5000 && get_primary(state.view_num) != self() && state.replica_num != 0 do
      view_num = state.view_num + 1
      status = "view_change"
      broadcast({:start_view_change, view_num, self()})
      {:noreply, %State{state |
      view_num: view_num,
      status: status
    }}
    else
      start_timer() # Reschedule again
      {:noreply, state}
    end
  end
end
