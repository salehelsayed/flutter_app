#!/usr/bin/env python3

import base64
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import signal
import stat
import subprocess
import tempfile
import time
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
ADAPTER = ROOT / "integration_test/scripts/ios_notification_provider_adapter.py"
RECEIVER = "00008150-001C3C6A3684401C"
RECEIVER_PEER = "12D3KooW" + "a" * 44
SENDER_PEER = "12D3KooW" + "b" * 44
RUN_ID = "ios-provider-run-1"
RUN_NONCE = "nonce-provider-1"
HANDOFF_NONCE = "handoff-nonce-1"
LEAF_CERTIFICATE = b"fixture-development-signing-leaf-der"
LEAF_SHA256 = hashlib.sha256(LEAF_CERTIFICATE).hexdigest()
EMBEDDED_PROFILE = b"fixture signed development mobileprovision"


def _load_adapter():
    spec = importlib.util.spec_from_file_location("ios_provider_adapter", ADAPTER)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load provider adapter")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _write_private(path: Path, value: str | bytes) -> None:
    if isinstance(value, bytes):
        path.write_bytes(value)
    else:
        path.write_text(value, encoding="utf-8")
    path.chmod(stat.S_IRUSR | stat.S_IWUSR)


def _write_executable(path: Path, value: str) -> None:
    path.write_text(value, encoding="utf-8")
    path.chmod(stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR)


def _b64url_decode(value: str) -> dict[str, object]:
    padding = "=" * ((4 - len(value) % 4) % 4)
    return json.loads(base64.urlsafe_b64decode(value + padding))


