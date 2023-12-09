defmodule Simon.Client do
  use GenServer
  require Logger

  ### Interface

  @spec start_link(discovery :: String.t()) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(discovery), do: GenServer.start_link(__MODULE__, {discovery}, name: __MODULE__, debug: [:statistics, :trace])

  @spec write(v :: String.t()) :: {:error, any} | :ok
  def write(v) do
    Logger.debug(v: v)
    GenServer.call(__MODULE__, {:init_write, v})
  end

  @spec read :: {:error, any} | {answer :: String.t()}
  def read do
    {:ok, v} = GenServer.call(__MODULE__, {:init_read})
    v
  end

  ### Callbacks

  defmodule State do
    @enforce_keys [:discovery, :view_number, :config, :client_id, :request_number]
    defstruct discovery: "", view_number: 0, config: [], client_id: nil, request_number: 0

    @typedoc """
    This is the state of our node.
    """
    @type t() :: %__MODULE__{
      discovery: String.t(),
      view_number: Integer.t(),
      config: List.t(),
      client_id: Atom.t(),
      request_number: Integer.t(),
    }
  end

  defmodule Request do
    defstruct type: "", client_id: nil, request_num: 0
  end

  @impl GenServer
  def init(arg) do
    #Logger.configure(format: "[$level] $metadata$message\n", metadata: [:module, :function, :my_id])
    Logger.metadata [pid: self()]
    Logger.metadata [type: "client"]
    discovery = elem(arg, 0)
    if discovery != "" do
      :pong = Node.ping(String.to_atom(discovery))
    end
    config = for {pid, _} <- :syn.members(:simon, :replica), do: pid
    Logger.debug(config: config)
    # if length(config) > 0 do
    #   {primary, _meta} = :syn.lookup(:simon, 1)
    #   Logger.debug(primary: node(primary))
    #   :pong = Node.ping(node(primary))
    # end
    :ok = :syn.join(:simon, :client, self())
    {:ok, %State{discovery: discovery, view_number: 1, config: config, client_id: self(), request_number: 0}}
  end

  @impl GenServer
  def handle_call({:init_write, v}, _from, state) do
    Logger.debug("init_write")
    req_num = state.request_number + 1
    config = for {pid, _} <- :syn.members(:simon, :replica), do: pid
    Logger.debug(config: config)
    n = length(config)
    primary_num = rem(state.view_number, n)
    Logger.debug(n: n, primary_num: primary_num)
    {primary, _meta} = :syn.lookup(:simon, primary_num)
    Logger.debug(primary: node(primary))
    resp = GenServer.call(primary, {:write, v, state.client_id, req_num})
    {:reply, resp, %State{state | request_number: req_num}}
  end

  @impl GenServer
  def handle_call({:init_read}, _from, state) do
    req_num = state.request_number + 1
    n = length(state.config)
    primary = rem(n, state.view_number)
    {:ok, v} = GenServer.call(state.config[primary], {:read, req_num})
    {:reply, v, %State{state | request_number: req_num}}
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
