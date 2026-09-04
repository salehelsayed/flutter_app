# TURN credential operations (VC2-01)

Status: repository support is implemented behind `TURN_CREDENTIALS_ENABLED` and
is off by default. No production TURN endpoint, allocation, firewall, DNS, TLS,
certificate, quota, or rotation claim is established by this document. Those
legs remain open until a separately authorized deployment can provide
privacy-safe evidence.

## Runtime custody

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
  retry budget. On failure it stops with a typed error; it must not downgrade to
  a direct route.
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

## Production readiness checklist (currently unproved)

- DNS and certificate ownership are approved and observable without exposing
  credential material.
- UDP/TCP 3478 and TLS/TCP 443 listeners are independently proven where the
  deployment contract requires them.
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