class _Fixture:
    def __init__(self, root: Path, adapter) -> None:
        self.root = root
        self.adapter = adapter
        self.capture = root / "capture"
        self.capture.mkdir(mode=0o700)
        self.app = root / "Runner.app"
        self.app.mkdir()
        (self.app / "Runner").write_text("prebuilt", encoding="utf-8")
        (self.app / "embedded.mobileprovision").write_bytes(EMBEDDED_PROFILE)

        self.request = {
            "schema": adapter.PROVIDER_REQUEST_SCHEMA,
            "expectedTitle": "Fixture title",
            "expectedBody": "Fixture body",
            "expectedMessageText": "private message text",
            "receiverDeviceId": RECEIVER,
            "peerDeviceId": RECEIVER_PEER,
        }
        self.staging = {
            "schema": adapter.STAGING_SCHEMA,
            "environment": "staging",
            "provider": "apns",
            "providerConfigured": True,
            "providerCredentialsAvailable": True,
            "providerProbeSucceeded": True,
            "appSigningAvailable": True,
            "signingProbeSucceeded": True,
            "apnsEnvironment": "development",
            "signingEntitlementEnvironment": "development",
            "bundleId": adapter.BUNDLE_ID,
            "relayActive": True,
            "relayInboxSeedDriverAvailable": True,
            "dedicatedDisposableReceiver": True,
            "destructiveTestStateResetAuthorized": True,
            "providerCleanupAvailable": True,
            "productionDeploymentPerformed": False,
            "candidateAppRevision": "fixture-app-revision",
            "candidateRelayRevision": "v1.6.0",
            "candidateRelaySha256": "c" * 64,
            "signingIdentitySha256": LEAF_SHA256,
            "signingCertificateSha256": LEAF_SHA256,
            "provisioningProfileSha256": hashlib.sha256(
                EMBEDDED_PROFILE
            ).hexdigest(),
            "signingExpiresAt": "2037-01-01T00:00:00.000Z",
            "receiverDeviceId": RECEIVER,
            "peerDeviceId": RECEIVER_PEER,
            "relayAddresses": ["/dns4/relay.example/tcp/4001"],
        }
        self.payload = {
            "fixture_schema": "mknoon.sims.ios-payload-private-fixture.v1",
            "aps": {
                "alert": {
                    "title": self.request["expectedTitle"],
                    "body": self.request["expectedBody"],
                },
                "mutable-content": 1,
                "content-available": 1,
            },
            "type": "new_message",
            "sender_id": SENDER_PEER,
            "message_id": "message-1",
            "gcm.message_id": "ios-sims-bg-" + "c" * 32,
            "kem": "opaque-kem",
            "ciphertext": "opaque-ciphertext",
            "nonce": "opaque-nonce",
        }
        self.handoff = {
            "schema": adapter.RECEIVER_HANDOFF_SCHEMA,
            "captureNonce": HANDOFF_NONCE,
            "receiverDeviceId": RECEIVER,
            "peerDeviceId": RECEIVER_PEER,
            "bundleId": adapter.BUNDLE_ID,
            "apnsEnvironment": "development",
            "apnsDeviceToken": "a" * 64,
            "mlKemPublicKey": base64.b64encode(b"R" * 1184).decode(),
            "notificationAuthorization": "authorized",
            "notificationAlertSetting": "enabled",
            "notificationBadgeSetting": "enabled",
            "capturedAt": (
                datetime.datetime.now(datetime.timezone.utc)
                .isoformat(timespec="milliseconds")
                .replace("+00:00", "Z")
            ),
        }

        self.request_path = root / "provider-request.json"
        self.staging_path = root / "staging.json"
        self.payload_path = root / "apns-payload.json"
        self.handoff_path = root / "receiver-handoff.json"
        self.relay_key = root / "relay-key"
        self.auth_key = root / "AuthKey_TEST.p8"
        self.relay_actions = root / "relay-actions.log"
        self.relay_mode = root / "relay-mode"
        self.curl_mode = root / "curl-mode"
        self.curl_observation = root / "curl-observation.json"
        self.curl_count = root / "curl-count.txt"
        self.xcrun_actions = root / "xcrun-actions.jsonl"
        self.profile_path = root / "development.mobileprovision"
        self.security_actions = root / "security-actions.jsonl"
        self.sender_actions = root / "sender-actions.log"
        self._persist_inputs()
        _write_private(self.relay_key, "relay-private-key\n")
        self.profile_path.write_bytes(EMBEDDED_PROFILE)
        subprocess.run(
            [
                "openssl",
                "genpkey",
                "-algorithm",
                "EC",
                "-pkeyopt",
                "ec_paramgen_curve:P-256",
                "-out",
                str(self.auth_key),
            ],
            check=True,
            capture_output=True,
        )
        self.auth_key.chmod(0o600)
        self.relay_mode.write_text("normal", encoding="utf-8")
        self.curl_mode.write_text("success", encoding="utf-8")

        self.codesign = root / "fake-codesign.py"
        _write_executable(
            self.codesign,
            """#!/usr/bin/env python3
import pathlib, plistlib, sys
extract=next((value for value in sys.argv if value.startswith('--extract-certificates=')), None)
if extract is not None:
 prefix=extract.split('=', 1)[1]
 pathlib.Path(prefix+'0').write_bytes(""" + repr(LEAF_CERTIFICATE) + """)
 raise SystemExit(0)
if '--extract-certificates' in sys.argv:
 print('certificate prefix must use the codesign option=value form', file=sys.stderr)
 raise SystemExit(64)
value={
 'aps-environment':'development',
 'application-identifier':'397R9Q4WMX.com.mknoon.app',
 'com.apple.developer.team-identifier':'397R9Q4WMX',
}
sys.stdout.buffer.write(plistlib.dumps(value))
""",
        )
        self.security = root / "fake-security.py"
        _write_executable(
            self.security,
            """#!/usr/bin/env python3
import datetime, json, pathlib, plistlib, sys
with open(""" + repr(str(self.security_actions)) + """,'a') as log:
 log.write(json.dumps(sys.argv[1:])+'\\n')
value={
 'TeamIdentifier':['397R9Q4WMX'],
 'Entitlements':{
  'aps-environment':'development',
  'application-identifier':'397R9Q4WMX.com.mknoon.app',
  'com.apple.developer.team-identifier':'397R9Q4WMX',
 },
 'ProvisionedDevices':['""" + RECEIVER + """'],
 'DeveloperCertificates': [""" + repr(LEAF_CERTIFICATE) + """],
 'ExpirationDate':datetime.datetime(2037,1,1),
}
sys.stdout.buffer.write(plistlib.dumps(value))
""",
        )
        self.relay_driver = root / "relay-fixture-driver.py"
        _write_executable(
            self.relay_driver,
            """#!/usr/bin/env python3
import argparse, hashlib, json, pathlib, time
p=argparse.ArgumentParser()
for name in ['action','scenario','receiver','peer-device','provider-request',
             'staging-manifest','relay-target','relay-key','run-id','nonce',
             'apns-payload','apns-payload-sha256','receiver-handoff-sha256',
             'lifecycle','provider-receipt','output']:
    p.add_argument('--'+name)
a=p.parse_args()
lifecycle=json.loads(pathlib.Path(a.lifecycle).read_text())
assert set(lifecycle) == {
 'schema','state','runId','nonce','receiverDeviceIdSha256',
 'peerDeviceIdSha256','requestSha256','stagingManifestSha256',
 'apnsPayloadSha256','receiverHandoffSha256','stagedEnvelopeSha256','recordedAt'}
assert lifecycle['state'] == {
 'setup':'fixture_spawn_pending','cleanup':'cleanup_spawn_pending',
 'rollback':'rollback_spawn_pending'}[a.action]
assert lifecycle['stagingManifestSha256'] == hashlib.sha256(
 pathlib.Path(a.staging_manifest).read_bytes()).hexdigest()
payload=pathlib.Path(a.apns_payload).read_bytes()
assert hashlib.sha256(payload).hexdigest() == a.apns_payload_sha256
open('""" + str(self.relay_actions) + """','a').write(a.action+'\\n')
if pathlib.Path('""" + str(self.relay_mode) + """').read_text().strip() == 'hang' and a.action == 'setup':
    time.sleep(30)
def h(value): return hashlib.sha256(value.encode()).hexdigest()
receipt={
 'schema':'mknoon.sims.ios-payload-relay-fixture-receipt.v1',
 'action':a.action,
 'runId':a.run_id,
 'nonce':a.nonce,
 'receiverDeviceIdSha256':h(a.receiver),
 'peerDeviceIdSha256':h(a.peer_device),
 'requestSha256':hashlib.sha256(open(a.provider_request,'rb').read()).hexdigest(),
 'stagingManifestSha256':lifecycle['stagingManifestSha256'],
 'apnsPayloadSha256':a.apns_payload_sha256,
 'receiverHandoffSha256':a.receiver_handoff_sha256,
 'childBuildCount':0,
 'manualActionCount':0,
}
if a.action == 'setup':
 receipt.update(status='seeded', relayInboxSeeded=True,
                stagedEnvelopeSha256=lifecycle['stagedEnvelopeSha256'])
elif a.action == 'cleanup':
 receipt.update(status='cleared', relayFixtureCleared=True,
                providerReceiptSha256=hashlib.sha256(
                    open(a.provider_receipt,'rb').read()).hexdigest())
else:
 receipt.update(status='cleared', relayFixtureCleared=True,
                stagedEnvelopeSha256=lifecycle['stagedEnvelopeSha256'])
pathlib.Path(a.output).write_text(json.dumps(receipt)+'\\n')
""",
        )
        self.payload_producer = root / "iospayloadproducer"
        _write_executable(
            self.payload_producer,
            """#!/usr/bin/env python3
raise SystemExit('runtime producer invocation belongs to the outer driver')
""",
        )
        self.go = root / "fake-go.py"
        _write_executable(
            self.go,
            """#!/usr/bin/env python3
import sys
assert sys.argv[1:3] == ['version', '-m']
print(sys.argv[3] + ': go1.25.0')
""",
        )
        self.sender_driver = root / "fake-receiver-bootstrap.py"
        _write_executable(
            self.sender_driver,
            """#!/usr/bin/env python3
import hashlib, json, os, pathlib, sys
assert sys.argv[1:] == ['--action', 'cleanup-sender']
payload_path=pathlib.Path(os.environ['SIMS_IOS_NOTIFICATION_APNS_PAYLOAD_PATH'])
payload=payload_path.read_bytes()
sender=json.loads(payload)['sender_id']
def h(value): return hashlib.sha256(value.encode()).hexdigest()
receipt={
 'schema':'mknoon.sims.ios-sender-projection-host-receipt.v1',
 'action':'cleanup-sender','status':'PASS','containsSecrets':False,
 'bundleId':'com.mknoon.app',
 'captureNonceSha256':h(os.environ['SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE']),
 'receiverDeviceIdSha256':h(os.environ['SIMS_IOS_PHYSICAL_DEVICE_ID']),
 'senderPeerIdSha256':h(sender),
 'apnsPayloadSha256':hashlib.sha256(payload).hexdigest(),
 'fixtureDigest':h('fixture-generation'),
 'nativeStatus':'cleaned','resultCode':'idempotent',
 'completedAt':'2037-01-01T00:00:00.000Z'}
output=pathlib.Path(os.environ['SIMS_IOS_NOTIFICATION_SENDER_PROJECTION_RECEIPT_PATH'])
output.write_text(json.dumps(receipt)+'\\n'); output.chmod(0o600)
open(""" + repr(str(self.sender_actions)) + """,'a').write('cleanup-sender\\n')
""",
        )
        self.staging["relayFixtureDriverSha256"] = hashlib.sha256(
            self.relay_driver.read_bytes()
        ).hexdigest()
        self.staging["payloadProducerSha256"] = hashlib.sha256(
            self.payload_producer.read_bytes()
        ).hexdigest()
        self._persist_inputs()
        self.curl = root / "fake-curl.py"
        _write_executable(
            self.curl,
            """#!/usr/bin/env python3
import base64, hashlib, json, pathlib, re, sys
config=pathlib.Path(sys.argv[sys.argv.index('--config')+1]).read_text()
def values(name):
 return re.findall(r'^'+re.escape(name)+r' = "(.*)"$', config, re.M)
def value(name): return values(name)[0]
url=value('url')
headers=values('header')
authorization=[v for v in headers if v.startswith('authorization: bearer ')][0]
jwt=authorization.split()[-1]
parts=jwt.split('.')
assert len(parts) == 3
def decode(part):
 return json.loads(base64.urlsafe_b64decode(part+'='*((4-len(part)%4)%4)))
header=decode(parts[0]); claims=decode(parts[1])
payload_path=value('data-binary')[1:]
payload=pathlib.Path(payload_path).read_bytes()
observation={
 'url':url,
 'headers':headers,
 'jwtHeader':header,
 'jwtClaims':claims,
 'jwtSignatureBytes':len(base64.urlsafe_b64decode(parts[2]+'='*((4-len(parts[2])%4)%4))),
 'payloadSha256':hashlib.sha256(payload).hexdigest(),
 'payloadBytes':len(payload),
}
count_path=pathlib.Path('""" + str(self.curl_count) + """')
count=int(count_path.read_text())+1 if count_path.exists() else 1
count_path.write_text(str(count))
observation['submissionCount']=count
pathlib.Path('""" + str(self.curl_observation) + """').write_text(json.dumps(observation))
mode=pathlib.Path('""" + str(self.curl_mode) + """').read_text().strip()
status, reason = {
 'success':('200',None),
 'missing-unique':('200',None),
 'malformed-unique':('200',None),
 'bad-token':('400','BadDeviceToken'),
 'bad-payload':('400','PayloadEmpty'),
 'service':('503','ServiceUnavailable'),
}[mode]
unique_id='00000000-0000-4000-8000-'+str(count).zfill(12)
unique_header=(
 '' if mode == 'missing-unique'
 else 'apns-unique-id: '+('not a safe id' if mode == 'malformed-unique' else unique_id)+'\\n'
)
pathlib.Path(value('dump-header')).write_text(
 'HTTP/2 '+status+'\\napns-id: provider-id-'+str(count)+'\\n'+unique_header+'\\n')
pathlib.Path(value('output')).write_text(
 '' if reason is None else json.dumps({'reason':reason}))
print(status, end='')
""",
        )
        self.xcrun = root / "fake-xcrun.py"
        _write_executable(
            self.xcrun,
            """#!/usr/bin/env python3
import json, pathlib, sys
with open('""" + str(self.xcrun_actions) + """','a') as log:
 log.write(json.dumps(sys.argv[1:])+'\\n')
for option in ('--json-output','--log-output'):
 if option in sys.argv:
  pathlib.Path(sys.argv[sys.argv.index(option)+1]).write_text(
   json.dumps({'result':'ok'})+'\\n')
""",
        )

    def _persist_inputs(self) -> None:
        _write_private(self.request_path, json.dumps(self.request, separators=(",", ":")))
        _write_private(self.staging_path, json.dumps(self.staging, separators=(",", ":")))
        _write_private(
            self.payload_path,
            json.dumps(self.payload, separators=(",", ":")).encode() + b"\n",
        )
        _write_private(self.handoff_path, json.dumps(self.handoff, separators=(",", ":")))

    @property
    def environment(self) -> dict[str, str]:
        return {
            **os.environ,
            "SIMS_IOS_APNS_AUTH_KEY_PATH": str(self.auth_key),
            "SIMS_IOS_APNS_KEY_ID": "ABCDEFGHIJ",
            "SIMS_IOS_APNS_TEAM_ID": "397R9Q4WMX",
            "SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_PATH": str(self.handoff_path),
            "SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE": HANDOFF_NONCE,
            "SIMS_IOS_NOTIFICATION_APNS_PAYLOAD_PATH": str(self.payload_path),
            "SIMS_IOS_NOTIFICATION_RELAY_FIXTURE_DRIVER": str(self.relay_driver),
            "SIMS_IOS_NOTIFICATION_CODESIGN_EXECUTABLE": str(self.codesign),
            "SIMS_IOS_NOTIFICATION_SECURITY_EXECUTABLE": str(self.security),
            "SIMS_IOS_NOTIFICATION_GO_EXECUTABLE": str(self.go),
            "SIMS_IOS_NOTIFICATION_PAYLOAD_PRODUCER": str(self.payload_producer),
            "SIMS_IOS_NOTIFICATION_RECEIVER_BOOTSTRAP_DRIVER": str(
                self.sender_driver
            ),
            "SIMS_IOS_NOTIFICATION_CURL_EXECUTABLE": str(self.curl),
            "SIMS_IOS_NOTIFICATION_XCRUN_EXECUTABLE": str(self.xcrun),
            "SIMS_IOS_NOTIFICATION_FIXTURE_TIMEOUT_SECONDS": "3",
        }

    def command(
        self,
        action: str,
        output: Path,
        provider_receipt: Path | None = None,
    ) -> list[str]:
        command = [
            "python3",
            str(ADAPTER),
            "--action",
            action,
            "--scenario",
            "payload_fast_path_ios_receiver",
            "--receiver",
            RECEIVER,
            "--peer-device",
            RECEIVER_PEER,
            "--application-binary",
            str(self.app),
            "--provider-request",
            str(self.request_path),
            "--staging-manifest",
            str(self.staging_path),
            "--relay-target",
            "operator@staging-relay",
            "--relay-key",
            str(self.relay_key),
            "--run-id",
            RUN_ID,
            "--nonce",
            RUN_NONCE,
        ]
        if provider_receipt is not None:
            command.extend(["--provider-receipt", str(provider_receipt)])
        command.extend(["--output", str(output)])
        return command

    def probe_command(self, output: Path) -> list[str]:
        return [
            "python3",
            str(ADAPTER),
            "--action",
            "probe",
            "--receiver",
            RECEIVER,
            "--peer-device",
            RECEIVER_PEER,
            "--provisioning-profile",
            str(self.profile_path),
            "--candidate-app-revision",
            "fixture-app-revision",
            "--candidate-relay-revision",
            "v1.6.0",
            "--candidate-relay-sha256",
            "c" * 64,
            "--relay-address",
            "/dns4/relay.example/tcp/4001",
            "--relay-fixture-driver",
            str(self.relay_driver),
            "--payload-producer",
            str(self.payload_producer),
            "--output",
            str(output),
        ]

    def run(
        self,
        action: str,
        output: Path,
        provider_receipt: Path | None = None,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            self.command(action, output, provider_receipt),
            cwd=ROOT,
            env=self.environment,
            text=True,
            capture_output=True,
            timeout=15,
        )


