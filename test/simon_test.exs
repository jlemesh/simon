defmodule SimonTest do
  use ExUnit.Case, async: false
  doctest Simon

  test "should read and write" do
    :ok = LocalCluster.start()
    [n1] = LocalCluster.start_nodes("primary", 1)

    Process.sleep(500)

    [n2, n3, n4, n5, n6] = LocalCluster.start_nodes("backup", 5)

    Process.sleep(3000)

    Simon.Client.write("a")

    v = Simon.Client.get_log()
    assert length(v) == 7

    Simon.Client.write("b")

    v = Simon.Client.get_log()
    assert length(Enum.at(v, 1)) == 2

    v = Simon.Client.get_storage()
    assert v == [[], ["a", "b"], ["a"], ["a"], ["a"], ["a"], ["a"]]

    Simon.Client.reset(n4)

    Process.sleep(300)
    # LocalCluster.stop_nodes([n4])

    # [n4] = LocalCluster.start_nodes("simon", 1)

    Simon.Client.write("c")

    v = Simon.Client.get_log()
    [entry1, entry2, {{:write, v}, _pid, req_num, _ref}] = Enum.at(v, 3) # n4
    assert v == "c"
    assert req_num == 3

    v = Simon.Client.get_storage()
    assert v == [[], ["a", "b", "c"], ["a", "b"], ["a", "b"], ["a", "b"], ["a", "b"], ["a", "b"]]

    # assert Node.ping(n4) == :pong

    # Simon.Node.write("c")

    # v = Simon.Node.read()
    # assert v == "c"

    LocalCluster.stop_nodes([n2, n3])
  end
end
