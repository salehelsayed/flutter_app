All twelve first-recipient starts have positive prior endpoint (E), token (T), and sender-authorized wake (W) rows with future recorded expiry. These are prior relay registration records; their stored expiry values do not independently verify Redis key TTL or the caller’s local grant/receipt. They do not prove client authority, delivery, acceptance, or media.

| Group | First observed direction | First receipt UTC | Last observed E / T / W records | Relevant registration observations |
|---|---|---|---|---|
| call-090 | peer-006 → peer-007 | 10:10:00.044 | Recorded / recorded / recorded; future expiry | None deleted; recorded expiries remain future |
| call-091 | peer-006 → peer-007 | 10:10:17.386 | Recorded / recorded / recorded; future expiry | None deleted; recorded expiries remain future |
| call-092 | peer-006 → peer-007 | 10:10:26.992 | Recorded / recorded / recorded; future expiry | None deleted; recorded expiries remain future |
| call-093 | peer-007 → peer-008 | 10:11:36.513 | Recorded / recorded / recorded; future expiry | 008 token epoch 2→3/generation 1→2 and endpoint identity flag changed before first receipt; token identity flag unchanged |
| call-094 | peer-006 → peer-007 | 10:12:01.789 | Recorded / recorded / recorded; future expiry | None deleted; recorded expiries remain future |
| call-095 | peer-008 → peer-006 | 10:12:06.055 | Recorded / recorded / recorded; future expiry | 006 endpoint identity flag changed before first receipt; token identity flag unchanged |
| call-096 | peer-006 → peer-007 | 10:12:36.516 | Recorded / recorded / recorded; future expiry | None deleted; recorded expiries remain future |
| call-097 | peer-006 → peer-007 | 10:13:00.169 | Recorded / recorded / recorded; future expiry | None deleted; recorded expiries remain future |
| call-098 | peer-006 → peer-007 | 10:15:27.340 | Recorded / recorded / recorded; future expiry | None deleted; recorded expiries remain future |
| call-099 | peer-006 → peer-007 | 10:16:11.240 | Recorded / recorded / recorded; future expiry | 007 E/T deleted in command order between 10:16:28.312 and 10:16:29.047 anchors; W retained |
| call-100 | peer-006 → peer-007 | 10:16:28.312 | Recorded / recorded / recorded; future expiry | 007 E/T deleted in command order between 10:16:28.312 and 10:16:29.047 anchors; W retained |
| call-101 | peer-006 → peer-007 | 10:17:04.394 | Recorded / recorded / recorded; future expiry | 007 E/T restored before first receipt (token epoch 5/gen 3); deleted after reverse receipt, before canceled marker; W retained |

Registration times are unknown: the displayed mutation brackets are adjacent call-event/terminal anchors in AOF command order. The 099 and 100 metadata spans overlap; their shared deletion is one episode, not two. The export contains a second deletion during 101. Both occur well before stored E/T expiry. Their endpoint DEL + route DEL + three separate high-water HSET rows match explicit `RevokeEndpoint`; ordinary Redis expiry cannot emit this sequence. The endpoint revoke uses its own WATCH/TxPipelined transaction, while the adjacent token deletion is separate. The initiating app action, joint token/endpoint atomicity, and any effect on the call outcome are not established; endpoint tombstones do not terminalize call mailboxes. Successful endpoint writes remain strictly increasing in preferenceEpoch, with unchanged deviceKeyEpoch. Token identity-change flags are never true; refreshEpoch/generation advances alone do not demonstrate token identity churn. Failed publication attempts are not represented by successful AOF writes, so publication-race causation is not established.

Source semantics were independently verified in `go-relay-server/call_control_redis.go:1224,1252–1264`, using query `1a0b4914e6e744a4` / digest `7a2cfaa5a97cd184`; see `initial-twelve-mailbox-semantics.md`. The audited tracked files match the historical binary's embedded revision as well as the later baseline. Its `vcs.modified=true` flag leaves unknown build-time edits unverified. The observed signature supports the endpoint-revoke interpretation; it does not identify the triggering historical callback.

Machine-readable state, exact record pointers, expiries, both mailbox directions, and timing caveats: `registration-authority-analysis.json`. Original evidence preserved byte-for-byte.
