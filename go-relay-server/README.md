  1. Build the binary on the server:

  cd go-relay-server
  make build
  sudo cp relay-server /usr/local/bin/relay-server

  2. Create the service file:

  sudo nano /etc/systemd/system/relay-server.service

  [Unit]
  Description=mknoon relay server
  After=network.target

  [Service]
  Type=simple
  ExecStart=/usr/local/bin/relay-server
  WorkingDirectory=/usr/local/bin
  Restart=on-failure
  RestartSec=5
  Environment=FIREBASE_SERVICE_ACCOUNT=/etc/mknoon/firebase-service-account.json

  [Install]
  WantedBy=multi-user.target

  3. Enable and start:

  sudo mkdir -p /data/media
  sudo systemctl daemon-reload
  sudo systemctl enable relay-server
  sudo systemctl start relay-server

  Common commands:

  sudo systemctl status relay-server    # check status
  sudo journalctl -u relay-server -f    # tail logs
  sudo systemctl restart relay-server   # restart after rebuild

  Adjust the FIREBASE_SERVICE_ACCOUNT path to wherever your service account JSON lives on the EC2 instance.

## Direct inbox ACK-or-expiry custody

The protected direct-text/reaction inbox is an additive, Redis-only lane. It
keeps the frozen `/mknoon/inbox/1.0.0` protocol and adds these actions:

- `store_custody_v1`
- `retrieve_custody_pending_v1`
- `ack_custody_v1`

Successful protected operations carry
`custodyContract: "ack_or_expiry_v1"`. Protected rows use the distinct
`${REDIS_PREFIX}custody_inbox:<encoded-peer-id>` namespace; the companion row
in the legacy `${REDIS_PREFIX}inbox:<encoded-peer-id>` lane is only a
compatibility shadow for older receivers. Legacy store, retrieve, pending, and
ACK behavior remains unchanged.

Admission is deliberately default-off. Enable it only after every relay
front-end uses the same durable Redis URL and prefix:

```text
RELAY_BACKEND=redis
REDIS_URL=redis://<user>:<pass>@<host>:6379/0
REDIS_PREFIX=relay:prod:
DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED=true
```

Startup fails if `DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED=true` is combined
with an in-memory backend. Turning the flag off rejects new protected stores
but does not disable protected retrieval, ACK, or expiry; senders retain local
custody when admission is unavailable.

The deployment sequence is S0 old relay, S1 new relay with admission off, S2
all Redis-backed front-ends with admission on, then S3 capable clients. Return
from S3 to S1 by turning admission off. Production S2 still requires an ops
receipt for shared Redis configuration and an actual Redis restart/restore;
the repository's miniredis process-handoff test is not that durability proof.

The fixed-cardinality Prometheus surface is:

- `relay_inbox_custody_contract_info{revision="ack_or_expiry_v1"}`
- `relay_inbox_custody_admission_enabled`
- `relay_inbox_custody_messages_pending`
- `relay_inbox_custody_expired_total`
- `relay_inbox_custody_store_total{result="..."}`

Store result labels are limited to `stored`, `duplicate`, `rejected_full`,
`disabled`, `identity_conflict`, `ineligible`, and `failed`. Peer IDs,
entry IDs, and envelopes must never be metric labels.

## Direct media blob ACK-or-expiry custody

The protected direct-media blob lane is additive and keeps the frozen
`/mknoon/media/1.0.0` protocol. It adds `upload_custody_v1` and
`ack_custody_v1`; the existing `download` action becomes strict only when the
complete custody tuple is present. Legacy upload, download, delete, and list
requests remain legacy. There is no protected list action.

Successful strict operations prove `custodyKind: "direct_media_blob_v1"` and
`custodyContract: "ack_or_expiry_v1"` together with the canonical recipient,
blob ID, lowercase ciphertext SHA-256, ciphertext size, MIME, and original
expiry. A completed download is non-destructive. Only an exact ACK from the
authenticated recipient retires the blob before expiry, and that ACK is pinned
by the client to the relay that supplied the strict download proof.

Protected files and commit markers live below the isolated
`<media-root>/.custody-v1/` subtree. This is a single-writer filesystem design:
do not mount one media directory into concurrent relay processes. One relay
holds the accepted blob; the contract does not replicate or fan out protected
bytes across relays.

Admission is deliberately default-off:

```text
DIRECT_MEDIA_BLOB_CUSTODY_ADMISSION_ENABLED=false
```

With admission off, a relay rejects only new strict uploads before body
transfer. It still reconciles, downloads, ACKs, expires, and retries cleanup for
already committed protected state. Turning admission off is therefore the
drain control, not permission to delete the `.custody-v1` subtree.

Use a relay-first rollout: deploy the upgraded binary to every relay with
admission off, verify filesystem ownership/capacity and reconstructed gauges,
then enable admission only after the upgraded fleet is ready. Capable clients
come after that relay wave. Once any strict blob has been admitted, do not roll
back to an old binary, which cannot drain protected state. Turn admission off
and roll forward with an upgraded binary instead. This repository change does
not enable production admission or add a feature caller.

The fixed-cardinality Prometheus surface is:

- `relay_media_custody_contract_info{revision="ack_or_expiry_v1"}`
- `relay_media_custody_admission_enabled`
- `relay_media_custody_blobs_pending`
- `relay_media_custody_bytes_pending`
- `relay_media_custody_tombstones`
- `relay_media_custody_outcomes_total{outcome="..."}`

Outcome labels are bounded implementation constants covering stored,
duplicate, full, conflict, ACK, already-ACKed, expiry, and cleanup states.
Peer IDs, blob IDs, hashes, MIME values, and other request data must never be
metric labels.
