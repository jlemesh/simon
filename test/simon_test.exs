defmodule SimonTest do
  use ExUnit.Case, async: false
  doctest Simon

  test "should read and write" do
    :ok = LocalCluster.start()
    nodes = LocalCluster.start_nodes("replica", 3)
    [n1, n2, n3] = nodes
    assert Node.ping(n1) == :pong
    assert Node.ping(n2) == :pong
    assert Node.ping(n3) == :pong

    Process.sleep(3000)
    Simon.Client.write("a")

    # v = Simon.Node.read()
    # assert v == "a"

    #Simon.Node.write("b")

    # LocalCluster.stop_nodes([n1])

    # v = Simon.Node.read()
    # assert v == "b"

    # nodes1 = LocalCluster.start_nodes("sim1", 1)

    # [n4] = nodes1

    # assert Node.ping(n4) == :pong

    # Simon.Node.write("c")

    # v = Simon.Node.read()
    # assert v == "c"

    LocalCluster.stop_nodes([n2, n3])
  end
end
