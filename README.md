# Simon

Simon is a MWMR Atomic Register. Each node has RPC API that has following commands:

- read: reads reg value from node
- write: writes a value to node

## Tests

```
mix test
```

## Usage

```
# build binary
mix release

# run node A 
env RELEASE_DISTRIBUTION=name RELEASE_NODE=aaa@127.0.0.1 SIMON_PORT=9000 _build/dev/rel/sim/bin/sim start

# run node B
env RELEASE_DISTRIBUTION=name RELEASE_NODE=bbb@127.0.0.1 SIMON_PORT=9001 SIMON_DISCOVERY=aaa@127.0.0.1 _build/dev/rel/sim/bin/sim start

# run node C
env RELEASE_DISTRIBUTION=name RELEASE_NODE=ccc@127.0.0.1 SIMON_PORT=9002 SIMON_DISCOVERY=aaa@127.0.0.1 _build/dev/rel/sim/bin/sim start

# read node A reg, should be empty
curl http://localhost:9000/read && echo

# write an entry to node A reg
curl -X PUT http://localhost:9000/write -H 'Content-Type: application/json' -d '{"msg":"a}' && echo

# read node A reg, should have the value we've just added
curl http://localhost:9000/read && echo

# read node B reg, should have the value we've just added
curl http://localhost:9001/read && echo

# read node C reg, should have the value we've just added
curl http://localhost:9002/read && echo
``````
