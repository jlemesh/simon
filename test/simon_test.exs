defmodule SimonTest do
  use ExUnit.Case
  doctest Simon

  test "greets the world" do
    assert Simon.hello() == :world
  end

  test "write log" do
    start_supervised(Simon.Node)
    :ok = Simon.Node.write_log(["one"])
    {:ok, log} = Simon.Node.read_log(0, 5)
    assert log == ["one"]
  end

  test "replicate" do
    start_supervised(Simon.Node)
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
  end

  test "should replicate on top" do
    start_supervised(Simon.Node)
    :ok = LocalCluster.start()
    nodes = LocalCluster.start_nodes("sim", 1)
    [n1] = nodes
    assert Node.ping(n1) == :pong

    :ok = Simon.Node.write_log(["zero"])

    :ok = Simon.Replicator.start_replicate(n1)
    {:ok, log} = Simon.Node.read_log(0, 5)
    assert log == ["zero"]

    :ok = GenServer.call({Simon.Node, n1}, {:write_log, ["one"]})
    {:ok, log} = GenServer.call({Simon.Node, n1}, {:read_log, 0, 5})
    assert log == ["one"]

    Process.sleep(2000)

    {:ok, log} = Simon.Node.read_log(0, 5)
    assert log == ["zero", "one"]

    :ok = LocalCluster.stop()
  end
end
