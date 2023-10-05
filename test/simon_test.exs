defmodule SimonTest do
  use ExUnit.Case, async: false
  doctest Simon

  test "should write to log" do
    :ok = Simon.Node.write_log(["one"])
    {:ok, log} = Simon.Node.read_log(0, 5)
    assert log == ["one"]
    Simon.Node.stop()
  end

  test "should replicate" do
    :ok = LocalCluster.start()
    nodes = LocalCluster.start_nodes("sim", 1)
    [n1] = nodes
    assert Node.ping(n1) == :pong

    :ok = Simon.Replicator.start_replicate(n1)
    {:ok, log} = Simon.Node.read_log(0, 5)
    assert log == []

    :ok = GenServer.call({Simon.Node, n1}, {:write_log, ["two"]})
    {:ok, log} = GenServer.call({Simon.Node, n1}, {:read_log, 0, 5})
    assert log == ["two"]

    Process.sleep(2000)

    {:ok, log} = Simon.Node.read_log(0, 5)
    assert log == ["two"]

    :ok = GenServer.call({Simon.Node, n1}, {:write_log, ["three", "four", "five"]})
    {:ok, log} = GenServer.call({Simon.Node, n1}, {:read_log, 0, 5})
    assert log == ["two", "three", "four", "five"]

    Process.sleep(1000)

    {:ok, log} = Simon.Node.read_log(0, 5)
    assert log == ["two", "three", "four"]

    Process.sleep(2000)

    :ok = Simon.Replicator.stop_replicate()

    {:ok, log} = Simon.Node.read_log(0, 5)
    assert log == ["two", "three", "four", "five"]

    :ok = GenServer.call({Simon.Node, n1}, {:write_log, ["six"]})
    {:ok, log} = GenServer.call({Simon.Node, n1}, {:read_log, 0, 5})
    assert log == ["two", "three", "four", "five", "six"]

    Process.sleep(2000)

    {:ok, log} = Simon.Node.read_log(0, 5)
    assert log == ["two", "three", "four", "five"]

    :ok = LocalCluster.stop()
    Simon.Node.stop()
  end

  test "should reset log before replicating" do
    :ok = LocalCluster.start()
    nodes = LocalCluster.start_nodes("sim", 1)
    [n1] = nodes
    assert Node.ping(n1) == :pong

    :ok = Simon.Node.write_log(["zero"])

    :ok = Simon.Replicator.start_replicate(n1)
    {:ok, log} = Simon.Node.read_log(0, 5)
    assert log == []

    :ok = GenServer.call({Simon.Node, n1}, {:write_log, ["one"]})
    {:ok, log} = GenServer.call({Simon.Node, n1}, {:read_log, 0, 5})
    assert log == ["one"]

    Process.sleep(2000)

    {:ok, log} = Simon.Node.read_log(0, 5)
    assert log == ["one"]

    :ok = LocalCluster.stop()
    Simon.Node.stop()
  end

  test "should replicate from new node" do
    # setup
    :ok = LocalCluster.start()
    nodes = LocalCluster.start_nodes("sim", 2)
    [n1, n2] = nodes
    assert Node.ping(n1) == :pong
    assert Node.ping(n2) == :pong

    # p and n2 start replication form n1
    :ok = Simon.Replicator.start_replicate(n1)
    :ok = GenServer.call({Simon.Replicator, n2}, {:start_replicate, n1})

    # write to n1 log
    :ok = GenServer.call({Simon.Node, n1}, {:write_log, ["one", "two"]})

    # p and n2 should replicate from n1
    Process.sleep(2000)

    {:ok, log} = Simon.Node.read_log(0, 5)
    assert log == ["one", "two"]

    {:ok, log} = GenServer.call({Simon.Node, n2}, {:read_log, 0, 5})
    assert log == ["one", "two"]

    # stop replication o n2 as it wil be simon
    :ok = GenServer.call({Simon.Replicator, n2}, :stop_replicate)

    # n2 should preserve its log
    {:ok, log} = GenServer.call({Simon.Node, n2}, {:read_log, 0, 5})
    assert log == ["one", "two"]

    # p and n1 start replication from n2 with empty logs
    :ok = Simon.Replicator.start_replicate(n2)

    {:ok, log} = Simon.Node.read_log(0, 5)
    assert log == []

    :ok = GenServer.call({Simon.Replicator, n1}, {:start_replicate, n2})
    {:ok, log} = GenServer.call({Simon.Node, n1}, {:read_log, 0, 5})
    assert log == []

    Process.sleep(2000)

    # p and n1 should have replicated data from n2
    {:ok, log} = GenServer.call({Simon.Node, n2}, {:read_log, 0, 5})
    assert log == ["one", "two"]

    {:ok, log} = Simon.Node.read_log(0, 5)
    assert log == ["one", "two"]

    {:ok, log} = GenServer.call({Simon.Node, n1}, {:read_log, 0, 5})
    assert log == ["one", "two"]

    :ok = LocalCluster.stop()
    Simon.Node.stop()
  end
end