class IosNotificationProviderAdapterTest(unittest.TestCase):
    def test_recovery_removes_private_snapshot_after_prior_owner_failure(
        self,
    ) -> None:
        adapter = _load_adapter()
        with tempfile.TemporaryDirectory(prefix="ios-provider-owner-cleanup-") as raw:
            state_directory = Path(raw)
            snapshot = Path(raw) / "payload.snapshot.json"
            _write_private(snapshot, '{"private":"payload"}\n')
            first_provenance = state_directory / "apns-unique-id-first.private.json"
            retry_provenance = state_directory / "apns-unique-id-retry.private.json"
            _write_private(first_provenance, '{"private":"first"}\n')
            _write_private(retry_provenance, '{"private":"retry"}\n')
            context = mock.Mock(
                state_directory=state_directory,
                payload_snapshot=snapshot,
                initial_lifecycle_state="accepted",
            )

            with (
                mock.patch.object(adapter, "_write_lifecycle"),
                mock.patch.object(
                    adapter,
                    "_run_fixture_driver",
                    side_effect=adapter.AdapterFailure("fixture rollback failed"),
                ),
                mock.patch.object(adapter, "_cleanup_sender_projection"),
                mock.patch.object(adapter, "_remove_candidate_application"),
            ):
                failures = adapter._perform_recovery(context)

            self.assertEqual(failures, ["relay fixture rollback"])
            self.assertFalse(snapshot.exists())
            self.assertFalse(first_provenance.exists())
            self.assertFalse(retry_provenance.exists())

            with (
                mock.patch.object(adapter, "_write_lifecycle"),
                mock.patch.object(
                    adapter,
                    "_run_fixture_driver",
                    side_effect=adapter.AdapterFailure("fixture rollback failed"),
                ),
                mock.patch.object(adapter, "_cleanup_sender_projection"),
                mock.patch.object(adapter, "_remove_candidate_application"),
                mock.patch.object(
                    adapter,
                    "_remove_payload_snapshot",
                    side_effect=adapter.AdapterFailure("snapshot removal failed"),
                ),
            ):
                failures = adapter._perform_recovery(context)

            self.assertEqual(
                failures,
                ["relay fixture rollback", "payload snapshot removal"],
            )

    def test_provenance_cleanup_attempts_both_paths_and_redacts_failures(
        self,
    ) -> None:
        adapter = _load_adapter()
        context = mock.Mock()
        private_value = "private-apns-unique-id-must-not-escape"
        first = mock.Mock()
        first.unlink.side_effect = OSError(private_value)
        first.exists.return_value = True
        retry = mock.Mock()
        retry.exists.return_value = True

        with mock.patch.object(
            adapter,
            "_apns_unique_id_provenance_path",
            side_effect=lambda _context, stage: {
                "first": first,
                "retry": retry,
            }[stage],
        ):
            with self.assertRaises(adapter.AdapterFailure) as raised:
                adapter._remove_apns_unique_id_provenance(context)

        first.unlink.assert_called_once_with(missing_ok=True)
        retry.unlink.assert_called_once_with(missing_ok=True)
        self.assertIn("2 file(s)", str(raised.exception))
        self.assertNotIn(private_value, str(raised.exception))

    def test_local_probe_emits_stable_full_development_manifest_without_live_calls(
        self,
    ) -> None:
        adapter = _load_adapter()
        with tempfile.TemporaryDirectory(prefix="ios-provider-probe-") as raw:
            fixture = _Fixture(Path(raw), adapter)
            output = fixture.capture / "staging-manifest.json"
            first = subprocess.run(
                fixture.probe_command(output),
                cwd=ROOT,
                env=fixture.environment,
                text=True,
                capture_output=True,
            )
            self.assertEqual(first.returncode, 0, first.stderr)
            first_bytes = output.read_bytes()
            manifest = json.loads(first_bytes)
            self.assertEqual(manifest["apnsEnvironment"], "development")
            self.assertEqual(
                manifest["signingEntitlementEnvironment"], "development"
            )
            self.assertEqual(manifest["signingIdentitySha256"], LEAF_SHA256)
            self.assertEqual(manifest["signingCertificateSha256"], LEAF_SHA256)
            self.assertEqual(
                manifest["payloadProducerSha256"],
                hashlib.sha256(fixture.payload_producer.read_bytes()).hexdigest(),
            )
            self.assertEqual(manifest["receiverDeviceId"], RECEIVER)
            self.assertEqual(manifest["peerDeviceId"], RECEIVER_PEER)
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)

            second = subprocess.run(
                fixture.probe_command(output),
                cwd=ROOT,
                env=fixture.environment,
                text=True,
                capture_output=True,
            )
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(output.read_bytes(), first_bytes)
            security_actions = [
                json.loads(line)
                for line in fixture.security_actions.read_text().splitlines()
            ]
            self.assertEqual(
                security_actions,
                [
                    ["cms", "-D", "-i", str(fixture.profile_path)],
                    ["cms", "-D", "-i", str(fixture.profile_path)],
                ],
            )
            self.assertFalse(fixture.relay_actions.exists())
            self.assertFalse(fixture.curl_observation.exists())
            self.assertFalse(fixture.xcrun_actions.exists())

    def test_duplicate_payload_and_plaintext_substrings_fail_closed(self) -> None:
        adapter = _load_adapter()
        request = {
            "expectedTitle": "Fixture title",
            "expectedBody": "Fixture body",
            "expectedMessageText": "private message text",
        }
        duplicate = b'{"aps":{},"aps":{}}'
        with self.assertRaises(adapter.AdapterBlocked):
            adapter.decode_json_object_bytes(duplicate, "payload")

        payload = {
            "fixture_schema": "mknoon.sims.ios-payload-private-fixture.v1",
            "aps": {
                "alert": {
                    "title": request["expectedTitle"],
                    "body": request["expectedBody"],
                },
                "mutable-content": 1,
                "content-available": 1,
            },
            "type": "new_message",
            "sender_id": SENDER_PEER,
            "message_id": "message-1",
            "gcm.message_id": "ios-sims-bg-" + "c" * 32,
            "kem": "opaque-kem",
            "ciphertext": "opaque-ciphertext",
            "nonce": "opaque-nonce",
        }
        raw = json.dumps(payload, separators=(",", ":")).encode()
        self.assertRegex(
            adapter.validate_apns_payload(payload, request, raw),
            r"^[0-9a-f]{64}$",
        )
        for mutation in (
            lambda value: value.pop("fixture_schema"),
            lambda value: value.__setitem__("gcm.message_id", "arbitrary-id"),
            lambda value: value.__setitem__("unexpected", "opaque"),
            lambda value: value["aps"].__setitem__("unexpected", "opaque"),
            lambda value: value["aps"].__setitem__("mutable-content", 1.0),
            lambda value: value["aps"].__setitem__("content-available", 1.0),
        ):
            malformed = json.loads(json.dumps(payload))
            mutation(malformed)
            malformed_raw = json.dumps(malformed, separators=(",", ":")).encode()
            with self.assertRaises(adapter.AdapterBlocked):
                adapter.validate_apns_payload(malformed, request, malformed_raw)
        payload["aps"]["thread-id"] = "prefix PRIVATE message TEXT suffix"
        raw = json.dumps(payload, separators=(",", ":")).encode()
        with self.assertRaises(adapter.AdapterBlocked):
            adapter.validate_apns_payload(payload, request, raw)

        payload["aps"].pop("thread-id")
        payload["route_note"] = "prefix Fixture body suffix"
        raw = json.dumps(payload, separators=(",", ":")).encode()
        with self.assertRaises(adapter.AdapterBlocked):
            adapter.validate_apns_payload(payload, request, raw)

        with self.assertRaises(adapter.AdapterBlocked):
            adapter.validate_apns_payload(payload, request, b"x" * 4097)

    def test_apns_failure_classification_uses_reason_not_status(self) -> None:
        adapter = _load_adapter()
        with self.assertRaises(adapter.AdapterBlocked):
            adapter.raise_for_apns_failure("400", "BadDeviceToken")
        with self.assertRaises(adapter.AdapterBlocked):
            adapter.raise_for_apns_failure("403", "InvalidProviderToken")
        with self.assertRaises(adapter.AdapterFailure):
            adapter.raise_for_apns_failure("400", "PayloadEmpty")
        with self.assertRaises(adapter.AdapterFailure):
            adapter.raise_for_apns_failure("403", None)
        with self.assertRaises(adapter.AdapterFailure):
            adapter.raise_for_apns_failure("503", "ServiceUnavailable")

    def test_process_timeout_terminates_descendant_process_group(self) -> None:
        adapter = _load_adapter()
        with tempfile.TemporaryDirectory(prefix="provider-tree-") as raw:
            root = Path(raw)
            child_pid = root / "child.pid"
            helper = root / "tree.py"
            _write_executable(
                helper,
                """#!/usr/bin/env python3
import pathlib, signal, subprocess, sys, time
child=subprocess.Popen([sys.executable,'-c',
 'import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(30)'])
pathlib.Path(sys.argv[1]).write_text(str(child.pid))
signal.signal(signal.SIGTERM, signal.SIG_IGN)
time.sleep(30)
""",
            )
            with self.assertRaises(adapter.CommandTimedOut):
                adapter.run_process(
                    [str(helper), str(child_pid)],
                    timeout_seconds=1.0,
                    environment=os.environ,
                )
            pid = int(child_pid.read_text())
            deadline = time.time() + 3
            while time.time() < deadline:
                state = subprocess.run(
                    ["ps", "-o", "state=", "-p", str(pid)],
                    text=True,
                    capture_output=True,
                ).stdout.strip()
                if not state or state.startswith("Z"):
                    break
                time.sleep(0.05)
            self.assertTrue(not state or state.startswith("Z"), state)

    def test_development_setup_cleanup_and_public_rollback_are_bound(self) -> None:
        adapter = _load_adapter()
        with tempfile.TemporaryDirectory(prefix="ios-provider-adapter-") as raw:
            fixture = _Fixture(Path(raw), adapter)
            setup_output = fixture.capture / "provider_receipt.json"
            setup = fixture.run("setup", setup_output)
            self.assertEqual(setup.returncode, 0, setup.stderr)
            receipt = json.loads(setup_output.read_text())
            payload_sha = hashlib.sha256(fixture.payload_path.read_bytes()).hexdigest()
            handoff_sha = hashlib.sha256(fixture.handoff_path.read_bytes()).hexdigest()
            first_apns_id = "provider-id-1"
            first_unique_id = "00000000-0000-4000-8000-000000000001"
            self.assertEqual(receipt["apnsPayloadSha256"], payload_sha)
            self.assertEqual(receipt["receiverHandoffSha256"], handoff_sha)
            self.assertEqual(
                receipt["providerMessageIdSha256"],
                hashlib.sha256(first_apns_id.encode()).hexdigest(),
            )
            first_provenance = next(
                fixture.capture.glob(
                    ".ios-provider-state-*/apns-unique-id-first.private.json"
                )
            )
            private_delivery = json.loads(first_provenance.read_text())
            self.assertEqual(
                set(private_delivery),
                {
                    "schema",
                    "submissionStage",
                    "runId",
                    "nonce",
                    "receiverDeviceIdSha256",
                    "apnsPayloadSha256",
                    "receiverHandoffSha256",
                    "apnsIdSha256",
                    "apnsUniqueId",
                    "apnsUniqueIdSha256",
                    "providerMessageIdSha256",
                    "createdAt",
                },
            )
            self.assertEqual(private_delivery["submissionStage"], "first")
            self.assertEqual(private_delivery["apnsUniqueId"], first_unique_id)
            self.assertEqual(
                private_delivery["apnsIdSha256"],
                hashlib.sha256(first_apns_id.encode()).hexdigest(),
            )
            self.assertEqual(
                private_delivery["apnsUniqueIdSha256"],
                hashlib.sha256(first_unique_id.encode()).hexdigest(),
            )
            self.assertEqual(
                private_delivery["providerMessageIdSha256"],
                receipt["providerMessageIdSha256"],
            )
            self.assertEqual(stat.S_IMODE(first_provenance.stat().st_mode), 0o600)
            self.assertNotIn(first_unique_id, setup_output.read_text())

            observation = json.loads(fixture.curl_observation.read_text())
            self.assertEqual(
                observation["url"],
                "https://api.sandbox.push.apple.com/3/device/" + "a" * 64,
            )
            self.assertIn("apns-topic: com.mknoon.app", observation["headers"])
            self.assertIn("apns-push-type: alert", observation["headers"])
            self.assertIn("apns-priority: 10", observation["headers"])
            self.assertEqual(observation["jwtHeader"], {"alg": "ES256", "kid": "ABCDEFGHIJ"})
            self.assertEqual(observation["jwtClaims"]["iss"], "397R9Q4WMX")
            self.assertEqual(observation["jwtSignatureBytes"], 64)
            expiration_header = next(
                header
                for header in observation["headers"]
                if header.startswith("apns-expiration: ")
            )
            expiration = int(expiration_header.split(": ", 1)[1])
            issued_at = observation["jwtClaims"]["iat"]
            self.assertGreaterEqual(expiration, issued_at + 115)
            self.assertLessEqual(expiration, issued_at + 125)
            self.assertEqual(observation["payloadSha256"], payload_sha)
            self.assertEqual(observation["payloadBytes"], fixture.payload_path.stat().st_size)

            cleanup_output = fixture.capture / "provider_cleanup_receipt.json"
            cleanup = fixture.run("cleanup", cleanup_output, setup_output)
            self.assertEqual(cleanup.returncode, 0, cleanup.stderr)
            self.assertEqual(json.loads(cleanup_output.read_text())["status"], "cleaned")
            self.assertFalse(first_provenance.exists())

            first_recovery = fixture.capture / "provider_recovery_1.json"
            second_recovery = fixture.capture / "provider_recovery_2.json"
            self.assertEqual(fixture.run("rollback", first_recovery).returncode, 0)
            self.assertEqual(fixture.run("rollback", second_recovery).returncode, 0)
            self.assertEqual(json.loads(second_recovery.read_text())["status"], "recovered")

            self.assertEqual(
                fixture.relay_actions.read_text().splitlines(),
                ["setup", "cleanup", "rollback", "rollback"],
            )
            uninstall_calls = [
                json.loads(line) for line in fixture.xcrun_actions.read_text().splitlines()
            ]
            self.assertGreaterEqual(len(uninstall_calls), 3)
            for call in uninstall_calls:
                self.assertEqual(call[:4], ["devicectl", "device", "uninstall", "app"])
                self.assertIn("--device", call)
                self.assertEqual(call[call.index("--device") + 1], RECEIVER)
                self.assertIn("com.mknoon.app", call)

            persisted = "\n".join(
                path.read_text(errors="replace")
                for path in fixture.capture.rglob("*")
                if path.is_file()
            )
            self.assertNotIn(fixture.handoff["apnsDeviceToken"], persisted)
            self.assertNotIn(fixture.handoff["mlKemPublicKey"], persisted)
            self.assertNotIn("opaque-ciphertext", persisted)
            self.assertNotIn("private message text", persisted)

    def test_first_and_second_send_receipts_bind_identical_private_retry(self) -> None:
        adapter = _load_adapter()
        with tempfile.TemporaryDirectory(prefix="ios-provider-retry-") as raw:
            fixture = _Fixture(Path(raw), adapter)
            first_path = fixture.capture / "provider_first.json"
            first_result = fixture.run("setup", first_path)
            self.assertEqual(first_result.returncode, 0, first_result.stderr)
            first = json.loads(first_path.read_text())
            first_apns_id = "provider-id-1"
            first_unique_id = "00000000-0000-4000-8000-000000000001"
            first_provenance = next(
                fixture.capture.glob(
                    ".ios-provider-state-*/apns-unique-id-first.private.json"
                )
            )
            self.assertEqual(
                json.loads(first_provenance.read_text())["apnsUniqueId"],
                first_unique_id,
            )
            snapshot = next(
                fixture.capture.glob(".ios-provider-state-*/payload.snapshot.json")
            )
            payload_before = snapshot.read_bytes()

            second_path = fixture.capture / "provider_retry.json"
            second_result = fixture.run("retry", second_path, first_path)
            self.assertEqual(second_result.returncode, 0, second_result.stderr)
            second = json.loads(second_path.read_text())
            second_apns_id = "provider-id-2"
            second_unique_id = "00000000-0000-4000-8000-000000000002"
            retry_provenance = next(
                fixture.capture.glob(
                    ".ios-provider-state-*/apns-unique-id-retry.private.json"
                )
            )
            self.assertEqual(
                json.loads(retry_provenance.read_text())["apnsUniqueId"],
                second_unique_id,
            )
            self.assertEqual(
                second["schema"],
                "mknoon.sims.ios-payload-fast-path-provider-retry-receipt.v1",
            )
            self.assertEqual(second["providerAcceptedCount"], 2)
            self.assertTrue(second["payloadBytesIdentical"])
            self.assertTrue(second["collapseIdentityReused"])
            self.assertTrue(second["providerIdsDistinct"])
            self.assertEqual(
                second["firstProviderMessageIdSha256"],
                first["providerMessageIdSha256"],
            )
            self.assertEqual(
                second["firstProviderMessageIdSha256"],
                hashlib.sha256(first_apns_id.encode()).hexdigest(),
            )
            self.assertEqual(
                second["secondProviderMessageIdSha256"],
                hashlib.sha256(second_apns_id.encode()).hexdigest(),
            )
            self.assertNotEqual(
                second["firstProviderMessageIdSha256"],
                second["secondProviderMessageIdSha256"],
            )
            self.assertEqual(
                second["collapseIdentitySha256"],
                first["collapseIdentitySha256"],
            )
            self.assertEqual(
                second["firstProviderReceiptSha256"],
                hashlib.sha256(first_path.read_bytes()).hexdigest(),
            )
            self.assertEqual(snapshot.read_bytes(), payload_before)
            observation = json.loads(fixture.curl_observation.read_text())
            self.assertEqual(observation["submissionCount"], 2)
            collapse_headers = [
                value
                for value in observation["headers"]
                if value.startswith("apns-collapse-id: ")
            ]
            self.assertEqual(len(collapse_headers), 1)
            collapse_value = collapse_headers[0].split(": ", 1)[1]
            self.assertLessEqual(len(collapse_value.encode()), 64)
            self.assertEqual(
                hashlib.sha256(collapse_value.encode()).hexdigest(),
                second["collapseIdentitySha256"],
            )

            cleanup = fixture.run(
                "cleanup",
                fixture.capture / "cleanup.json",
                first_path,
            )
            self.assertEqual(cleanup.returncode, 0, cleanup.stderr)
            self.assertFalse(first_provenance.exists())
            self.assertFalse(retry_provenance.exists())

    def test_development_apns_unique_id_is_required_and_safe(self) -> None:
        adapter = _load_adapter()
        self.assertEqual(
            adapter._secret_bearing_field(
                {"APNS.Unique-ID": "private-apns-unique-id"}
            ),
            "$.APNS.Unique-ID",
        )
        for mode in ("missing-unique", "malformed-unique"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(
                prefix="ios-provider-unique-id-"
            ) as raw:
                fixture = _Fixture(Path(raw), adapter)
                fixture.curl_mode.write_text(mode)
                result = fixture.run("setup", fixture.capture / "provider.json")
                self.assertEqual(result.returncode, 1)
                self.assertIn("APNs response omitted", result.stderr)
                self.assertEqual(
                    fixture.relay_actions.read_text().splitlines(),
                    ["setup", "rollback"],
                )
                self.assertEqual(
                    list(
                        fixture.capture.glob(
                            ".ios-provider-state-*/apns-unique-id-*.private.json"
                        )
                    ),
                    [],
                )

    def test_apns_and_fixture_timeout_failures_roll_back(self) -> None:
        adapter = _load_adapter()
        with tempfile.TemporaryDirectory(prefix="ios-provider-failure-") as raw:
            fixture = _Fixture(Path(raw), adapter)
            fixture.curl_mode.write_text("bad-payload")
            rejected = fixture.run("setup", fixture.capture / "rejected.json")
            self.assertEqual(rejected.returncode, 1)
            self.assertEqual(
                fixture.relay_actions.read_text().splitlines(),
                ["setup", "rollback"],
            )

            timeout_root = Path(raw) / "timeout-case"
            timeout_root.mkdir()
            timeout_fixture = _Fixture(timeout_root, adapter)
            timeout_fixture.relay_mode.write_text("hang")
            timed_out = timeout_fixture.run(
                "setup",
                timeout_fixture.capture / "timeout.json",
            )
            self.assertEqual(timed_out.returncode, 1)
            self.assertEqual(
                timeout_fixture.relay_actions.read_text().splitlines()[-2:],
                ["setup", "rollback"],
            )

    def test_journaled_recovery_uses_bound_snapshot_and_rejects_run_reuse(
        self,
    ) -> None:
        adapter = _load_adapter()
        with tempfile.TemporaryDirectory(prefix="ios-provider-journal-") as raw:
            fixture = _Fixture(Path(raw), adapter)
            setup_output = fixture.capture / "provider.json"
            setup = fixture.run("setup", setup_output)
            self.assertEqual(setup.returncode, 0, setup.stderr)
            snapshot = next(
                fixture.capture.glob(
                    ".ios-provider-state-*/payload.snapshot.json"
                )
            )
            original_snapshot = snapshot.read_bytes()

            fixture.payload["message_id"] = "different-message"
            fixture.payload["ciphertext"] = "different-opaque-ciphertext"
            fixture._persist_inputs()
            recovery_output = fixture.capture / "recovery.json"
            recovery = fixture.run("rollback", recovery_output)
            self.assertEqual(recovery.returncode, 0, recovery.stderr)
            self.assertEqual(
                json.loads(recovery_output.read_text())["apnsPayloadSha256"],
                hashlib.sha256(original_snapshot).hexdigest(),
            )
            self.assertEqual(
                fixture.relay_actions.read_text().splitlines(),
                ["setup", "rollback"],
            )
            self.assertEqual(
                fixture.sender_actions.read_text().splitlines(),
                ["cleanup-sender"],
            )

            reused = fixture.run("setup", fixture.capture / "reused.json")
            self.assertEqual(reused.returncode, 78)
            self.assertEqual(
                fixture.relay_actions.read_text().splitlines(),
                ["setup", "rollback"],
            )
            self.assertFalse(snapshot.exists())

    def test_handoff_nonce_and_entitlement_mismatch_block_before_relay(self) -> None:
        adapter = _load_adapter()
        with tempfile.TemporaryDirectory(prefix="ios-provider-binding-") as raw:
            fixture = _Fixture(Path(raw), adapter)
            environment = fixture.environment
            environment["SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE"] = "wrong-nonce"
            result = subprocess.run(
                fixture.command("setup", fixture.capture / "bad-handoff.json"),
                cwd=ROOT,
                env=environment,
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 78)
            self.assertFalse(fixture.relay_actions.exists())

            fixture.request["expectedTitle"] = "t" * 31
            fixture._persist_inputs()
            result = fixture.run("setup", fixture.capture / "long-title.json")
            self.assertEqual(result.returncode, 78)
            self.assertIn("expectedTitle is invalid", result.stderr)
            self.assertFalse(fixture.relay_actions.exists())

            fixture.request["expectedTitle"] = "Fixture title"
            fixture.request["expectedMessageText"] = "m" * 141
            fixture._persist_inputs()
            result = fixture.run("setup", fixture.capture / "long-message.json")
            self.assertEqual(result.returncode, 78)
            self.assertIn("expectedMessageText is invalid", result.stderr)
            self.assertFalse(fixture.relay_actions.exists())

            fixture.request["expectedMessageText"] = " leading-space"
            fixture._persist_inputs()
            result = fixture.run("setup", fixture.capture / "spaced-message.json")
            self.assertEqual(result.returncode, 78)
            self.assertIn("expectedMessageText is invalid", result.stderr)
            self.assertFalse(fixture.relay_actions.exists())

            fixture.request["expectedMessageText"] = "Fixture message"
            fixture.handoff["notificationAuthorization"] = "denied"
            fixture._persist_inputs()
            result = fixture.run("setup", fixture.capture / "denied-alerts.json")
            self.assertEqual(result.returncode, 78)
            self.assertIn("authorized alerts", result.stderr)
            self.assertFalse(fixture.relay_actions.exists())

            fixture.handoff["notificationAuthorization"] = "authorized"
            fixture.handoff["notificationBadgeSetting"] = "disabled"
            fixture._persist_inputs()
            result = fixture.run("setup", fixture.capture / "disabled-badges.json")
            self.assertEqual(result.returncode, 78)
            self.assertIn("authorized alerts and badges", result.stderr)
            self.assertFalse(fixture.relay_actions.exists())

            fixture.handoff["notificationBadgeSetting"] = "enabled"
            fixture.staging["signingIdentitySha256"] = "e" * 64
            fixture.staging["signingCertificateSha256"] = "e" * 64
            fixture._persist_inputs()
            result = fixture.run("setup", fixture.capture / "bad-leaf.json")
            self.assertEqual(result.returncode, 78)
            self.assertFalse(fixture.relay_actions.exists())

            fixture.staging["signingIdentitySha256"] = LEAF_SHA256
            fixture.staging["signingCertificateSha256"] = LEAF_SHA256
            fixture._persist_inputs()
            _write_executable(
                fixture.codesign,
                """#!/usr/bin/env python3
import plistlib, sys
sys.stdout.buffer.write(plistlib.dumps({
 'aps-environment':'production',
 'application-identifier':'397R9Q4WMX.com.mknoon.app',
 'com.apple.developer.team-identifier':'397R9Q4WMX'}))
""",
            )
            result = fixture.run("setup", fixture.capture / "bad-signing.json")
            self.assertEqual(result.returncode, 78)
            self.assertFalse(fixture.relay_actions.exists())


if __name__ == "__main__":
    unittest.main()
