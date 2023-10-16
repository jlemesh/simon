------------------------------- MODULE Simon -------------------------------
EXTENDS Integers, Sequences
CONSTANT Nodes, Entries, ReplicateStep, NilNode
VARIABLE log, simon, requests

ASSUME
  /\ ReplicateStep \in Nat

Requests == [type : {"write_log"}, node: Nodes, log: [1..2 -> Entries]]
 \union [type : {"start_replicate"}, node: Nodes, simon: Nodes]
 \union [type : {"stop_replicate"}, node: Nodes]

TypeOK ==
  /\ log \in [Nodes -> Seq(Entries)]
  /\ simon \in [Nodes -> (Nodes \union {NilNode})]
  /\ requests \subseteq Requests

ReplicationEnd(len_n, len_s, step) == IF len_n + step <= len_s THEN len_n + step ELSE len_s

Replicate(s, n) ==
  /\ simon[n] = s
  /\ n /= s
  /\ Len(log[n]) < Len(log[s])
  /\ log' = [log EXCEPT ![n] = log[n] \o SubSeq(log[s], Len(log[n]) + 1, ReplicationEnd(Len(log[n]), Len(log[s]), ReplicateStep))]
  /\ UNCHANGED <<simon, requests>>

WriteLog(n) ==
  \E r \in requests:
    /\ r.type = "write_log"
    /\ log' = [log EXCEPT ![n] = log[n] \o r.log]
    /\ requests' = requests \ {r}
    /\ simon[n] = NilNode
    /\ UNCHANGED <<simon>>

StartReplicate(n) ==
  \E r \in requests:
    /\ r.node = n
    /\ r.type = "start_replicate"
    /\ r.simon /= n
    /\ simon[r.simon] /= r.node
    /\ simon' = [simon EXCEPT ![n] = r.simon]
    /\ requests' = requests \ {r}
    /\ log' = [log EXCEPT ![n] = <<>>]

StopReplicate(n) ==
  \E r \in requests:
    /\ r.node = n
    /\ r.type = "stop_replicate"
    /\ simon' = [simon EXCEPT ![n] = NilNode]
    /\ requests' = requests \ {r}
    /\ UNCHANGED <<log>>

Init ==
  /\ log = [ n \in Nodes |-> <<>> ]
  /\ simon = [ n \in Nodes |-> NilNode ]
  /\ requests \in SUBSET Requests

Next == \E s, n \in Nodes : WriteLog(n) \/ StartReplicate(n) \/ StopReplicate(n) \/ Replicate(s, n)

Spec == Init /\ [][Next]_<<log, simon, requests>> /\ WF_<<log, simon, requests>>(Next)

Consistent == \A s, n \in Nodes: IF simon[n] = s THEN log[s] = log[n] ELSE TRUE

EventuallyConsistent == <>[]Consistent

=============================================================================
\* Modification History
\* Last modified Sat Oct 14 20:39:36 EEST 2023 by jelizaveta
\* Created Sat Oct 07 20:42:41 EEST 2023 by jelizaveta
