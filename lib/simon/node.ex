defmodule Simon.Node do
  use GenServer
  require Logger

  ### Interface

  @spec start_link(is_writer :: Bool.t()) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(is_writer), do: GenServer.start_link(__MODULE__, {is_writer}, name: __MODULE__)

  @spec write(v :: String.t()) :: {:error, any} | :ok
  def write(v) do
    GenServer.call(__MODULE__, {:init_write, v})
  end

  @spec read :: {:error, any} | {:ok, answer :: String.t()}
  def read do
    {:ok, v} = GenServer.call(__MODULE__, {:init_read})
    v
  end

  ### Callbacks

  defmodule State do
    @enforce_keys [:reg, :writer, :wsn, :reqsn]
    defstruct reg: "", writer: false, wsn: 0, reqsn: 0

    @typedoc """
    This is the state of our node.
    """
    @type t() :: %__MODULE__{
      reg: String.t(),
      writer: Bool.t(),
      wsn: Integer.t(),
      reqsn: Integer.t()
    }
  end

  @impl GenServer
  def init(arg) do
    :ok = :syn.join(:simon, :node, self())
    writer = elem(arg, 0)
    Logger.debug(writer)
    # if writer == false do
    #   :pong = Node.ping(:"aaa@127.0.0.1")
    # end
    state = %State{reg: "", writer: writer, wsn: 0, reqsn: 0}
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:init_write, v}, _from, state) do
    wsn = state.wsn + 1
    broadcast({:write, v, wsn})
    {:reply, :ok, %State{state | wsn: wsn, reg: v}} # do not send :write to itself, write directly to reg
  end

  @impl GenServer
  def handle_call({:init_read}, _from, state) do
    reqsn = state.reqsn + 1
    replies = broadcast({:read, reqsn})
    v = get_max(replies ++ [{:ack_read_req, reqsn, state.wsn, state.reg}]) # do not send :read to itself, just add data directly to the list
    broadcast({:write, elem(v, 3), elem(v, 2)})
    {:reply, {:ok, elem(v, 3)}, %State{state | reqsn: reqsn}}
  end

  @impl GenServer
  def handle_call({:write, v, wsn}, _from, state) do
    if wsn >= state.wsn do
      {:reply, {:ack_write, wsn}, %State{state | reg: v, wsn: wsn}}
    else
      {:reply, {:ack_write, wsn}, state}
    end
  end

  @impl GenServer
  def handle_call({:read, reqsn}, _from, state) do
    {:reply, {:ack_read_req, reqsn, state.wsn, state.reg}, state}
  end

  def broadcast(msg) do
    Logger.debug("broadcast")
    self = self()
    members = for {pid, _} <- :syn.members(:simon, :node), pid != self, do: pid
    replies = for pid <- members, do: GenServer.call(pid, msg)
    # will loop infinitely until there are enough replies
    if length(replies) < length(members) / 2 do
      broadcast(msg)
    else
      replies
    end
  end

  def get_max(replies) do
    Enum.max_by(replies, fn x -> elem(x, 2) end)
  end
end
