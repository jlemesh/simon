# Simon

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `simon` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:simon, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/simon>.

mix release

env RELEASE_DISTRIBUTION=name RELEASE_NODE=aaa@127.0.0.1 SIMON_PORT=9000 _build/dev/rel/sim/bin/sim start

curl http://localhost:9000 && echo
curl http://localhost:9000/read_log?idx=0 && echo
curl -X PUT http://localhost:9000/write_log -H 'Content-Type: application/json' -d '{"msg":["two", "three"]}' && echo

env RELEASE_DISTRIBUTION=name RELEASE_NODE=bbb@127.0.0.1 SIMON_PORT=9001 _build/dev/rel/sim/bin/sim start

curl -X PUT http://localhost:9001/start_replicate -H 'Content-Type: application/json' -d '{"node":"aaa@127.0.0.1"}' && echo

env RELEASE_DISTRIBUTION=name RELEASE_NODE=bbb@127.0.0.1 SIMON_PORT=9001 _build/dev/rel/sim/bin/sim rpc 'Node.ping(:"aaa@127.0.0.1")'
