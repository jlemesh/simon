defmodule SimonTest do
  use ExUnit.Case, async: false
  doctest Simon

  test "should read and write" do
    :ok = LocalCluster.start()
    nodes = LocalCluster.start_nodes("sim", 3)
    [n1, n2, n3] = nodes
    assert Node.ping(n1) == :pong
    assert Node.ping(n2) == :pong
    assert Node.ping(n3) == :pong

    Simon.Node.write("a")

    LocalCluster.stop_nodes([n1])

    v = Simon.Node.read()
    assert v == "a"

    :ok = LocalCluster.stop()
  end
end
