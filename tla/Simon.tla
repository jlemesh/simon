------------------------------- MODULE Simon -------------------------------
EXTENDS Integers, Sequences, FiniteSets, TLC
CONSTANT Nodes, Values
VARIABLE requests, view_num, replica_num, op_num, log, commit_num, config, storage

InitRequests ==
    [type : {"write"}, receiver: Nodes, value: Values, client_id: {0}, req_num: 0..1]

Requests == 
    InitRequests
    \union [type : {"prepare"}, receiver: Nodes, sender: Nodes, view_num: 0..1, request: InitRequests, op_num: 0..2, commit_num: 0..2]
    \union [type : {"prepare_ok"}, receiver: Nodes, sender: Nodes, view_num: 0..1, op_num: 0..2, replica_num: 0..2]
    \union [type : {"get_state"}, receiver: Nodes, sender: Nodes, view_num: 0..1, commit_num: 0..2]
    \union [type : {"new_state"}, receiver: Nodes, sender: Nodes, view_num: 0..1, log: Seq(InitRequests), op_num: 0..2, commit_num: 0..2]

TypeOK ==
  /\ requests \subseteq Requests
  /\ view_num \in [Nodes -> Nat]
  /\ replica_num \in [Nodes -> Nat]
  /\ op_num \in [Nodes -> Nat]
  /\ log \in [Nodes -> Seq(InitRequests)]
  /\ commit_num \in [Nodes -> Nat]
  /\ config \in [Nodes -> Seq(Nodes)]
  /\ storage \in [Nodes -> Seq(Values)]

IsPrimary(replica, view) == (view % Cardinality(Nodes))  = replica

GetPrimary(view, node_config) == node_config[view % Cardinality(Nodes)]

IsInjective(s) == \A i, j \in DOMAIN s: (s[i] = s[j]) => (i = j)

SetToSeq(S) == CHOOSE f \in [1..Cardinality(S) -> S] : IsInjective(f)

PrepareOKReq(n, op) == {r \in requests: r.type = "prepare_ok" /\ r.receiver = n /\ r.op_num = op }

Range(f) == {f[x]: x \in DOMAIN f}

Write(n) ==
    \E r \in requests:
        /\ r.type = "write"
        /\ r.receiver = n
        /\ GetPrimary(view_num[n], config[n]) = n
        /\ op_num' = [op_num EXCEPT ![n] = op_num[n] + 1]
        /\ log' = [log EXCEPT ![n] = Append(log[n], r)]
        /\ requests' = (requests \ {r})
            \cup {[type|-> "prepare", 
            receiver |-> no,
            sender |-> n,
            view_num |-> view_num[n],
            op_num |-> op_num[n] + 1,
            commit_num |-> commit_num[n],
            request |-> r] : no \in Nodes}
        /\ UNCHANGED <<view_num, replica_num, commit_num, config, storage>>

Prepare0(n) ==
  \E r \in requests:
    /\ r.type = "prepare"
    /\ r.receiver = n
    /\ GetPrimary(view_num[n], config[n]) # n
    /\ op_num[n] < r.op_num - 1
    /\ op_num' = [op_num EXCEPT ![n] = r.commit_num]
    /\ requests' = (requests \ {r}) \cup {[type|-> "get_state",
        receiver |-> GetPrimary(view_num[n], config[n]), 
        sender |-> n, 
        view_num |-> view_num[n],
        commit_num |-> commit_num[n]]}
    /\ UNCHANGED <<view_num, replica_num, config, commit_num, log, storage>>

Prepare1(n) ==
  \E r \in requests:
    /\ r.type = "prepare"
    /\ r.receiver = n
    /\ GetPrimary(view_num[n], config[n]) # n
    /\ op_num[n] >= r.op_num - 1
    /\ Len(log[n]) > r.commit_num
    /\ commit_num[n] < r.commit_num
    /\ log' = [log EXCEPT ![n] = Append(log[n], r.request)]
    /\ op_num' = [op_num EXCEPT ![n] = r.op_num]
    /\ commit_num' = [commit_num EXCEPT ![n] = r.commit_num]
    /\ storage' = [storage EXCEPT ![n] = Append(storage[n], log[n][r.commit_num].value)]
    /\ requests' = (requests \ {r})
        \cup {[type|-> "prepare_ok",
        receiver |-> GetPrimary(view_num[n], config[n]), 
        sender |-> n, 
        view_num |-> view_num[n],
        op_num |-> r.op_num,
        replica_num |-> replica_num[n]]}
    /\ UNCHANGED <<view_num, replica_num, config>>

