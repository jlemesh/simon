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
    @enforce_keys [:reg, :discovery, :wsn, :reqsn, :i, :lw]
    defstruct reg: [], discovery: "", wsn: 0, reqsn: 0, i: nil, lw: 0

    @typedoc """
    This is the state of our node.
    """
    @type t() :: %__MODULE__{
      reg: List.t(),
      discovery: String.t(),
      wsn: Integer.t(),
      reqsn: Integer.t(),
      i: Atom.t(),
      lw: Integer.t()
    }
  end

  @impl GenServer
  def init(arg) do
    :ok = :syn.join(:simon, :node, self())
    discovery = elem(arg, 0)
    if discovery != "" do
      :pong = Node.ping(String.to_atom(discovery))
    end
    state = %State{reg: [], discovery: discovery, wsn: 0, reqsn: 0, i: self(), lw: 0}
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:init_write, v}, _from, state) do
    replies = broadcast({:write_req, state.reqsn + 1}) ++ [{:ack_write_req, state.reqsn + 1, state.wsn, state.i}]
    max = get_max(replies)
    msn = elem(max, 2) + 1
    mlw = elem(max, 3)

    min = get_min(replies)
    minsn = elem(min, 2)
    Logger.debug("minsn: #{minsn}")
    Logger.debug("msn: #{msn}")
    reqsn = if minsn < msn - 1 do
      Logger.debug("propagate")
      if mlw == state.i do
        r = propagate(minsn, state)
        state.reqsn + 1 + length(r)
      else
        GenServer.call(mlw, {:propagate, minsn})
      end
    else
      state.reqsn
    end

    broadcast({:write, reqsn, v, msn, state.i})
    {:reply, :ok, %State{state | reqsn: reqsn, reg: state.reg ++ [v], lw: state.i, wsn: msn}} # do not send :write to itself, write directly to reg
  end

  @impl GenServer
  def handle_call({:init_read}, _from, state) do
    replies = broadcast({:read_req, state.reqsn + 1}) ++ [{:ack_read_req, state.reqsn + 1, state.wsn, state.lw, state.reg}]
    max = get_max(replies) # do not send :read to itself, just add data directly to the list
    msn = elem(max, 2)
    mlw = elem(max, 3)
    v = List.last(elem(max, 4))

    min = get_min(replies)
    minsn = elem(min, 2)
    Logger.debug("minsn: #{minsn}")
    Logger.debug("msn: #{msn}")
    reqsn = if minsn < msn - 1 do
      Logger.debug("propagate")
      if mlw == state.i do
        r = propagate(minsn, state)
        state.reqsn + 1 + length(r)
      else
        GenServer.call(mlw, {:propagate, minsn})
      end
    else
      state.reqsn
    end
    broadcast({:write, reqsn, v, msn, mlw})
    if state.wsn < msn do
      {:reply, {:ok, v}, %State{state | reqsn: reqsn, reg: state.reg ++ [v]}}
    else
      {:reply, {:ok, v}, %State{state | reqsn: reqsn}}
    end
  end

  @impl GenServer
  def handle_call({:write, reqsn, v, wsn, lw}, _from, state) do
    if wsn > state.wsn do # replaced >= with > for list
      {:reply, {:ack_write, reqsn}, %State{state | reg: state.reg ++ [v], wsn: wsn, lw: lw}}
    else
      {:reply, {:ack_write, reqsn}, state}
    end
  end

  @impl GenServer
  def handle_call({:read_req, reqsn}, _from, state) do
    {:reply, {:ack_read_req, reqsn, state.wsn, state.lw, state.reg}, state}
  end

  @impl GenServer
  def handle_call({:write_req, reqsn}, _from, state) do
    {:reply, {:ack_write_req, reqsn, state.wsn, state.lw}, state}
  end

  @impl GenServer
  def handle_call({:propagate, minsn}, _from, state) do
    r = propagate(minsn, state)
    {:reply, state.reqsn + length(r), %State{state | reqsn: state.reqsn + length(r)}}
  end

  @impl GenServer
  def handle_info({:sleep, time}, state) do
    Process.sleep(time)

    {:noreply, state}
  end

  def broadcast(msg) do
    Logger.debug("broadcast")
    self = self()
    members = for {pid, _} <- :syn.members(:simon, :node), pid != self, do: pid
    replies = for pid <- members, do: send_msg(pid, msg)

    # will loop infinitely until there are enough replies
    if length(replies) < length(members) / 2 do
      broadcast(msg)
    else
      replies
    end
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
