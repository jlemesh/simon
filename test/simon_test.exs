defmodule SimonTest do
  use ExUnit.Case, async: false
  doctest Simon

  test "should write" do
    Simon.Client.reset_client()
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

    Simon.Client.write("c")

    v = Simon.Client.get_log()
    [entry1, entry2, {{:write, v}, _pid, req_num, _ref}] = Enum.at(v, 3) # n4
    assert v == "c"
    assert req_num == 3

    v = Simon.Client.get_storage()
    assert v == [[], ["a", "b", "c"], ["a", "b"], ["a", "b"], ["a", "b"], ["a", "b"], ["a", "b"]]

    LocalCluster.stop_nodes([n1, n2, n3, n4, n5, n6])
  end

  test "should write in order" do
    Simon.Client.reset_client()
    :ok = LocalCluster.start()
    [n1] = LocalCluster.start_nodes("primary", 1)

    Process.sleep(500)

    [n2, n3, n4, n5, n6] = LocalCluster.start_nodes("backup", 5)

    Process.sleep(3000)

    Simon.Client.write("a")
    Simon.Client.write("b")
    Simon.Client.write("c")
    Simon.Client.write("d")
    Simon.Client.write("e")

    Process.sleep(1000)

    v = Simon.Client.get_log()
    assert length(Enum.at(v, 1)) == 5
    [entry1, entry2, entry3, entry4, {{:write, v}, _pid, req_num, _ref}] = Enum.at(v, 4) # n5
    assert v == "e"
    assert req_num == 5

    v = Simon.Client.get_storage()
    assert v == [[], ["a", "b", "c", "d", "e"], ["a", "b", "c", "d"], ["a", "b", "c", "d"], ["a", "b", "c", "d"], ["a", "b", "c", "d"], ["a", "b", "c", "d"]]

    LocalCluster.stop_nodes([n1, n2, n3, n4, n5, n6])
  end

  test "should write with view change" do
    Simon.Node.leave
    Process.sleep(5000)

    assert :syn.member_count(:simon, :replica) == 0
    assert :syn.lookup(:simon, 1) == :undefined

    Simon.Client.reset_client()
    :ok = LocalCluster.start()
    Process.sleep(1000)
    [n1] = LocalCluster.start_nodes("primary", 1)

    assert :syn.member_count(:simon, :replica) == 1
    Process.sleep(1000)

    [n2, n3] = LocalCluster.start_nodes("backup", 2)

    Process.sleep(3000)

    Simon.Client.write("a")

    Process.sleep(7000)

    Simon.Client.write("b")

    v = Simon.Client.get_storage()
    assert v == [["a"], ["a"], ["a", "b"]]

    LocalCluster.stop_nodes([n1, n2, n3])
  end

  test "should recover" do
    Simon.Node.leave
    Process.sleep(5000)

    assert :syn.member_count(:simon, :replica) == 0
    assert :syn.lookup(:simon, 1) == :undefined

    Simon.Client.reset_client()
    :ok = LocalCluster.start()
    Process.sleep(1000)
    [n1] = LocalCluster.start_nodes("primary", 1)

    assert :syn.member_count(:simon, :replica) == 1
    Process.sleep(1000)

    [n2, n3] = LocalCluster.start_nodes("backup", 2)

    Process.sleep(1000)

    Simon.Client.write("a")

    [n4] = LocalCluster.start_nodes("new", 1)
    Process.sleep(1000)
    GenServer.cast({Simon.Node, n4}, :init_recover)
    Process.sleep(1000)

    Simon.Client.write("b")

    v = Simon.Client.get_storage()
    assert v == [["a"], ["a", "b"], ["a"], ["a"]]

    LocalCluster.stop_nodes([n1, n2, n3, n4])
  end
end
