# TURN credential operations (VC2-01)

Status: repository support is implemented behind `TURN_CREDENTIALS_ENABLED` and
is off by default. The active environment is separate from that source default.
September 14 read-only inspection found the existing service enabled with
UDP/TCP 3478 and TLS 5349, IPv4/IPv6 listeners and relay range 49152–50175.
Current owners, hashes, independent allocation/media results and unresolved
native TLS/network legs are recorded in
[IPV6-Infra-Ops.md](../../Network-Arch/IPV6-Infra-Ops.md). Earlier statements that
production activation was wholly unobserved are superseded by those dated
observations; they do not establish permanent availability or release approval.

## Runtime custody

The later September 14 network audit found the configured global IPv6 address
absent from the relay's interfaces while old coturn sockets remained bound.
Listener presence therefore no longer established endpoint availability at that
instant. No production repair/restart was performed by that follow-up. See the
[current network verification boundary](../../Network-Arch/IPV6-Infra-Ops.md#remaining-network-scenarios-current-verification-boundary)
for the dated address/route evidence and unresolved credential failures. The
19:11 UTC recheck found restored IPv6 and two successful fresh credential
requests through the normal hostname path. DNS IPv4 had changed; the old numeric
fixture pin still failed and must not be used to judge the recovered service.
That readiness check did not rerun native media or explain the older UDP loss.

For independent diagnostics, `integration_test/scripts/turn_path_probe.py`
keeps connection and allocation families separate, observes sequence/timing at
both client sockets, and releases allocations. Its `--local-fixture` mode
requires an already isolated Linux namespace with only loopback; it refuses a
routable host before mutation and uses its own coturn configuration, process
and generated credential. Wrap it in the documented bounded `unshare`/`timeout`
command and collect cleanup before removing the owned stage. This does not
change the production service or supply a phone-facing IPv6/NAT64 network.
The retained TLS parser's reuse for UDP incorrectly required stream padding on
unaligned datagrams; that diagnostic defect is repaired. The historical failed
100-byte UDP trial was aligned, so its original cause remains unresolved.

The focused post-recovery IPv4 checks reproduce a separate configuration fault:
the configured `external-ip` public/private mapping still advertises the previous
public IPv4. Three external-peer trials each lose all three synthetic packets at
that advertised address; all three paired current-address controls receive all
three. Two allocations on the same coturn can still pass through its existing
hairpin mapping, so same-server echo or native media does not validate public
allocation reachability. Native public UDP media and fresh serial/paced controls
now pass within their recorded scopes; they do not explain the old 10/11 loss.

The existing operator helper supports a separate non-mutating IPv4-only preview:

```sh
# On the relay, after discovering its current public and assigned private IPv4:
sudo -n python3 fix_coturn_dual_stack_tls.py --external-ip-only \
  --private-ipv4 "$TURN_PRIVATE_IPV4" --public-ipv4 "$TURN_PUBLIC_IPV4"
```

This mode preserves listeners, TLS files/hooks and every unrelated config byte.
Only after deployment is authorized, repeat with the exact returned
`--expect-config-sha256 "$TURN_PREVIEW_SHA256" --apply`. It refuses active
allocations, saves a private backup and restores the original mapping if the
bounded service restart fails. Following the recorded preview, the one-line
patch was **authorized and applied at 20:28 UTC on September 14**.
Fresh preflight found zero allocations; the post-apply byte/hash audit confirms
only the public IPv4 changed and certificates/hooks and the messaging relay
process were preserved. All three external advertised-address trials now pass,
as do the paired controls and the post-repair native UDP proof. No app rebuild
was required. Exact receipts are in the canonical network verification record;
the older 10/11 datagram loss remains unexplained, and the IPv6 UDP comparison's
two failures are retained separately.
The retained `run_external_peer.py` driver in the canonical private evidence
directory uses the existing `TurnProbe`, three fixed fresh-allocation pairs,
authenticated permissions, 100-byte sequence records and seven-second reads,
then Refresh(0) and socket/client cleanup. Its current-address control is a raw
protocol diagnostic; never rewrite app ICE candidates as a workaround.

The relay process reads configuration at startup from these names only:

- `TURN_CREDENTIALS_ENABLED`
- `TURN_CREDENTIAL_URLS`
- `TURN_CREDENTIAL_PRIMARY_SECRET_B64`
- `TURN_CREDENTIAL_VERIFICATION_SECRETS_B64`

Never place their values in application bundles, logs, diagnostics, tickets, or
test artifacts. An enabled but incomplete or malformed configuration fails
closed at startup. There is no static application credential fallback.

The mint action is authenticated by the existing relay stream. It derives the
credential subject from that authenticated stream and does not accept a claimed
identity in the request body. The response is allowlisted and logs/metrics use
fixed outcome labels only. Per-subject process-local admission limits bound mint
work before secret-provider access. A production deployment also needs an
independent shared or edge abuse-control layer when multiple relay processes are
used; the in-process limiter must not be represented as a global quota.

## Lifecycle and outage behavior

- Credentials are short-lived and prefetched before expiry.
- Credential expiry is not a maximum call duration. An already healthy TURN
  allocation may continue during a mint outage; this repository does not assume
  how long a deployed coturn allocation survives without a live allocation test.
- A new allocation or ICE restart must obtain a valid bundle within the bounded
  retry budget. Privacy-protected calls must not downgrade to a direct route.
  Normal-mode calls may attempt direct ICE after a typed transient availability
  failure within the existing deadline; authentication/configuration rejection
  remains fail-closed. The policy frozen for that call governs recovery.
- Superseded or closed staged bundles are released from the client lifecycle as
  soon as practical. Long-lived copies in telemetry or persistence are forbidden.

## Rotation and rollback

Rotate with an overlap window: advertise a new primary mint secret while the
verification set continues to accept the prior secret for at least the full
advertised credential lifetime plus measured clock-skew allowance. Remove the
prior secret only after that drain window. Roll back by restoring the previous
primary while retaining both verification entries through the same window.

Restart relay and TURN processes independently. First disable minting with the
feature flag if required, then drain dependent allocations according to the
deployed coturn policy. A relay restart must not be treated as proof that coturn
allocations were preserved, and a coturn restart must not silently enable direct
fallback.

## Production readiness checklist (requires per-boundary evidence)

- DNS and certificate ownership are approved and observable without exposing
  credential material.
- UDP/TCP 3478 and TLS/TCP 5349 are independently tested. TLS/TCP 443 and
  443-only calling remain separate unprovisioned/unverified requirements; a
  normal HTTPS listener is not proof of TURN or application signaling on 443.
- The relay allocation port range and cloud/network firewalls are documented,
  least-privilege, and tested from the supported networks.
- Quotas, process/global rate controls, saturation alerts, certificate expiry,
  mint failure rates, and allocation health have owners and rollback thresholds.
- Authenticated allocation, media relay, long-call behavior across credential
  expiry, mint outage continuity, wrong-secret rejection, overlap rotation, and
  rollback are demonstrated without recording identifiers, endpoint addresses,
  credentials, candidates, or session descriptions.

Repository unit, bridge, and device tests may prove grammar and local lifecycle
behavior. They cannot substitute for these deployed TURN acceptance legs.

The initial September 14 integrated validation retained native Android TLS as failed:
the protected call could not select a relay pair. The current public chain also
fails against the pinned WebRTC trust roots at ISRG Root X2, while a temporary
verifier input containing that root passes. System-trusted host TLS success does
not certify the native library. The certificate preflight and staged repair in
[`IPV6-Infra-Ops.md`](../../Network-Arch/IPV6-Infra-Ops.md#native-turntls-proven-android-repair-not-published)
require normal hostname/chain validation and native protected media proof before
promotion. Working UDP/TCP alternatives remain configured. No production
certificate, trust policy, key or service was changed by that validation.

The native follow-up supersedes that result for an Android debug fixture using
WebRTC SDK `144.7559.14`: TLS-only protected media and the full mixed-policy
matrix pass against the unchanged public listener, with certificate/hostname
verification enabled. The Android-only dependency override is in
`android/build.gradle.kts`; `flutter_webrtc` 1.6.0, Flutter and iOS/desktop pins are unchanged.
The old `.09` runtime still fails. No signed app was published, and iOS parity
and audible audio are unverified. See the current
[native diagnosis and receipts](../../Network-Arch/IPV6-Infra-Ops.md#native-turntls-proven-android-repair-not-published).

## Staged atomic certificate hook (not executed)

The active lineage is `/etc/letsencrypt/live/mknoun.xyz`, managed by Certbot
2.9.0 through its existing timer, nginx authenticator/installer and
`/etc/letsencrypt/renewal/mknoun.xyz.conf`. The deployed chain is already the
default YE2 chain through X2 to X1. The CA's
[currently offered alternatives](https://letsencrypt.org/ca/certificates/)
cannot chain to the old native runtime's 36 anchors. Retain the valid certificate
and the existing default chain selection; no issuance or preferred-chain change
is needed for the Android repair. The public-root admission check below rejects
a future unsupported chain instead of silently breaking renewed TLS.

The existing `/etc/letsencrypt/renewal-hooks/deploy/50-mknoon-coturn` copies
certificate and key independently, then signals coturn. Replace **that hook**
with [50-mknoon-coturn](../../docker-ws/50-mknoon-coturn) and its
[guard](../../docker-ws/coturn_tls_deploy.py); do not install a second renewal
system or rerun historical deployment scripts. Certbot's
[deploy-hook contract](https://eff-certbot.readthedocs.io/en/stable/using.html#renewing-certificates)
runs after successful renewal. A nonzero guard result must reach operational
monitoring: preserving the old certificate only contains the failure until its
expiry. Inspect `certbot.service` and coturn logs after the next scheduled renewal.

The guard uses a public trust bundle derived from both tested Android system
stores plus the unchanged built-in WebRTC anchors, intersected across the two
targets. The prepared bundle is
`.codex-test-logs/native-turn-tls-20260914/tested-android-trust.pem` (140 anchors,
SHA-256 `ef6088d20a02aeadd843ea7b28b725fa9219ec01453900cb7d7c8ea2795335d4`).
It is a **server preflight input**, never a client-installed certificate store.
No server intermediate was promoted into it. A different supported runtime or
CA/root transition requires refreshed provenance and native media proof.

The following is an approval-ready procedure, **not an executed deployment**.
Copy the reviewed helper, hook and public trust bundle into a root-only stage
directory `/root/mknoon-turn-tls-stage/` under names `coturn_tls_deploy.py`,
`50-mknoon-coturn` and `tested-android-trust.pem`. Verify their local/staged
SHA-256 digests before installation. On the server, with root privileges:

```sh
set -eu
umask 077
test "$(systemctl is-active certbot.service || true)" = inactive
TURN_TLS_BACKUP=/var/backups/mknoon/coturn-tls-20260914
test ! -e "$TURN_TLS_BACKUP"
install -d -m 0700 "$TURN_TLS_BACKUP"
cp -a /etc/coturn/tls "$TURN_TLS_BACKUP/tls"
cp -a /etc/turnserver.conf "$TURN_TLS_BACKUP/turnserver.conf"
cp -a /etc/letsencrypt/renewal/mknoun.xyz.conf "$TURN_TLS_BACKUP/renewal.conf"
cp -a /etc/letsencrypt/renewal-hooks/deploy/50-mknoon-coturn "$TURN_TLS_BACKUP/hook"

install -d -o root -g root -m 0755 /usr/local/libexec
install -o root -g root -m 0750 /root/mknoon-turn-tls-stage/coturn_tls_deploy.py \
  /usr/local/libexec/mknoon-coturn-tls-deploy.py
install -o root -g turnserver -m 0640 /root/mknoon-turn-tls-stage/tested-android-trust.pem \
  /etc/coturn/tls/trust-anchors.pem
python3 /usr/local/libexec/mknoon-coturn-tls-deploy.py check \
  --lineage /etc/letsencrypt/live/mknoun.xyz --trust /etc/coturn/tls/trust-anchors.pem
python3 /usr/local/libexec/mknoon-coturn-tls-deploy.py prepare \
  --lineage /etc/letsencrypt/live/mknoun.xyz --trust /etc/coturn/tls/trust-anchors.pem
install -o root -g root -m 0750 /root/mknoon-turn-tls-stage/50-mknoon-coturn \
  /etc/letsencrypt/renewal-hooks/deploy/50-mknoon-coturn
```

`prepare` validates a snapshot of the **currently configured** pair and converts
the two existing paths into `current/fullchain.pem` and `current/privkey.pem`
links. Both files contain identical bytes throughout this conversion, and no
signal is sent. The coturn configuration and certificate lineage paths stay
the same. Each subsequent hook invocation snapshots both renewed files under
`/etc/coturn/tls/generations/`, checks at least seven days of validity, hostname,
server purpose, chain ordering and key match, then switches the single `current`
link under an exclusive lock. Directories are root:turnserver 0750 and key files
0640; keep the root-only backup and previous generations on the server.

After installation, verify both unchanged listeners independently:

```sh
openssl s_client -connect 127.0.0.1:5349 -servername mknoun.xyz \
  -verify_hostname mknoun.xyz -verify_return_error -no-CApath -no-CAstore \
  -CAfile /etc/coturn/tls/trust-anchors.pem </dev/null
openssl s_client -connect '[::1]:5349' -servername mknoun.xyz \
  -verify_hostname mknoun.xyz -verify_return_error -no-CApath -no-CAstore \
  -CAfile /etc/coturn/tls/trust-anchors.pem </dev/null
systemctl is-active coturn.service certbot.timer
```

These are certificate preflights, not native-media acceptance. A separately
approved invocation of the new hook with `RENEWED_LINEAGE` set to this lineage
would exercise a same-certificate live reload without issuing anything. It is
not included in the no-signal installation procedure. Do not run `certbot renew
--force-renewal` to test it. Offline malformed, missing/reversed intermediate,
wrong-hostname, untrusted, mismatched-key, near-expiry and failed-reload controls
already exercise the guard; the isolated daemon test also preserves an existing
TLS stream while fresh connections see the renewed leaf.

To undo just the no-signal installation before any renewal/promotion, first
require both configured files to remain byte-identical to the protected backup.
Restore flat paths through temporary files and then restore the old hook; no
daemon signal is needed because the bytes have not changed:

```sh
set -eu
cmp -s "$TURN_TLS_BACKUP/tls/fullchain.pem" /etc/coturn/tls/fullchain.pem
cmp -s "$TURN_TLS_BACKUP/tls/privkey.pem" /etc/coturn/tls/privkey.pem
for TURN_TLS_NAME in fullchain.pem privkey.pem; do
  install -o root -g turnserver -m 0640 "$TURN_TLS_BACKUP/tls/$TURN_TLS_NAME" \
    "/etc/coturn/tls/$TURN_TLS_NAME.restore"
  mv -Tf "/etc/coturn/tls/$TURN_TLS_NAME.restore" "/etc/coturn/tls/$TURN_TLS_NAME"
done
install -o root -g root -m 0750 "$TURN_TLS_BACKUP/hook" \
  /etc/letsencrypt/renewal-hooks/deploy/50-mknoon-coturn
```

If either comparison fails, stop this installation rollback and use the
validated certificate rollback below. Retain the protected generations and
backup for inspection; do not recursively delete key material during rollback.

For an approved certificate rollback, first validate the protected old pair,
then promote it through the same transaction and listener checks:

```sh
python3 /usr/local/libexec/mknoon-coturn-tls-deploy.py check \
  --lineage "$TURN_TLS_BACKUP/tls" --trust /etc/coturn/tls/trust-anchors.pem
python3 /usr/local/libexec/mknoon-coturn-tls-deploy.py deploy \
  --lineage "$TURN_TLS_BACKUP/tls" --trust /etc/coturn/tls/trust-anchors.pem
```

Automatic rollback on reload/probe failure switches back to the exact previous
generation, signals coturn again and exits unsuccessfully. Rollback to an expired
backup is not an acceptable restoration. Only `coturn.service` receives SIGUSR2;
coturn 4.6.1 updates TLS contexts without restarting the process. Existing calls
are expected to retain their allocations; confirm active-call continuity during
the separately approved live exercise. A **restart**, if ever needed, destroys
allocations and requires its own drain/disruption approval. nginx, Go relay,
Redis, DNS and firewalls are not part of this operation. The Android runtime
repair additionally needs signed-device validation and an approved app rollout;
installing this hook alone cannot repair already installed `.09` clients.
