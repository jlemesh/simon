defmodule Simon.Node do
  use GenServer
  require Logger

  ### Interface

  @spec start_link :: :ignore | {:error, any} | {:ok, pid}
  def start_link(), do: GenServer.start_link(__MODULE__, {}, name: __MODULE__)

  @spec write_log(msg :: List.t()) :: {:error, any} | :ok
  def write_log(msg) do
    GenServer.call(__MODULE__, {:write_log, msg})
  end

  @spec read_log(idx :: Integer.t(), count :: Integer.t()) :: {:ok, log :: List.t()}
  def read_log(idx, count) do
    GenServer.call(__MODULE__, {:read_log, idx, count})
  end

  @spec stop :: :ok
  def stop() do
    GenServer.stop(__MODULE__)
  end

  ### Callbacks

  defmodule State do
    @enforce_keys [:log]
    defstruct log: []

    @typedoc """
    This is the state of our node.
    """
    @type t() :: %__MODULE__{
      log: List.t()
    }
  end

  @impl GenServer
  def init(_arg) do
    :ok = :syn.join(:simon, :node, self())
    Logger.debug("Started")
    state = %State{log: []}
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:write_log, msg}, _from, state) do
    {:reply, :ok, %State{state | log: state.log ++ msg}}
  end

  @impl GenServer
  def handle_call({:read_log, idx, count}, _from, state) do
    log = Enum.slice(state.log, idx, count)
    {:reply, {:ok, log}, state}
  end

  @impl GenServer
  def handle_call(:reset_log, _from, state) do
    {:reply, :ok, %State{state | log: []}}
  end
end
