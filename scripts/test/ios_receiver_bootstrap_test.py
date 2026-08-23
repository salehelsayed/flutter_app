from __future__ import annotations

import base64
import datetime
import json
import hashlib
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[2]
DRIVER = ROOT / "integration_test" / "scripts" / "ios_receiver_bootstrap.py"


class IosReceiverBootstrapTest(unittest.TestCase):
    def test_private_handoff_is_nonce_bound_redacted_and_cleaned(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            fake = self._fake_xcrun(root)
            output = root / "private" / "receiver-handoff.json"
            token = "ab" * 32
            peer = "12D3KooW" + "1" * 44
            ml_kem = base64.b64encode(b"A" * 1184).decode()
            environment = {
                **os.environ,
                "SIMS_IOS_RECEIVER_BOOTSTRAP_XCRUN": str(fake),
                "FAKE_DEVICECTL_STATE": str(root / "state.json"),
                "FAKE_APNS_TOKEN": token,
                "FAKE_PEER_ID": peer,
                "FAKE_ML_KEM_PUBLIC": ml_kem,
                "SIMS_IOS_PHYSICAL_DEVICE_ID": "00008110-001A123E0E91801E",
                "SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE":
                    "nonce-bootstrap-contract-1",
                "SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_PATH": str(output),
            }
            result = subprocess.run(
                [sys.executable, str(DRIVER), "--timeout-seconds", "5"],
                cwd=ROOT,
                env=environment,
                capture_output=True,
                text=True,
                timeout=15,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn(token, result.stdout + result.stderr)
            self.assertNotIn(ml_kem, result.stdout + result.stderr)
            self.assertTrue(output.is_file())
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)
            handoff = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(
                set(handoff),
                {
                    "schema",
                    "captureNonce",
                    "receiverDeviceId",
                    "peerDeviceId",
                    "bundleId",
                    "apnsEnvironment",
                    "apnsDeviceToken",
                    "mlKemPublicKey",
                    "notificationAuthorization",
                    "notificationAlertSetting",
                    "notificationBadgeSetting",
                    "capturedAt",
                },
            )
            self.assertEqual(
                handoff["schema"],
                "mknoon.sims.ios-provider-receiver-handoff.v2",
            )
            self.assertEqual(handoff["apnsDeviceToken"], token)
            self.assertEqual(handoff["peerDeviceId"], peer)
            self.assertEqual(handoff["notificationAuthorization"], "authorized")
            self.assertEqual(handoff["notificationAlertSetting"], "enabled")
            self.assertEqual(handoff["notificationBadgeSetting"], "enabled")

            state = json.loads((root / "state.json").read_text(encoding="utf-8"))
            self.assertEqual(state["lastAction"], "cleanup")
            self.assertTrue(
                state["commands"][0].startswith("devicectl device copy to "),
                state["commands"],
            )
            self.assertTrue(
                state["commands"][1].startswith("devicectl device process launch "),
                state["commands"],
            )
            joined = " ".join(state["commands"])
            self.assertNotIn(" install ", f" {joined} ")
            self.assertNotIn("uninstall", joined)

    def test_nonce_mismatch_fails_without_persisting_token(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            fake = self._fake_xcrun(root)
            output = root / "receiver-handoff.json"
            token = "cd" * 32
            environment = {
                **os.environ,
                "SIMS_IOS_RECEIVER_BOOTSTRAP_XCRUN": str(fake),
                "FAKE_DEVICECTL_STATE": str(root / "state.json"),
                "FAKE_APNS_TOKEN": token,
                "FAKE_PEER_ID": "12D3KooW" + "2" * 44,
                "FAKE_ML_KEM_PUBLIC": base64.b64encode(b"B" * 1184).decode(),
                "FAKE_NONCE_OVERRIDE": "nonce-bootstrap-wrong-2",
                "SIMS_IOS_PHYSICAL_DEVICE_ID": "00008110-001A123E0E91801E",
                "SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE":
                    "nonce-bootstrap-contract-2",
                "SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_PATH": str(output),
            }
            result = subprocess.run(
                [sys.executable, str(DRIVER), "--timeout-seconds", "5"],
                cwd=ROOT,
                env=environment,
                capture_output=True,
                text=True,
                timeout=15,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertFalse(output.exists())
            self.assertNotIn(token, result.stdout + result.stderr)
            self.assertIn('"containsSecrets":false', result.stdout)

    def test_probe_sources_do_not_log_full_fcm_tokens(self) -> None:
        app_delegate = (ROOT / "ios" / "Runner" / "AppDelegate.swift").read_text()
        probe_app = (ROOT / "integration_test" / "apns_provider_probe_app.dart").read_text()
        probe_harness = (
            ROOT / "integration_test" / "apns_provider_probe_harness.dart"
        ).read_text()
        self.assertNotIn("token=%@", app_delegate)
        self.assertNotIn("'token': fcmToken", probe_app)
        self.assertNotIn("'token': fcmToken", probe_harness)

    def test_unsafe_notification_settings_reject_private_handoff(self) -> None:
        for authorization, alert_setting, badge_setting in (
            ("denied", "enabled", "enabled"),
            ("authorized", "disabled", "enabled"),
            ("authorized", "enabled", "disabled"),
        ):
            with self.subTest(
                authorization=authorization,
                alert_setting=alert_setting,
                badge_setting=badge_setting,
            ), tempfile.TemporaryDirectory() as raw:
                root = Path(raw)
                fake = self._fake_xcrun(root)
                output = root / "receiver-handoff.json"
                environment = {
                    **os.environ,
                    "SIMS_IOS_RECEIVER_BOOTSTRAP_XCRUN": str(fake),
                    "FAKE_DEVICECTL_STATE": str(root / "state.json"),
                    "FAKE_APNS_TOKEN": "ef" * 32,
                    "FAKE_PEER_ID": "12D3KooW" + "4" * 44,
                    "FAKE_ML_KEM_PUBLIC": base64.b64encode(
                        b"C" * 1184
                    ).decode(),
                    "FAKE_NOTIFICATION_AUTHORIZATION": authorization,
                    "FAKE_NOTIFICATION_ALERT_SETTING": alert_setting,
                    "FAKE_NOTIFICATION_BADGE_SETTING": badge_setting,
                    "SIMS_IOS_PHYSICAL_DEVICE_ID": "00008110-001A123E0E91801E",
                    "SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE":
                        "nonce-bootstrap-settings-1",
                    "SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_PATH": str(output),
                }
                result = subprocess.run(
                    [sys.executable, str(DRIVER), "--timeout-seconds", "5"],
                    cwd=ROOT,
                    env=environment,
                    capture_output=True,
                    text=True,
                    timeout=15,
                    check=False,
                )
                self.assertEqual(result.returncode, 1)
                self.assertFalse(output.exists())
                self.assertIn('"containsSecrets":false', result.stdout)

    def test_sender_seed_and_cleanup_use_only_private_payload_and_hashed_receipt(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            fake = self._fake_xcrun(root)
            sender = "12D3KooW" + "3" * 44
            payload = {
                "fixture_schema": "mknoon.sims.ios-payload-private-fixture.v1",
                "aps": {
                    "alert": {"title": "Encrypted title", "body": "Encrypted body"},
                    "mutable-content": 1,
                },
                "type": "new_message",
                "sender_id": sender,
                "message_id": "message-private-1",
                "kem": "opaque-kem",
                "ciphertext": "opaque-ciphertext",
                "nonce": "opaque-nonce",
            }
            payload_path = root / "payload.json"
            payload_path.write_text(
                json.dumps(payload, separators=(",", ":"), sort_keys=True) + "\n",
                encoding="utf-8",
            )
            payload_path.chmod(0o600)
            receipt = root / "sender-receipt.json"
            nonce = "nonce-bootstrap-sender-contract-1"
            receiver = "00008110-001A123E0E91801E"
            environment = {
                **os.environ,
                "SIMS_IOS_RECEIVER_BOOTSTRAP_XCRUN": str(fake),
                "FAKE_DEVICECTL_STATE": str(root / "state.json"),
                "SIMS_IOS_PHYSICAL_DEVICE_ID": receiver,
                "SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE": nonce,
                "SIMS_IOS_NOTIFICATION_APNS_PAYLOAD_PATH": str(payload_path),
                "SIMS_IOS_NOTIFICATION_SENDER_PROJECTION_RECEIPT_PATH": str(receipt),
            }

            for action, native_status in (
                ("seed-sender", "seeded"),
                ("cleanup-sender", "cleaned"),
            ):
                result = subprocess.run(
                    [
                        sys.executable,
                        str(DRIVER),
                        "--action",
                        action,
                        "--timeout-seconds",
                        "5",
                    ],
                    cwd=ROOT,
                    env=environment,
                    capture_output=True,
                    text=True,
                    timeout=15,
                    check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn(sender, result.stdout + result.stderr)
                self.assertTrue(receipt.is_file())
                self.assertEqual(stat.S_IMODE(receipt.stat().st_mode), 0o600)
                value = json.loads(receipt.read_text(encoding="utf-8"))
                self.assertEqual(
                    set(value),
                    {
                        "schema",
                        "action",
                        "status",
                        "containsSecrets",
                        "bundleId",
                        "captureNonceSha256",
                        "receiverDeviceIdSha256",
                        "senderPeerIdSha256",
                        "apnsPayloadSha256",
                        "fixtureDigest",
                        "nativeStatus",
                        "resultCode",
                        "completedAt",
                    },
                )
                self.assertEqual(value["action"], action)
                self.assertEqual(value["nativeStatus"], native_status)
                self.assertEqual(
                    value["senderPeerIdSha256"], hashlib.sha256(sender.encode()).hexdigest()
                )
                self.assertEqual(
                    value["apnsPayloadSha256"],
                    hashlib.sha256(payload_path.read_bytes()).hexdigest(),
                )

            state = json.loads((root / "state.json").read_text(encoding="utf-8"))
            joined = " ".join(state["commands"])
            self.assertNotIn(sender, joined)
            self.assertEqual(state["lastAction"], "cleanup")

            payload["aps"]["alert"]["title"] = "x" * 31
            payload_path.write_text(
                json.dumps(payload, separators=(",", ":"), sort_keys=True) + "\n",
                encoding="utf-8",
            )
            payload_path.chmod(0o600)
            over_bound = subprocess.run(
                [sys.executable, str(DRIVER), "--action", "seed-sender"],
                cwd=ROOT,
                env=environment,
                capture_output=True,
                text=True,
                timeout=15,
                check=False,
            )
            self.assertEqual(over_bound.returncode, 78)
            self.assertFalse(receipt.exists())

    def test_notification_recovery_is_exact_bound_redacted_and_cleaned(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            fake = self._fake_xcrun(root)
            receiver = "00008110-001A123E0E91801E"
            nonce = "nonce-bootstrap-recovery-contract-1"
            peer = "12D3KooW" + "5" * 44
            sender = "12D3KooW" + "6" * 44
            payload = {
                "fixture_schema": "mknoon.sims.ios-payload-private-fixture.v1",
                "aps": {
                    "alert": {"title": "Encrypted title", "body": "Encrypted body"},
                    "mutable-content": 1,
                },
                "type": "new_message",
                "sender_id": sender,
                "message_id": "message-private-recovery-1",
                "kem": "opaque-kem",
                "ciphertext": "opaque-ciphertext",
                "nonce": "opaque-nonce",
            }
            payload_path = root / "payload.json"
            payload_path.write_text(
                json.dumps(payload, separators=(",", ":"), sort_keys=True) + "\n",
                encoding="utf-8",
            )
            payload_path.chmod(0o600)
            now = datetime.datetime.now(datetime.timezone.utc).isoformat(
                timespec="milliseconds"
            ).replace("+00:00", "Z")
            handoff = root / "handoff.json"
            handoff.write_text(
                json.dumps(
                    {
                        "schema": "mknoon.sims.ios-provider-receiver-handoff.v2",
                        "captureNonce": nonce,
                        "receiverDeviceId": receiver,
                        "peerDeviceId": peer,
                        "bundleId": "com.mknoon.app",
                        "apnsEnvironment": "development",
                        "apnsDeviceToken": "ab" * 32,
                        "mlKemPublicKey": base64.b64encode(b"D" * 1184).decode(),
                        "notificationAuthorization": "authorized",
                        "notificationAlertSetting": "enabled",
                        "notificationBadgeSetting": "enabled",
                        "capturedAt": now,
                    },
                    separators=(",", ":"),
                    sort_keys=True,
                )
                + "\n",
                encoding="utf-8",
            )
            handoff.chmod(0o600)
            receipt = root / "recovery-receipt.json"
            environment = {
                **os.environ,
                "SIMS_IOS_RECEIVER_BOOTSTRAP_XCRUN": str(fake),
                "FAKE_DEVICECTL_STATE": str(root / "state.json"),
                "SIMS_IOS_PHYSICAL_DEVICE_ID": receiver,
                "SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE": nonce,
                "SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_PATH": str(handoff),
                "SIMS_IOS_NOTIFICATION_APNS_PAYLOAD_PATH": str(payload_path),
                "SIMS_IOS_NOTIFICATION_RECOVERY_RECEIPT_PATH": str(receipt),
            }
            result = subprocess.run(
                [
                    sys.executable,
                    str(DRIVER),
                    "--action",
                    "prove-recovery",
                    "--timeout-seconds",
                    "5",
                ],
                cwd=ROOT,
                env=environment,
                capture_output=True,
                text=True,
                timeout=15,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(receipt.is_file())
            self.assertEqual(stat.S_IMODE(receipt.stat().st_mode), 0o600)
            value = json.loads(receipt.read_text(encoding="utf-8"))
            self.assertEqual(
                value,
                {
                    "schema": "mknoon.sims.ios-notification-recovery-host-receipt.v1",
                    "action": "prove-recovery",
                    "status": "PASS",
                    "containsSecrets": False,
                    "bundleId": "com.mknoon.app",
                    "captureNonceSha256": hashlib.sha256(nonce.encode()).hexdigest(),
                    "receiverDeviceIdSha256": hashlib.sha256(
                        receiver.encode()
                    ).hexdigest(),
                    "apnsPayloadSha256": hashlib.sha256(
                        payload_path.read_bytes()
                    ).hexdigest(),
                    "badgeBefore": 1,
                    "badgeAfter": 0,
                    "deliveredBefore": 1,
                    "deliveredWithSentinel": 2,
                    "deliveredAfter": 1,
                    "deliveredNotificationBadgeWasNil": True,
                    "sentinelSurvived": True,
                    "removedExactOwnedNotification": True,
                    "childBuildCount": 0,
                    "manualActionCount": 0,
                    "resultCode": "ok",
                    "completedAt": value["completedAt"],
                },
            )
            self.assertNotIn(peer, result.stdout + result.stderr)
            self.assertNotIn(sender, result.stdout + result.stderr)
            state = json.loads((root / "state.json").read_text(encoding="utf-8"))
            self.assertEqual(state["lastAction"], "cleanup")
            self.assertIn("stage-recovery-command", " ".join(state["commands"]))

    def test_group_observation_is_exact_source_bound_redacted_and_cleaned(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            fake = self._fake_xcrun(root)
            receiver = "00008110-001A123E0E91801E"
            nonce = "nonce-bootstrap-group-observation-1"
            group_sha = hashlib.sha256(b"raw-group-id").hexdigest()
            event_sha = hashlib.sha256(b"raw-reaction-id").hexdigest()
            target_sha = hashlib.sha256(b"raw-target-message-id").hexdigest()
            receipt = root / "group-observation-receipt.json"
            environment = {
                **os.environ,
                "SIMS_IOS_RECEIVER_BOOTSTRAP_XCRUN": str(fake),
                "FAKE_DEVICECTL_STATE": str(root / "state.json"),
                "SIMS_IOS_PHYSICAL_DEVICE_ID": receiver,
                "SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE": nonce,
                "SIMS_IOS_GROUP_NOTIFICATION_OBSERVATION_RECEIPT_PATH": str(
                    receipt
                ),
            }
            result = subprocess.run(
                [
                    sys.executable,
                    str(DRIVER),
                    "--action",
                    "observe-group",
                    "--phase",
                    "reaction",
                    "--expected-group-id-sha256",
                    group_sha,
                    "--expected-event-id-sha256",
                    event_sha,
                    "--expected-target-message-id-sha256",
                    target_sha,
                    "--timeout-seconds",
                    "10",
                ],
                cwd=ROOT,
                env=environment,
                capture_output=True,
                text=True,
                timeout=20,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(receipt.is_file())
            self.assertEqual(stat.S_IMODE(receipt.stat().st_mode), 0o600)
            value = json.loads(receipt.read_text(encoding="utf-8"))
            self.assertEqual(
                set(value),
                {
                    "schema",
                    "action",
                    "phase",
                    "status",
                    "containsSecrets",
                    "bundleId",
                    "captureNonceSha256",
                    "receiverDeviceIdSha256",
                    "expectedGroupIdSha256",
                    "expectedEventIdSha256",
                    "expectedTargetMessageIdSha256",
                    "matchingRemoteCount",
                    "matchingLocalCount",
                    "matchingUsefulProviderCount",
                    "matchingSanitizedProviderCount",
                    "matchingFlutterLocalCount",
                    "matchingUnknownCount",
                    "matchingTotalCount",
                    "stableSampleCount",
                    "stableSampleIntervalMilliseconds",
                    "observationDeadlineMilliseconds",
                    "sampledThroughDeadline",
                    "badSourceSeen",
                    "duplicateSeen",
                    "requestIdentifierSha256",
                    "childBuildCount",
                    "manualActionCount",
                    "runnerTerminated",
                    "preTapCleanupLaunchCount",
                    "resultCode",
                    "completedAt",
                },
            )
            self.assertEqual(
                {
                    key: value[key]
                    for key in (
                        "schema",
                        "action",
                        "phase",
                        "status",
                        "containsSecrets",
                        "expectedGroupIdSha256",
                        "expectedEventIdSha256",
                        "expectedTargetMessageIdSha256",
                        "matchingRemoteCount",
                        "matchingLocalCount",
                        "matchingUsefulProviderCount",
                        "matchingSanitizedProviderCount",
                        "matchingFlutterLocalCount",
                        "matchingUnknownCount",
                        "matchingTotalCount",
                        "stableSampleCount",
                        "stableSampleIntervalMilliseconds",
                        "observationDeadlineMilliseconds",
                        "sampledThroughDeadline",
                        "badSourceSeen",
                        "duplicateSeen",
                        "runnerTerminated",
                        "preTapCleanupLaunchCount",
                        "resultCode",
                    )
                },
                {
                    "schema": (
                        "mknoon.sims.ios-group-notification-observation-"
                        "host-receipt.v1"
                    ),
                    "action": "observe-group",
                    "phase": "reaction",
                    "status": "PASS",
                    "containsSecrets": False,
                    "expectedGroupIdSha256": group_sha,
                    "expectedEventIdSha256": event_sha,
                    "expectedTargetMessageIdSha256": target_sha,
                    "matchingRemoteCount": 1,
                    "matchingLocalCount": 0,
                    "matchingUsefulProviderCount": 1,
                    "matchingSanitizedProviderCount": 0,
                    "matchingFlutterLocalCount": 0,
                    "matchingUnknownCount": 0,
                    "matchingTotalCount": 1,
                    "stableSampleCount": 3,
                    "stableSampleIntervalMilliseconds": 500,
                    "observationDeadlineMilliseconds": 8000,
                    "sampledThroughDeadline": True,
                    "badSourceSeen": False,
                    "duplicateSeen": False,
                    "runnerTerminated": True,
                    "preTapCleanupLaunchCount": 0,
                    "resultCode": "ok",
                },
            )
            encoded = receipt.read_text(encoding="utf-8") + result.stdout
            self.assertNotIn("raw-group-id", encoded)
            self.assertNotIn("raw-reaction-id", encoded)
            self.assertNotIn("raw-target-message-id", encoded)
            self.assertNotIn(nonce, encoded)
            self.assertNotIn(receiver, encoded)

            cleanup = subprocess.run(
                [
                    sys.executable,
                    str(DRIVER),
                    "--action",
                    "cleanup-group-observation",
                    "--timeout-seconds",
                    "5",
                ],
                cwd=ROOT,
                env=environment,
                capture_output=True,
                text=True,
                timeout=15,
                check=False,
            )
            self.assertEqual(cleanup.returncode, 0, cleanup.stderr)
            state = json.loads((root / "state.json").read_text(encoding="utf-8"))
            self.assertEqual(state["lastAction"], "cleanup")

    def test_group_observation_holds_fence_until_pull_and_terminates_without_pretap_relaunch(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            fake = self._fake_xcrun(root)
            receiver = "00008110-001A123E0E91801E"
            environment = {
                **os.environ,
                "SIMS_IOS_RECEIVER_BOOTSTRAP_XCRUN": str(fake),
                "FAKE_DEVICECTL_STATE": str(root / "state.json"),
                "SIMS_IOS_PHYSICAL_DEVICE_ID": receiver,
                "SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE": (
                    "nonce-bootstrap-group-fence-1"
                ),
                "SIMS_IOS_GROUP_NOTIFICATION_OBSERVATION_RECEIPT_PATH": str(
                    root / "message-receipt.json"
                ),
            }
            digest = hashlib.sha256(b"message-phase").hexdigest()
            result = subprocess.run(
                [
                    sys.executable,
                    str(DRIVER),
                    "--action",
                    "observe-group",
                    "--phase",
                    "message",
                    "--expected-group-id-sha256",
                    hashlib.sha256(b"group").hexdigest(),
                    "--expected-event-id-sha256",
                    digest,
                    "--expected-target-message-id-sha256",
                    hashlib.sha256(b"target").hexdigest(),
                    "--timeout-seconds",
                    "10",
                ],
                cwd=ROOT,
                env=environment,
                capture_output=True,
                text=True,
                timeout=20,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            state = json.loads((root / "state.json").read_text(encoding="utf-8"))
            commands = state["commands"]
            launches = [
                (index, command)
                for index, command in enumerate(commands)
                if command.startswith("devicectl device process launch ")
            ]
            pulls = [
                index
                for index, command in enumerate(commands)
                if command.startswith("devicectl device copy from ")
                and "/group-observation-result.json" in command
            ]
            terminations = [
                index
                for index, command in enumerate(commands)
                if command.startswith("devicectl device process terminate ")
            ]
            self.assertEqual(len(launches), 1, commands)
            self.assertEqual(len(pulls), 1, commands)
            self.assertEqual(len(terminations), 1, commands)
            self.assertLess(launches[0][0], pulls[0], commands)
            self.assertLess(pulls[0], terminations[0], commands)
            self.assertEqual(terminations[0], len(commands) - 1, commands)
            self.assertIn("--pid 4242", commands[terminations[0]], commands)
            self.assertNotIn("com.mknoon.app", commands[terminations[0]], commands)
            self.assertEqual(state["lastAction"], "observe_group")
            self.assertNotIn("cleanup", " ".join(commands))

    def _fake_xcrun(self, root: Path) -> Path:
        script = root / "fake-xcrun.py"
        script.write_text(
            textwrap.dedent(
                r'''#!/usr/bin/env python3
import datetime, hashlib, json, os, pathlib, sys
args=sys.argv[1:]
state_path=pathlib.Path(os.environ['FAKE_DEVICECTL_STATE'])
if state_path.exists():
  state=json.loads(state_path.read_text())
else:
  state={'commands':[]}
state['commands'].append(' '.join(args))
def value(name):
  return args[args.index(name)+1]
if args[:4] == ['devicectl','device','copy','to']:
  request=json.loads(pathlib.Path(value('--source')).read_text())
  state['request']=request
  state['lastAction']=request['action']
elif args[:4] == ['devicectl','device','copy','from']:
  request=state.get('request',{})
  source=value('--source')
  sender_result=source.endswith('/sender-result.json')
  recovery_result=source.endswith('/recovery-result.json')
  group_result=source.endswith('/group-observation-result.json')
  if group_result and request.get('action') == 'observe_group':
    response={
      'schema':'mknoon.sims.ios-group-notification-observation-result.v1',
      'action':'observe_group',
      'phase':request['phase'],
      'captureNonce':request['captureNonce'],
      'receiverDeviceId':request['receiverDeviceId'],
      'bundleId':'com.mknoon.app',
      'expectedGroupIdSha256':request['expectedGroupIdSha256'],
      'expectedEventIdSha256':request['expectedEventIdSha256'],
      'expectedTargetMessageIdSha256':request['expectedTargetMessageIdSha256'],
      'status':'passed',
      'resultCode':'ok',
      'matchingRemoteCount':1,
      'matchingLocalCount':0,
      'matchingUsefulProviderCount':1,
      'matchingSanitizedProviderCount':0,
      'matchingFlutterLocalCount':0,
      'matchingUnknownCount':0,
      'matchingTotalCount':1,
      'stableSampleCount':3,
      'stableSampleIntervalMilliseconds':500,
      'observationDeadlineMilliseconds':8000,
      'sampledThroughDeadline':True,
      'badSourceSeen':False,
      'duplicateSeen':False,
      'requestIdentifierSha256':['b'*64],
      'childBuildCount':0,
      'manualActionCount':0,
      'completedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='milliseconds').replace('+00:00','Z'),
    }
  elif recovery_result and request.get('action') == 'prove_recovery':
    response={
      'schema':'mknoon.sims.ios-notification-recovery-result.v1',
      'action':'prove_recovery',
      'captureNonce':request['captureNonce'],
      'receiverDeviceId':request['receiverDeviceId'],
      'bundleId':'com.mknoon.app',
      'apnsPayloadSha256':request['apnsPayloadSha256'],
      'status':'passed',
      'resultCode':'ok',
      'badgeBefore':1,
      'badgeAfter':0,
      'deliveredBefore':1,
      'deliveredWithSentinel':2,
      'deliveredAfter':1,
      'deliveredNotificationBadgeWasNil':True,
      'sentinelSurvived':True,
      'removedExactOwnedNotification':True,
      'childBuildCount':0,
      'manualActionCount':0,
      'completedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='milliseconds').replace('+00:00','Z'),
    }
  elif sender_result and request.get('action') in ('seed_sender','cleanup_sender'):
    fields={
      'schema':'mknoon.sims.ios-sender-projection-request.v1',
      'captureNonce':request['captureNonce'],
      'receiverDeviceId':request['receiverDeviceId'],
      'bundleId':'com.mknoon.app',
      'senderPeerId':request['senderPeerId'],
      'senderUsername':request['senderUsername'],
      'apnsPayloadSha256':request['apnsPayloadSha256'],
    }
    fixture=hashlib.sha256(json.dumps(fields,separators=(',',':')).encode()).hexdigest()
    response={
      'schema':'mknoon.sims.ios-sender-projection-result.v1',
      'action':request['action'],
      'captureNonce':request['captureNonce'],
      'receiverDeviceId':request['receiverDeviceId'],
      'bundleId':'com.mknoon.app',
      'apnsPayloadSha256':request['apnsPayloadSha256'],
      'fixtureDigest':fixture,
      'status':'seeded' if request['action']=='seed_sender' else 'cleaned',
      'resultCode':'ok',
      'completedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='milliseconds').replace('+00:00','Z'),
    }
  elif request.get('action') == 'capture' and not sender_result:
    nonce=os.environ.get('FAKE_NONCE_OVERRIDE',request['captureNonce'])
    response={
      'schema':'mknoon.sims.ios-provider-receiver-handoff.v2',
      'captureNonce':nonce,
      'receiverDeviceId':request['receiverDeviceId'],
      'peerDeviceId':os.environ['FAKE_PEER_ID'],
      'bundleId':'com.mknoon.app',
      'apnsEnvironment':'development',
      'apnsDeviceToken':os.environ['FAKE_APNS_TOKEN'],
      'mlKemPublicKey':os.environ['FAKE_ML_KEM_PUBLIC'],
      'notificationAuthorization':os.environ.get('FAKE_NOTIFICATION_AUTHORIZATION','authorized'),
      'notificationAlertSetting':os.environ.get('FAKE_NOTIFICATION_ALERT_SETTING','enabled'),
      'notificationBadgeSetting':os.environ.get('FAKE_NOTIFICATION_BADGE_SETTING','enabled'),
      'capturedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='milliseconds').replace('+00:00','Z'),
    }
  else:
    state_path.write_text(json.dumps(state))
    raise SystemExit(1)
  destination=pathlib.Path(value('--destination'))
  destination.write_text(json.dumps(response))
  destination.chmod(0o600)
for option in ('--json-output','--log-output'):
  if option in args:
    output={}
    if option == '--json-output' and args[:4] == ['devicectl','device','process','launch']:
      output={'result':{'process':{'processIdentifier':4242}}}
    pathlib.Path(value(option)).write_text(json.dumps(output))
state_path.write_text(json.dumps(state))
'''
            ),
            encoding="utf-8",
        )
        script.chmod(0o700)
        return script


if __name__ == "__main__":
    unittest.main()
