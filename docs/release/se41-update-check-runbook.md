# SE-41 update check runbook

How to sign, publish and roll back the version file, and how to look after the
host that serves it.

## Facts

| Item | Value |
| --- | --- |
| URL (fixed in every shipped build) | `https://updates.mknoon.xyz/mknoon/version.json` |
| App constants | `lib/features/update_check/domain/update_check_keys.dart` |
| Signing CLI | `tool/sign_version_file.dart` |
| Server | EC2 `i-05a8b6160bf5a6495`, t3.micro, eu-north-1, security group `launch-wizard-5` |
| OS | Amazon Linux 2023. `dnf-automatic` installs security updates. |
| Public IP | `51.20.131.205` (Elastic IP) |
| DNS | GoDaddy, A record `updates` → `51.20.131.205` |
| SSH | user `ec2-user` (not `ubuntu`), key `se.pem` (RSA; with paramiko, load it with `RSAKey`) |
| Web server | Caddy 2.11.7 at `/usr/local/bin/caddy`, systemd unit `caddy`, config `/etc/caddy/Caddyfile` |
| File on disk | `/srv/updates/mknoon/version.json` (`/srv/updates` is owned by `ec2-user`) |

Caddy serves only `GET` and `HEAD` on `/mknoon/version.json`. Every other path
returns 404. Responses carry `Cache-Control: max-age=300`. There is no
compression and no redirect. There is no access log, on purpose (see
[Privacy](#9-privacy)).

TLS uses a Let's Encrypt certificate. Caddy gets and renews it over port 443
(TLS-ALPN challenge). Port 80 stays closed.

## 1. Signing (offline, on the owner's Mac only)

The private keys (`signing_key.b64` for k1 and k2) never go into the repo, onto
the server, or into any agent session. Sign on the owner's Mac only.

1. Write `payload.json`. All fields are required. Both platform sections are
   required.

   ```json
   {
     "schemaVersion": 1,
     "sequence": 1,
     "issuedAt": 1760000000,
     "ios":     { "latestBuild": 120, "minBuild": 0, "reasonCode": "general" },
     "android": { "latestBuild": 120, "minBuild": 0, "reasonCode": "general" }
   }
   ```

   - `sequence`: a whole number. See [Sequence rules](#3-sequence-rules).
   - `issuedAt`: Unix time in seconds (`date +%s`).
   - `latestBuild`, `minBuild`: store build numbers. `minBuild` must not be
     above `latestBuild`.
     - A build below `latestBuild` sees the soft banner.
     - A build below `minBuild` sees the blocking update screen.
   - `reasonCode`: `general`, `security`, `protocol_change` or `critical_fix`.

2. Sign it with k1:

   ```sh
   dart run tool/sign_version_file.dart sign \
     --key <k1 dir>/signing_key.b64 --key-id k1 \
     --in payload.json --out version.json
   ```

   `sign` checks the payload with the app's own rules before it signs.

3. Verify the result with the k1 public key (the value of
   `updateCheckK1PublicKeyBase64`):

   ```sh
   dart run tool/sign_version_file.dart verify \
     --pub <k1 public key> --in version.json
   ```

   Do not publish a file that fails `verify`.

## 2. Publishing

1. Upload to a temporary name next to the live file:

   ```sh
   scp -i se.pem version.json \
     ec2-user@51.20.131.205:/srv/updates/mknoon/version.json.tmp
   ```

2. Move it into place. `mv` within one directory is atomic, so a phone never
   reads a half-written file:

   ```sh
   ssh -i se.pem ec2-user@51.20.131.205 \
     'mv /srv/updates/mknoon/version.json.tmp /srv/updates/mknoon/version.json'
   ```

3. Check that the live file is byte-identical to the signed file:

   ```sh
   curl -sS -o live.json https://updates.mknoon.xyz/mknoon/version.json
   cmp live.json version.json && echo identical
   ```

4. Run the CLI verify against the downloaded copy:

   ```sh
   dart run tool/sign_version_file.dart verify --pub <k1 public key> --in live.json
   ```

Phones may keep the old file for up to 300 seconds (`max-age=300`).

## 3. Sequence rules

- Every new file has a higher `sequence` than the last file published.
- Never reuse a `sequence`. Never lower it within a key.
- The app keeps the last verified file and ignores any file with a lower
  sequence. A reused or lower number is ignored on phones that already have
  the newer file.
- A higher-rank key starts its own sequence: the first k2 file is accepted
  whatever its number (`decideVersionFileRatchet`,
  `lib/features/update_check/domain/version_file_verifier.dart:297-303`).
  The rules above then apply within k2.

## 4. The first file

- `latestBuild` = the first store build that contains SE-41.
- `minBuild` = `0`.
- `reasonCode` = `general`.

This file nudges nobody and blocks nobody. It only proves the full path works.

## 5. Rollback

To undo a `minBuild` raise, publish a new file with a LOWER `minBuild` and a
HIGHER `sequence`.

Never roll back by deleting the file. A 404 does not clear anything: each
phone keeps its last verified file, so a blocked build stays blocked.

## 6. When to raise minBuild (O8)

Raise `minBuild` only when all three are true:

1. The phased release has reached 100% (7 days on iOS).
2. The build is live in every store country.
3. The oldest supported iOS and Android versions can install it.

Otherwise some users are blocked with no build they can install.

## 7. Key compromise or planned rotation

The app has two built-in public keys: k1 (rank 1) and backup k2 (rank 2).

If k1 is compromised, or for a planned rotation:

1. Sign the next file with k2 (`--key-id k2`, verify with the k2 public key).
2. Publish it as usual. One accepted k2 file permanently retires k1 on every
   installed app. After that, those apps reject every k1 file.
3. Put a NEW backup key k3 into the next app release.

If k2 is also stolen, only an app update can recover. No version file can fix
it.

## 8. Release guard

Store builds fail if `MKNOON_UPDATE_CHECK=off` is set.
`scripts/check_update_check_release_defines.py` checks this and runs inside
`scripts/build_ios_appstore_ipa.sh`, `docker-ws/build_store_release.sh` and
`docker-ws/build_play_aab.sh`.

An archive made by hand in Xcode does not run these scripts, so it bypasses
the guard.

## 9. Privacy

The host sees the IP address and the time of every check. That is why Caddy
has no access log.

Never turn on access logging on this host.

## 10. Server checks

- Certificate expiry:

  ```sh
  echo | openssl s_client -connect updates.mknoon.xyz:443 \
    -servername updates.mknoon.xyz | openssl x509 -noout -enddate
  ```

- Service state:

  ```sh
  systemctl status caddy
  ```

- The Elastic IP must stay attached to the instance. If the IP ever changes,
  update the GoDaddy A record `updates`.
- An expired certificate makes every check fail silently. The app then keeps
  its last file, so the ability to block an old build is lost until the
  certificate is fixed.

## 11. Check-now push (T4b)

Asks every installed app to run its signed update check now. The push only
says "check": the app still trusts nothing but the signed version file, and
it never shows text from the relay.

### When

- Send the silent push first, after publishing a new `version.json`
  (section 2). Most phones check within minutes; iOS decides when.
- Use `--ios-alert` only for a security or hard (`minBuild`) release, and
  only after a silent push. It shows a fixed sentence that is built into the
  app (EN, DE, AR): "Is Mknoon up to date? Older versions can lose their
  connection. Tap to open Mknoon and check." Tapping only opens the app.

### Command (on the relay host, over SSH)

```
sudo bash -c 'set -a; . /etc/mknoon/relay-server.env; set +a; \
  /usr/local/bin/relay-server update-check-push'              # silent
sudo bash -c 'set -a; . /etc/mknoon/relay-server.env; set +a; \
  /usr/local/bin/relay-server update-check-push --ios-alert'  # alert
```

It needs `RELAY_BACKEND=redis`, `REDIS_URL` and `FIREBASE_SERVICE_ACCOUNT`
from the service env. Success prints
`update-check-push: sent topic=update_check mode=<silent|ios-alert> message=<id>`.
Exit code 2 with a reason otherwise.

### What it sends (one FCM topic send to `update_check`)

- Data payload, exactly: `{"type":"update_check"}`. No notification block.
- Android: high-priority data message. It shows no notification. FCM may
  lower the priority of apps that send many high-priority messages that show
  nothing; at most 1 per 6 h is fine, so do not raise the limit.
- iOS silent (default): `aps.content-available: 1`, headers
  `apns-priority: 5`, `apns-push-type: background`.
- iOS `--ios-alert`: also `aps.alert` with ONLY
  `title-loc-key: UPDATE_CHECK_ALERT_TITLE` and
  `loc-key: UPDATE_CHECK_ALERT_BODY` (no title or body text, no loc-args, no
  URL), `content-available: 1`, `apns-push-type: alert`,
  `apns-priority: 10`, no `mutable-content`. Never VoIP/PushKit.

### Limits (Redis, kept across restarts)

- One send per 6 h in any mode (`<prefix>se41:update_check_push:any`).
- Alert mode at most once per 24 h (`<prefix>se41:update_check_push:alert`);
  an alert also counts toward the 6 h limit.
- A refused send prints `rate limited: limit_6h` or `limit_24h_alert`.
- A send that FCM clearly rejects (invalid argument, APNs/third-party auth
  error, sender ID mismatch) gives its slot back, so it can be retried at
  once after the fix.
- Any other failure (a timeout, a network error, an FCM server error) keeps
  the slot, because FCM may already have accepted the message: a retried
  `--ios-alert` must not alert twice in a day. The command then prints the
  Redis keys it reserved and the `redis-cli ... DEL` command that clears
  them. Run that only if you are sure nothing was delivered.
- The app also limits itself to one push-triggered check per hour.

### What the app does

- It joins the FCM topic `update_check` while the kill switch is on and
  leaves it when the switch is off. Only builds with T4b join, so older
  builds never get the push.
- Android: `MknoonFirebaseMessagingService` matches only the exact data
  `{"type":"update_check"}` with no notification block. It then queues the
  T4a worker once (unique work `mknoon-se41-update-check-push`, KEEP, needs a
  network) and shows nothing. Any other shape goes on to the normal push
  handling unchanged.
- iOS: `didReceiveRemoteNotification` sends the exact payload to the same
  Dart check as the background task and calls the completion handler
  exactly once within 25 s. An `--ios-alert` push also shows the fixed
  sentence from `Localizable.strings` (EN, DE, AR). Tapping it only opens
  the app.
- A push-started check always downloads the file: it skips the app's
  6 h gate (the 1 h app limit and the relay's 6 h limit bound the traffic).
- The app ignores the push while its kill switch is off, even if it is
  still in the topic.
- In both cases a notice appears only if the signed file says so (T2/T4a).
- To check on a device: iOS logs `[SE41_UPDATE_CHECK] push started` and
  `push completed outcome=<outcome>` (public os_log). Android runs the
  worker with reason `android_push`.

### Deploy (needs owner approval; not done yet)

The subcommand ships in the relay binary. Deploying it follows the normal
relay deploy: bump `const version` in `main.go` first, build on the container
toolchain (`CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath`, check
`go version <binary>`), upload, verify the sha on the box, `sudo install`,
restart, check the journal and metrics, and update
`docker-ws/group-reaction-staging-manifest-315.json`. Probe the deployed
binary with `grep -a -c UPDATE_CHECK_ALERT_TITLE /usr/local/bin/relay-server`
(1 or more). Try it on the Hetzner test relay first if possible. The running
relay process does not change; only the CLI is new.

### Accepted limitation

Someone who takes over the relay host (or the Firebase/APNs credentials) can
send the fixed sentence and ignore the limits. That is spam, not phishing:
the text and the store link are built into the app. The fix is rotating the
Firebase and APNs credentials.
