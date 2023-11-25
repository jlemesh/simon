------------------------------- MODULE Simon -------------------------------
EXTENDS Integers, Sequences, FiniteSets, TLC
CONSTANT Nodes, Values, NilValue
VARIABLE reg, wsn, reqsn, requests, lw, write_buf

AllValues == Values \cup {NilValue}

InitRequests ==
    [type : {"init_write"}, receiver: Nodes, value: Values]
    \union [type : {"init_read"}, receiver: Nodes]

Requests == 
    InitRequests
    \union [type : {"read_req"}, receiver: Nodes, sender: Nodes, reqsn: 0..5]
    \union [type : {"ack_read_req"}, receiver: Nodes, sender: Nodes, reqsn: 0..5, wsn: 0..5, reg: Seq(Values \cup {NilValue}), lw: Nodes]
    \union [type : {"write"}, receiver: Nodes, sender: Nodes, reqsn: 0..5, v: AllValues, wsn: 0..5, lw: Nodes]
    \union [type : {"ack_write"}, receiver: Nodes, sender: Nodes, reqsn: 0..5]
    \union [type : {"write_req"}, receiver: Nodes, sender: Nodes, reqsn: 0..5]
    \union [type : {"ack_write_req"}, receiver: Nodes, sender: Nodes, reqsn: 0..5, wsn: 0..5]

TypeOK ==
  /\ reg \in [Nodes -> Seq(AllValues)]
  /\ wsn \in [Nodes -> Nat]
  /\ reqsn \in [Nodes -> Nat]
  /\ requests \subseteq Requests

MaxRequest(S) == CHOOSE x \in S : \A y \in S : y.wsn <= x.wsn

MinRequest(S) == CHOOSE x \in S : \A y \in S : y.wsn >= x.wsn

RequestsOfType(type, n) == {req \in requests: req.receiver = n /\ req.type = type /\ req.reqsn = reqsn[n]}

Last(seq) == Head(SubSeq(seq, Len(seq), Len(seq)))

InitRead(n) ==
    \E r \in requests:
        /\ r.type = "init_read"
        /\ r.receiver = n
        /\ requests' = (requests \ {r})
            \cup {[type|-> "read_req", receiver |-> no, sender |-> n, reqsn |-> reqsn[n] + 1] : no \in Nodes}
        /\ reqsn' = [reqsn EXCEPT ![n] = reqsn[n] + 1]
        /\ UNCHANGED <<reg, wsn, lw, write_buf>>

InitWrite(n) ==
  \E r \in requests:
    /\ r.type = "init_write"
    /\ r.receiver = n
    /\ requests' = (requests \ {r})
        \cup {[type|-> "write_req", receiver |-> no, sender |-> n, reqsn |-> reqsn[n] + 1] : no \in Nodes}
    /\ reqsn' = [reqsn EXCEPT ![n] = reqsn[n] + 1]
    /\ write_buf' = [write_buf EXCEPT ![n] = r.value]
    /\ UNCHANGED <<reg, wsn, lw>>

Write(n) ==
    \E r \in requests:
        /\ r.type = "write"
        /\ r.receiver = n
        /\ requests' = (requests \ {r}) \cup {[type|-> "ack_write", receiver |-> r.sender, sender |-> n, reqsn |-> r.reqsn]}
        /\ wsn' = IF r.wsn > wsn[n] THEN [wsn EXCEPT ![n] = r.wsn] ELSE wsn
        /\ reg' = IF r.wsn > wsn[n] THEN [reg EXCEPT ![n] = reg[n][r.wsn] :> r.v] ELSE reg
        /\ lw' = IF r.wsn > wsn[n] THEN [lw EXCEPT ![n] = r.lw] ELSE lw
        /\ UNCHANGED <<reqsn, write_buf>>

ReadReq(n) ==
    \E r \in requests:
        /\ r.type = "read_req"
        /\ r.receiver = n
        /\ requests' = (requests \ {r})
            \cup {[type|-> "ack_read_req", receiver |-> r.sender, sender |-> n, reqsn |-> reqsn[n], wsn |-> wsn[n], lw |-> n, reg |-> reg[n]]}
        /\ UNCHANGED <<reg, wsn, reqsn, lw, write_buf>>