Prepare2(n) ==
  \E r \in requests:
    /\ r.type = "prepare"
    /\ r.receiver = n
    /\ GetPrimary(view_num[n], config[n]) # n
    /\ op_num[n] = r.op_num - 1
    /\ Len(log[n]) > r.commit_num
    /\ log' = [log EXCEPT ![n] = Append(log[n], r.request)]
    /\ op_num' = [op_num EXCEPT ![n] = r.op_num]
    /\ commit_num' = [commit_num EXCEPT ![n] = r.commit_num]
    /\ requests' = (requests \ {r})
        \cup {[type|-> "prepare_ok",
        receiver |-> GetPrimary(view_num[n], config[n]), 
        sender |-> n, 
        view_num |-> view_num[n],
        op_num |-> r.op_num,
        replica_num |-> replica_num[n]]}
    /\ UNCHANGED <<view_num, replica_num, config, storage>>

Prepare3(n) ==
  \E r \in requests:
    /\ r.type = "prepare"
    /\ r.receiver = n
    /\ GetPrimary(view_num[n], config[n]) # n
    /\ op_num[n] >= r.op_num - 1
    /\ Len(log[n]) <= r.commit_num
    /\ log' = [log EXCEPT ![n] = Append(log[n], r.request)]
    /\ op_num' = [op_num EXCEPT ![n] = r.op_num]
    /\ requests' = (requests \ {r})
        \cup {[type|-> "prepare_ok",
        receiver |-> GetPrimary(view_num[n], config[n]), 
        sender |-> n, 
        view_num |-> view_num[n],
        op_num |-> r.op_num,
        replica_num |-> replica_num[n]]}
    /\ UNCHANGED <<view_num, replica_num, config, commit_num, storage>>

PrepareOK(n) ==
  \E r \in requests:
    /\ r.type = "prepare_ok"
    /\ r.receiver = n
    /\ GetPrimary(view_num[n], config[n]) = n
    /\ Cardinality(PrepareOKReq(n, r.op_num)) > Cardinality(Nodes) \div 2
    /\ storage' = [storage EXCEPT ![n] = Append(storage[n], log[n][r.op_num].value)]
    /\ commit_num' = [commit_num EXCEPT ![n] = commit_num[n] + 1]
    /\ requests' = (requests \ {r})
    /\ UNCHANGED <<view_num, replica_num, op_num, log, config>>

GetState(n) ==
  \E r \in requests:
    /\ r.type = "get_state"
    /\ r.receiver = n
    /\ requests' = (requests \ {r})
        \cup {[type|-> "new_state",
        receiver |-> r.sender, 
        sender |-> n, 
        view_num |-> view_num[n],
        log |-> SubSeq(log[n], r.commit_num + 1, Len(log[n])),
        op_num |-> op_num[n],
        commit_num |-> commit_num[n]]}
    /\ UNCHANGED <<view_num, replica_num, op_num, log, config, commit_num, storage>>

NewState(n) ==
  \E r \in requests:
    /\ r.type = "new_state"
    /\ r.receiver = n
    /\ r.op_num > op_num[n]
    /\ storage' = [storage EXCEPT ![n] = storage[n] \o SetToSeq({x.value: x \in Range(SubSeq(r.log, 1, r.commit_num - commit_num[n]))})]
    /\ commit_num' = [commit_num EXCEPT ![n] = r.commit_num]
    /\ log' = [log EXCEPT ![n] = log[n] \o SubSeq(r.log, op_num[n]+1, Len(r.log))]
    /\ op_num' = [op_num EXCEPT ![n] = r.op_num]
    /\ requests' = (requests \ {r})
    /\ UNCHANGED <<view_num, replica_num, config>>

Init ==
  /\ log = [ n \in Nodes |-> <<>> ]
  /\ view_num = [ n \in Nodes |-> 1 ]
  /\ replica_num = [ n \in Nodes |-> 0 ]
  /\ requests \in SUBSET InitRequests
  /\ op_num = [ n \in Nodes |-> 0 ]
  /\ commit_num = [ n \in Nodes |-> 0 ]
  /\ config = [ n \in Nodes |-> SetToSeq(Nodes) ]
  /\ storage = [ n \in Nodes |-> <<>> ]

Next == \E n \in Nodes : Write(n) \/ Prepare0(n) \/ Prepare1(n) \/ Prepare2(n) \/ Prepare3(n) \/ PrepareOK(n) \/ GetState(n) \/ NewState(n)

Spec == Init /\ [][Next]_<<requests, view_num, replica_num, op_num, log, commit_num, config, storage>> /\ WF_<<requests, view_num, replica_num, op_num, log, commit_num, config, storage>>(Next)

Consistent == \A n, s \in Nodes: log[n] = log[s]

EventuallyConsistent == <>[]Consistent

=============================================================================
