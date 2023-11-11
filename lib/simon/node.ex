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
    defstruct reg: "", discovery: "", wsn: 0, reqsn: 0, i: 0, lw: 0

    @typedoc """
    This is the state of our node.
    """
    @type t() :: %__MODULE__{
      reg: String.t(),
      discovery: String.t(),
      wsn: Integer.t(),
      reqsn: Integer.t(),
      i: Integer.t(),
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
    state = %State{reg: "", discovery: discovery, wsn: 0, reqsn: 0, i: :rand.uniform(10000), lw: 0}
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:init_write, v}, _from, state) do
    reqsn = state.reqsn + 1
    replies = broadcast({:write_req, reqsn})
    max = get_max(replies ++ [{:write_req, reqsn, state.wsn}])
    msn = elem(max, 2) + 1
    broadcast({:write, reqsn, v, msn, state.i})
    {:reply, :ok, %State{state | reqsn: reqsn, reg: v, lw: state.i, wsn: msn}} # do not send :write to itself, write directly to reg
  end

  @impl GenServer
  def handle_call({:init_read}, _from, state) do
    reqsn = state.reqsn + 1
    replies = broadcast({:read_req, reqsn})
    max = get_max(replies ++ [{:ack_read_req, reqsn, state.wsn, state.lw, state.reg}]) # do not send :read to itself, just add data directly to the list
    msn = elem(max, 2)
    mlw = elem(max, 3)
    v = elem(max, 4)
    broadcast({:write, reqsn, v, msn, mlw})
    {:reply, {:ok, v}, %State{state | reqsn: reqsn, reg: v}}
  end

  @impl GenServer
  def handle_call({:write, reqsn, v, wsn, lw}, _from, state) do
    if wsn >= state.wsn do
      {:reply, {:ack_write, reqsn}, %State{state | reg: v, wsn: wsn, lw: lw}}
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
    {:reply, {:ack_read_req, reqsn, state.wsn}, state}
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
end