WriteReq(n) ==
    \E r \in requests:
        /\ r.type = "write_req"
        /\ r.receiver = n
        /\ requests' = (requests \ {r})
            \cup {[type|-> "ack_write_req", receiver |-> r.sender, sender |-> n, reqsn |-> reqsn[n], wsn |-> wsn[n]]}
        /\ UNCHANGED <<reg, wsn, reqsn, lw, write_buf>>

AckReadReq(n) ==
    /\ Cardinality(RequestsOfType("ack_read_req", n)) > Cardinality(Nodes) \div 2
    /\ LET max_req == MaxRequest(RequestsOfType("ack_read_req", n))
        min_req == MinRequest(RequestsOfType("ack_read_req", n))
        IN requests' = (requests \ RequestsOfType("ack_read_req", n))
        \cup {[type|-> "write", 
            receiver |-> no, 
            sender |-> n, 
            reqsn |-> reqsn[max_req.sender] + 1, 
            v |-> max_req.reg[x + 1], 
            wsn |-> x, 
            lw |-> max_req.lw] : no \in Nodes, x \in min_req.wsn..max_req.wsn}
    /\ UNCHANGED <<reg, wsn, reqsn, lw, write_buf>>

AckWriteReq(n) ==
    /\ Cardinality(RequestsOfType("ack_write_req", n)) > Cardinality(Nodes) \div 2
    /\ LET max_req == MaxRequest(RequestsOfType("ack_write_req", n))
        min_req == MinRequest(RequestsOfType("ack_write_req", n))
        IN requests' = (requests \ RequestsOfType("ack_write_req", n))
        \cup {[type|-> "write", 
            receiver |-> no, 
            sender |-> n, 
            reqsn |-> reqsn[max_req.sender] + 1, 
            v |-> max_req.reg[x + 1], 
            wsn |-> x, 
            lw |-> max_req.lw] : no \in Nodes, x \in min_req.wsn..max_req.wsn}
        \cup {[type|-> "write", 
            receiver |-> no, 
            sender |-> n, 
            reqsn |-> reqsn[n] + 1, 
            v |-> write_buf[n], 
            wsn |-> max_req.wsn + 1, 
            lw |-> max_req.lw] : no \in Nodes}
    /\ write_buf' = [write_buf EXCEPT ![n] = NilValue]
    /\ UNCHANGED <<reg, wsn, reqsn, lw>>

AckWrite(n) ==
    /\ Cardinality(RequestsOfType("ack_write", n)) > Cardinality(Nodes) \div 2
    /\ requests' = (requests \ RequestsOfType("ack_write", n))
    /\ UNCHANGED <<reg, wsn, reqsn, lw, write_buf>>

Init ==
  /\ reg = [ n \in Nodes |-> <<NilValue>> ]
  /\ wsn = [ n \in Nodes |-> 0 ]
  /\ reqsn = [ n \in Nodes |-> 0 ]
  /\ requests \in SUBSET InitRequests
  /\ lw = [ n \in Nodes |-> n ]
  /\ write_buf = [ n \in Nodes |-> NilValue ]

Next == \E n \in Nodes : InitRead(n) \/ ReadReq(n) \/ AckReadReq(n) \/ AckWrite(n) \/ Write(n) \/ InitWrite(n)

Spec == Init /\ [][Next]_<<reg, wsn, reqsn, requests, lw, write_buf>> /\ WF_<<reg, wsn, reqsn, requests, lw, write_buf>>(Next)

Consistent == \A n, s \in Nodes: reg[n] = reg[s]

EventuallyConsistent == <>[]Consistent

=============================================================================
\* Modification History
\* Last modified Sat Oct 14 20:39:36 EEST 2023 by jelizaveta
\* Created Sat Oct 07 20:42:41 EEST 2023 by jelizaveta
