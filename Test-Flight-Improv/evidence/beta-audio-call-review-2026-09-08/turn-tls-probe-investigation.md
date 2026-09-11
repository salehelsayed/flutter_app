# TURN TLS probe loss was a test-client framing defect

The reported TLS loss came from coturn 4.18.0's `turnutils_uclient` receive accounting. An independent TLS client that preserves stream frame boundaries delivered **400/400 synthetic payloads**, with exact payload matching, across IPv4 and IPv6 burst and 20 ms cases. No live server configuration or service was changed during this investigation.

## Controlled reproduction

Each uclient case sent 30 messages per endpoint, 60 total, using the same two-client relay topology. All cases exited zero; pass/fail below also requires sent and received counts to agree.

| Transport | Interval | Mode | IPv4 received/sent | IPv6 received/sent |
|---|---:|---|---:|---:|
| TLS | 20 ms | ChannelData | 33/60 | 34/60 |
| TLS | 200 ms | ChannelData | 60/60 | 60/60 |
| TLS | 20 ms | SEND indications | 28/60 | 32/60 |
| TCP | 20 ms | ChannelData | 60/60 | 60/60 |

The apparent missing packets were present in the TLS read buffers. For the IPv4 20 ms ChannelData case, the client logged 12 reads of 104 bytes, 17 of 208 bytes, two of 312 bytes and two of 416 bytes. Those 33 reads contain **60 complete 104-byte frames**, exactly the number sent. The client reported 33 received messages. IPv6 logged eight reads of 104 bytes and 26 reads of 208 bytes: **60 frames in 34 reads**, then reported 34 received messages. The SEND-indication cases show the same one-message-per-read undercount.

## Source explanation

In the exact upstream 4.18.0 source, the TLS path reads an arbitrary amount with `SSL_read` and passes that buffer to single-message processing. The plain TCP path determines the next STUN/ChannelData frame length before consuming bytes. Channel validation then reduces the buffer length to the first frame's payload length; the uclient TLS path has already consumed any subsequent frames and does not retain those trailing bytes. This matches the complete byte accounting above. [TLS and TCP receive paths](https://github.com/coturn/coturn/blob/4.18.0/src/apps/uclient/uclient.c#L1434), [single-message processing](https://github.com/coturn/coturn/blob/4.18.0/src/apps/uclient/uclient.c#L1590), [channel length normalization](https://github.com/coturn/coturn/blob/4.18.0/src/client/ns_turn_msg.c#L962).

TURN over TLS uses explicit ChannelData lengths and four-byte alignment; an SSL read is not an application-message boundary. [RFC 8656, Sections 12.4–12.6](https://www.rfc-editor.org/rfc/rfc8656.html#section-12.4).

## Independent verification

A separate standard-library Python client performed authenticated allocation and channel binding, verified the TLS certificate and hostname `mknoun.xyz`, buffered incomplete or combined STUN/ChannelData frames, and compared every received synthetic payload against its expected sender and sequence. Each case sent 50 messages per endpoint.

| Family | Interval | Sent | Received | Unique payloads and bytes match | TLS |
|---|---:|---:|---:|---|---|
| IPv4 | Burst | 100 | 100 | Yes | 1.2 |
| IPv6 | Burst | 100 | 100 | Yes | 1.2 |
| IPv4 | 20 ms | 100 | 100 | Yes | 1.2 |
| IPv6 | 20 ms | 100 | 100 | Yes | 1.2 |

Multiple frames arrived together in TLS reads in these independent cases too; the framing-aware receiver handled all of them. Every endpoint finished with zero unconsumed buffered bytes. These results establish this bounded synthetic TLS relay leg. They do not claim a successful audio call, arbitrary-duration reliability, or behavior on an untested device/network.

## Artifacts and reproduction

- `turn-tls-controlled.json`: eight sanitized uclient runs, flags without credentials, TLS read sizes, and strict count verdicts.
- `turn-tls-framed-independent.json`: four independent framed TLS runs and exact payload verdicts.
- `turn_tls_controlled_probe.py`: repeatable uclient harness.
- `turn_tls_framed_probe.py`: independent protocol harness.

The scripts generate short-lived credentials on the relay, retain them only in process memory, and persist only allowlisted metadata. Neither issuer secrets nor complete client output are exported. Re-running opens only the scripts' ephemeral synthetic relay allocations; the framed client explicitly releases them afterward.

Client: Homebrew coturn 4.18.0, macOS arm64. Server: coturn 4.6.1. Installed uclient SHA-256: `2c919898e70b0a78cfa9ced96243a089a00dd594adb59c3e5b760dd0d7f1f490`. Retrieved upstream `uclient.c` SHA-256: `ac4189f3517eafa7c51523b892c889f51d9a323e4246f4dbd1992fd15e4dcfa7`. Controlled runs occurred 11:24:30–11:25:19 UTC; independent runs occurred 11:28:05–11:28:10 UTC on September 8, 2026.
