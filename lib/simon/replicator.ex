defmodule Simon.Replicator do
  use GenServer
  require Logger

  @spec start_link :: :ignore | {:error, any} | {:ok, pid}
  def start_link(), do: GenServer.start_link(__MODULE__, {}, name: __MODULE__)

  @spec start_replicate(node()) :: :ok
  def start_replicate(node) do
    GenServer.call(__MODULE__, {:start_replicate, node})
  end

  @spec stop_replicate :: :ok
  def stop_replicate() do
    GenServer.call(__MODULE__, :stop_replicate)
  end

  ### Callbacks

  defmodule State do
    @enforce_keys [:simon, :count]
    defstruct simon: nil, count: 0

    @typedoc """
    This is the state of our node.
    """
    @type t() :: %__MODULE__{
      simon: String.t(),
      count: Integer.t()
    }
  end

  @impl GenServer
  def init(_arg) do
    :ok = :syn.join(:simon, :node, self())
    Logger.debug("Started replicator")
    state = %State{simon: nil, count: 0}
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:start_replicate, node}, _from, state) do
    :pong = Node.ping(node)
    GenServer.call(Simon.Node, :reset_log)
    Logger.debug("Replication started")
    schedule_replicate()
    {:reply, :ok, %State{state | simon: node}}
  end

  @impl GenServer
  def handle_call(:stop_replicate, _from, state) do
    Logger.debug("Replication stopping")
    {:reply, :ok, %State{state | simon: nil}}
  end

  @impl GenServer
  def handle_info(:replicate, state) do
    if state.simon != nil do
      Logger.debug("Replicating")
      {:ok, log} = GenServer.call({Simon.Node, state.simon}, {:read_log, state.count, 2})
      Logger.debug(log)
      len = length(log)
      :ok = GenServer.call(Simon.Node, {:write_log, log})
      schedule_replicate() # Reschedule again
      {:noreply, %State{state | count: state.count + len}}
    else
      Logger.debug("Replication stopped")
      {:noreply, state}
    end
  end

  defp schedule_replicate() do
    Process.send_after(self(), :replicate, 1 * 1000) # In 1 seconds
  end
end
