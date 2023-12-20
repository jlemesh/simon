# Simon

Simon is a VSR.

## TODOs

- send commit when no requests from client

## Links

https://github.com/penberg/vsr-rs/blob/main/src/replica.rs
https://charap.co/reading-group-viewstamped-replication-revisited/
https://dspace.mit.edu/bitstream/handle/1721.1/71763/MIT-CSAIL-TR-2012-021.pdf?sequence=1
https://medium.com/@polyglot_factotum/understand-viewstamped-replication-with-rust-automerge-and-tla-7a94e9e4d553
https://jack-vanlightly.com/analyses/2022/12/20/vr-revisited-an-analysis-with-tlaplus

## Tests

```
mix test
```

## Usage

```
# build binary
mix release

# run node A with client
env RELEASE_DISTRIBUTION=name RELEASE_NODE=aaa@127.0.0.1 SIMON_PORT=9000 _build/dev/rel/sim/bin/sim start

# run node B
env RELEASE_DISTRIBUTION=name RELEASE_NODE=bbb@127.0.0.1 SIMON_PORT=9001 SIMON_DISCOVERY=aaa@127.0.0.1 _build/dev/rel/sim/bin/sim start

# run node C
env RELEASE_DISTRIBUTION=name RELEASE_NODE=ccc@127.0.0.1 SIMON_PORT=9002 SIMON_DISCOVERY=aaa@127.0.0.1 _build/dev/rel/sim/bin/sim start

# read node A reg, should be empty
curl http://localhost:9000/read && echo

# write an entry to node A reg
curl -X PUT http://localhost:9000/write -H 'Content-Type: application/json' -d '{"msg":"a"}' && echo

# read node A reg, should have the value we've just added
curl http://localhost:9000/read && echo

# read node B reg, should have the value we've just added
curl http://localhost:9001/read && echo

# read node C reg, should have the value we've just added
curl http://localhost:9002/read && echo
```
