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

    def test_final_capture_preserves_successful_receiver_launch(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            fake = self._fake_xcrun(root)
            output = root / "receiver-handoff.json"
            token = "ac" * 32
            ml_kem = base64.b64encode(b"F" * 1184).decode()
            environment = {
                **os.environ,
                "SIMS_IOS_RECEIVER_BOOTSTRAP_XCRUN": str(fake),
                "FAKE_DEVICECTL_STATE": str(root / "state.json"),
                "FAKE_APNS_TOKEN": token,
                "FAKE_PEER_ID": "12D3KooW" + "7" * 44,
                "FAKE_ML_KEM_PUBLIC": ml_kem,
                "SIMS_IOS_PHYSICAL_DEVICE_ID": "00008110-001A123E0E91801E",
                "SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE":
                    "nonce-bootstrap-final-contract-1",
                "SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_PATH": str(output),
            }
            result = subprocess.run(
                [
                    sys.executable,
                    str(DRIVER),
                    "--action",
                    "capture-receiver-final",
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
            self.assertTrue(output.is_file())
            self.assertNotIn(token, result.stdout + result.stderr)
            self.assertNotIn(ml_kem, result.stdout + result.stderr)
            state = json.loads((root / "state.json").read_text(encoding="utf-8"))
            self.assertEqual(state["lastAction"], "capture")
            launches = [
                command
                for command in state["commands"]
                if command.startswith("devicectl device process launch ")
            ]
            self.assertEqual(len(launches), 1, state["commands"])

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

    def test_final_capture_failure_still_launches_cleanup(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            fake = self._fake_xcrun(root)
            output = root / "receiver-handoff.json"
            token = "ad" * 32
            environment = {
                **os.environ,
                "SIMS_IOS_RECEIVER_BOOTSTRAP_XCRUN": str(fake),
                "FAKE_DEVICECTL_STATE": str(root / "state.json"),
                "FAKE_APNS_TOKEN": token,
                "FAKE_PEER_ID": "12D3KooW" + "8" * 44,
                "FAKE_ML_KEM_PUBLIC": base64.b64encode(b"G" * 1184).decode(),
                "FAKE_NONCE_OVERRIDE": "nonce-bootstrap-final-wrong-2",
                "SIMS_IOS_PHYSICAL_DEVICE_ID": "00008110-001A123E0E91801E",
                "SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE":
                    "nonce-bootstrap-final-contract-2",
                "SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_PATH": str(output),
            }
            result = subprocess.run(
                [
                    sys.executable,
                    str(DRIVER),
                    "--action",
                    "capture-receiver-final",
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

            self.assertEqual(result.returncode, 1)
            self.assertFalse(output.exists())
            self.assertNotIn(token, result.stdout + result.stderr)
            state = json.loads((root / "state.json").read_text(encoding="utf-8"))
            self.assertEqual(state["lastAction"], "cleanup")
            launches = [
                command
                for command in state["commands"]
                if command.startswith("devicectl device process launch ")
            ]
            self.assertEqual(len(launches), 2, state["commands"])

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
                    "content-available": 1,
                },
                "type": "new_message",
                "sender_id": sender,
                "message_id": "message-private-1",
                "gcm.message_id": "mknoon-sims-background-sender-1",
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
                    "content-available": 1,
                },
                "type": "new_message",
                "sender_id": sender,
                "message_id": "message-private-recovery-1",
                "gcm.message_id": "mknoon-sims-background-recovery-1",
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
                    "schema": "mknoon.sims.ios-notification-recovery-host-receipt.v2",
                    "action": "prove-recovery",
                    "proofStage": "single_submission",
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
                    "matchingRemoteCount": 1,
                    "matchingLocalCount": 0,
                    "matchingUsefulProviderCount": 1,
                    "matchingSanitizedProviderCount": 0,
                    "matchingFlutterLocalCount": 0,
                    "matchingUnknownCount": 0,
                    "matchingTotalCount": 1,
                    "stableSampleCount": 3,
                    "stableSampleIntervalMilliseconds": 500,
                    "settleDelayMilliseconds": 3000,
                    "observationDeadlineMilliseconds": 8000,
                    "requestIdentifierSha256": ["a" * 64],
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

    def test_notification_recovery_retains_exact_source_inventory(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            fake = self._fake_xcrun(root)
            receiver = "00008110-001A123E0E91801E"
            nonce = "nonce-bootstrap-recovery-source-1"
            peer = "12D3KooW" + "5" * 44
            sender = "12D3KooW" + "6" * 44
            payload = {
                "fixture_schema": "mknoon.sims.ios-payload-private-fixture.v1",
                "aps": {
                    "alert": {"title": "Encrypted title", "body": "Encrypted body"},
                    "mutable-content": 1,
                    "content-available": 1,
                },
                "type": "new_message",
                "sender_id": sender,
                "message_id": "message-private-source-1",
                "gcm.message_id": "mknoon-sims-background-source-1",
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
            receipt = root / "recovery-source-receipt.json"
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
            value = json.loads(receipt.read_text(encoding="utf-8"))
            self.assertEqual(
                value["schema"],
                "mknoon.sims.ios-notification-recovery-host-receipt.v2",
            )
            self.assertEqual(
                {
                    key: value[key]
                    for key in (
                        "matchingRemoteCount",
                        "matchingLocalCount",
                        "matchingUsefulProviderCount",
                        "matchingSanitizedProviderCount",
                        "matchingFlutterLocalCount",
                        "matchingUnknownCount",
                        "matchingTotalCount",
                        "stableSampleCount",
                        "stableSampleIntervalMilliseconds",
                        "settleDelayMilliseconds",
                        "observationDeadlineMilliseconds",
                    )
                },
                {
                    "matchingRemoteCount": 1,
                    "matchingLocalCount": 0,
                    "matchingUsefulProviderCount": 1,
                    "matchingSanitizedProviderCount": 0,
                    "matchingFlutterLocalCount": 0,
                    "matchingUnknownCount": 0,
                    "matchingTotalCount": 1,
                    "stableSampleCount": 3,
                    "stableSampleIntervalMilliseconds": 500,
                    "settleDelayMilliseconds": 3000,
                    "observationDeadlineMilliseconds": 8000,
                },
            )
            self.assertEqual(len(value["requestIdentifierSha256"]), 1)
            self.assertRegex(value["requestIdentifierSha256"][0], r"^[0-9a-f]{64}$")
            encoded = json.dumps(value, sort_keys=True)
            self.assertNotIn(peer, encoded)
            self.assertNotIn(sender, encoded)
            self.assertNotIn(payload["message_id"], encoded)

    def test_group_observation_is_exact_source_bound_redacted_and_cleaned(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            fake = self._fake_xcrun(root)
            receiver = "00008110-001A123E0E91801E"
            nonce = "nonce-bootstrap-group-observation-1"
            group_sha = hashlib.sha256(b"raw-group-id").hexdigest()
            event_sha = hashlib.sha256(b"raw-reaction-id").hexdigest()
            target_sha = hashlib.sha256(b"raw-target-message-id").hexdigest()
            raw_dispatch = "2d1fe9a0-a1d0-4eef-b43f-48f6df540ca0"
            raw_provider = "0:1771337139189655%0123456789abcdef"
            raw_collapse = "group-message-collapse-fixture"
            collapse_sha = hashlib.sha256(raw_collapse.encode()).hexdigest()
            receipt = root / "group-observation-receipt.json"
            environment = {
                **os.environ,
                "SIMS_IOS_RECEIVER_BOOTSTRAP_XCRUN": str(fake),
                "FAKE_DEVICECTL_STATE": str(root / "state.json"),
                "SIMS_IOS_PHYSICAL_DEVICE_ID": receiver,
                "SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE": nonce,
                "FAKE_GROUP_RAW_DISPATCH": raw_dispatch,
                "FAKE_GROUP_RAW_PROVIDER": raw_provider,
                "FAKE_GROUP_RAW_COLLAPSE": raw_collapse,
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
                    "--expected-collapse-identifier-sha256",
                    collapse_sha,
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
                    "expectedCollapseIdentifierSha256",
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
                    "diagnosticSchema",
                    "diagnosticRecords",
                    "diagnosticRecordCount",
                    "diagnosticOverflow",
                    "diagnosticConflict",
                    "diagnosticComplete",
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
                        "expectedCollapseIdentifierSha256",
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
                        "diagnosticRecordCount",
                        "diagnosticOverflow",
                        "diagnosticConflict",
                        "diagnosticComplete",
                        "runnerTerminated",
                        "preTapCleanupLaunchCount",
                        "resultCode",
                    )
                },
                {
                    "schema": (
                        "mknoon.sims.ios-group-notification-observation-"
                        "host-receipt.v3"
                    ),
                    "action": "observe-group",
                    "phase": "reaction",
                    "status": "PASS",
                    "containsSecrets": False,
                    "expectedGroupIdSha256": group_sha,
                    "expectedEventIdSha256": event_sha,
                    "expectedTargetMessageIdSha256": target_sha,
                    "expectedCollapseIdentifierSha256": collapse_sha,
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
                    "diagnosticRecordCount": 1,
                    "diagnosticOverflow": False,
                    "diagnosticConflict": False,
                    "diagnosticComplete": True,
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
            self.assertNotIn(raw_dispatch, encoded)
            self.assertNotIn(raw_provider, encoded)
            self.assertNotIn(raw_collapse, encoded)
            self.assertEqual(
                value["diagnosticSchema"],
                "mknoon.sims.ios-group-notification-diagnostics.v2",
            )
            self.assertEqual(len(value["diagnosticRecords"]), 1)
            diagnostic = value["diagnosticRecords"][0]
            self.assertEqual(
                set(diagnostic),
                {
                    "requestIdentifierSha256",
                    "dispatchCorrelationSha256",
                    "providerMessageIdSha256",
                    "claimedCollapseIdentifierSha256",
                    "triggerOrigin",
                    "sourceClass",
                    "reason",
                    "expectedCollapseIdentifierMatch",
                    "dispatchClaim",
                },
            )
            self.assertRegex(
                diagnostic["dispatchCorrelationSha256"], r"^[0-9a-f]{64}$"
            )
            self.assertRegex(
                diagnostic["providerMessageIdSha256"], r"^[0-9a-f]{64}$"
            )
            self.assertEqual(
                diagnostic["dispatchCorrelationSha256"],
                hashlib.sha256(raw_dispatch.encode()).hexdigest(),
            )
            self.assertEqual(
                diagnostic["providerMessageIdSha256"],
                hashlib.sha256(raw_provider.encode()).hexdigest(),
            )
            self.assertEqual(
                diagnostic["claimedCollapseIdentifierSha256"], collapse_sha
            )

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

    def test_group_observation_rejects_incomplete_raw_or_contradictory_provenance(
        self,
    ) -> None:
        mutations = (
            "missing_dispatch",
            "raw_dispatch",
            "uppercase_provider",
            "contradictory_match",
            "mismatched_top_level",
            "incomplete_record_count",
            "unexpected_raw_key",
        )
        for mutation in mutations:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as raw:
                root = Path(raw)
                fake = self._fake_xcrun(root)
                receipt = root / "invalid-provenance-receipt.json"
                environment = {
                    **os.environ,
                    "SIMS_IOS_RECEIVER_BOOTSTRAP_XCRUN": str(fake),
                    "FAKE_DEVICECTL_STATE": str(root / "state.json"),
                    "FAKE_GROUP_DIAGNOSTIC_MUTATION": mutation,
                    "SIMS_IOS_PHYSICAL_DEVICE_ID": "00008110-001A123E0E91801E",
                    "SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE": (
                        f"nonce-group-provenance-{mutation}"
                    ),
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
                        "message",
                        "--expected-group-id-sha256",
                        hashlib.sha256(b"group-provenance").hexdigest(),
                        "--expected-event-id-sha256",
                        hashlib.sha256(b"event-provenance").hexdigest(),
                        "--expected-target-message-id-sha256",
                        hashlib.sha256(b"target-provenance").hexdigest(),
                        "--expected-collapse-identifier-sha256",
                        "b" * 64,
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

                self.assertNotEqual(result.returncode, 0, mutation)
                self.assertFalse(receipt.exists(), mutation)
                combined = result.stdout + result.stderr
                self.assertNotIn("raw-dispatch-id", combined, mutation)

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
                    "--expected-collapse-identifier-sha256",
                    "b" * 64,
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

    def test_group_observation_recovers_terminal_native_failure_after_final_termination_pull(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            fake = self._fake_xcrun(root)
            receiver = "00008110-001A123E0E91801E"
            canonical = "b" * 64
            transient = "c" * 64
            receipt = root / "terminal-native-fail-receipt.json"
            environment = {
                **os.environ,
                "SIMS_IOS_RECEIVER_BOOTSTRAP_XCRUN": str(fake),
                "FAKE_DEVICECTL_STATE": str(root / "state.json"),
                "FAKE_GROUP_RESULT_AFTER_TERMINATION": "1",
                "FAKE_GROUP_NATIVE_STATUS": "failed",
                "FAKE_GROUP_TRANSIENT_DUPLICATE": "1",
                "SIMS_IOS_PHYSICAL_DEVICE_ID": receiver,
                "SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE": (
                    "nonce-bootstrap-group-terminal-fail-398"
                ),
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
                    "message",
                    "--expected-group-id-sha256",
                    hashlib.sha256(b"group-398").hexdigest(),
                    "--expected-event-id-sha256",
                    hashlib.sha256(b"message-398").hexdigest(),
                    "--expected-target-message-id-sha256",
                    hashlib.sha256(b"target-398").hexdigest(),
                    "--expected-collapse-identifier-sha256",
                    canonical,
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

            self.assertEqual(result.returncode, 1)
            self.assertTrue(receipt.is_file(), "TC-398-03 terminal pull")
            value = json.loads(receipt.read_text(encoding="utf-8"))
            self.assertEqual(value["status"], "FAIL")
            self.assertEqual(value["resultCode"], "bad_source_seen")
            self.assertEqual(value["matchingTotalCount"], 1)
            self.assertEqual(value["matchingRemoteCount"], 1)
            self.assertEqual(value["matchingLocalCount"], 0)
            self.assertEqual(value["matchingUsefulProviderCount"], 1)
            self.assertEqual(value["matchingSanitizedProviderCount"], 0)
            self.assertEqual(value["matchingFlutterLocalCount"], 0)
            self.assertEqual(value["matchingUnknownCount"], 0)
            self.assertEqual(value["requestIdentifierSha256"], [canonical])
            self.assertEqual(value["diagnosticRecordCount"], 2)
            self.assertEqual(
                [
                    record["requestIdentifierSha256"]
                    for record in value["diagnosticRecords"]
                ],
                [canonical, transient],
            )
            unknown = next(
                record
                for record in value["diagnosticRecords"]
                if record["expectedCollapseIdentifierMatch"] is False
            )
            self.assertIsNone(unknown["dispatchCorrelationSha256"])
            self.assertIsNone(unknown["providerMessageIdSha256"])
            self.assertIsNone(unknown["claimedCollapseIdentifierSha256"])
            state = json.loads((root / "state.json").read_text(encoding="utf-8"))
            commands = state["commands"]
            terminations = [
                index
                for index, command in enumerate(commands)
                if command.startswith("devicectl device process terminate ")
            ]
            pulls = [
                index
                for index, command in enumerate(commands)
                if command.startswith("devicectl device copy from ")
                and "/group-observation-result.json" in command
            ]
            self.assertEqual(len(terminations), 1, commands)
            self.assertGreater(len(pulls), 1, commands)
            self.assertEqual(len([index for index in pulls if index > terminations[0]]), 1)
            self.assertEqual(pulls[-1], len(commands) - 1, commands)

        valid_failure_profiles = (
            ("unstable_sample_count", "source_inventory_unstable"),
            ("unstable_deadline", "source_inventory_unstable"),
            ("duplicate_seen", "duplicate_seen"),
            ("source_inventory_mismatch", "source_inventory_mismatch"),
        )
        for profile, expected_code in valid_failure_profiles:
            with self.subTest(profile=profile), tempfile.TemporaryDirectory() as raw:
                root = Path(raw)
                fake = self._fake_xcrun(root)
                receipt = root / f"valid-fail-{profile}.json"
                environment = {
                    **os.environ,
                    "SIMS_IOS_RECEIVER_BOOTSTRAP_XCRUN": str(fake),
                    "FAKE_DEVICECTL_STATE": str(root / "state.json"),
                    "FAKE_GROUP_NATIVE_STATUS": "failed",
                    "FAKE_GROUP_FAILURE_PROFILE": profile,
                    "SIMS_IOS_PHYSICAL_DEVICE_ID": "00008110-001A123E0E91801E",
                    "SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE": (
                        f"nonce-group-valid-fail-{profile}"
                    ),
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
                        "message",
                        "--expected-group-id-sha256",
                        hashlib.sha256(b"group-valid-failure-code").hexdigest(),
                        "--expected-event-id-sha256",
                        hashlib.sha256(b"message-valid-failure-code").hexdigest(),
                        "--expected-target-message-id-sha256",
                        hashlib.sha256(b"target-valid-failure-code").hexdigest(),
                        "--expected-collapse-identifier-sha256",
                        "b" * 64,
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

                self.assertEqual(result.returncode, 1, profile)
                self.assertTrue(receipt.is_file(), profile)
                value = json.loads(receipt.read_text(encoding="utf-8"))
                self.assertEqual(value["status"], "FAIL", profile)
                self.assertEqual(value["resultCode"], expected_code, profile)

        invalid_fail_mutations = (
            ("mismatched_top_level", True, "failed"),
            ("failed_origin_total", True, "failed"),
            ("failed_source_total", True, "failed"),
            ("failed_origin_recompute", True, "failed"),
            ("failed_source_recompute", True, "failed"),
            ("unsorted_final", False, "failed"),
            ("duplicate_final", False, "failed"),
            ("failed_result_ok", True, "failed"),
            ("failed_result_unknown", True, "failed"),
            ("failed_result_wrong_precedence", True, "failed"),
            ("failed_unstable_wrong_precedence", False, "failed"),
            ("passed_failure_code", False, "passed"),
        )
        for mutation, transient_duplicate, native_status in invalid_fail_mutations:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as raw:
                root = Path(raw)
                fake = self._fake_xcrun(root)
                receipt = root / f"invalid-fail-{mutation}.json"
                environment = {
                    **os.environ,
                    "SIMS_IOS_RECEIVER_BOOTSTRAP_XCRUN": str(fake),
                    "FAKE_DEVICECTL_STATE": str(root / "state.json"),
                    "FAKE_GROUP_NATIVE_STATUS": native_status,
                    "FAKE_GROUP_DIAGNOSTIC_MUTATION": mutation,
                    "SIMS_IOS_PHYSICAL_DEVICE_ID": "00008110-001A123E0E91801E",
                    "SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE": (
                        f"nonce-group-fail-{mutation}"
                    ),
                    "SIMS_IOS_GROUP_NOTIFICATION_OBSERVATION_RECEIPT_PATH": str(
                        receipt
                    ),
                }
                if transient_duplicate:
                    environment["FAKE_GROUP_TRANSIENT_DUPLICATE"] = "1"
                result = subprocess.run(
                    [
                        sys.executable,
                        str(DRIVER),
                        "--action",
                        "observe-group",
                        "--phase",
                        "message",
                        "--expected-group-id-sha256",
                        hashlib.sha256(b"group-fail-aggregate").hexdigest(),
                        "--expected-event-id-sha256",
                        hashlib.sha256(b"message-fail-aggregate").hexdigest(),
                        "--expected-target-message-id-sha256",
                        hashlib.sha256(b"target-fail-aggregate").hexdigest(),
                        "--expected-collapse-identifier-sha256",
                        "b" * 64,
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

                self.assertNotEqual(result.returncode, 0, mutation)
                self.assertFalse(receipt.exists(), mutation)

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
if args[:4] == ['devicectl','device','process','terminate']:
  state['terminated']=True
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
    if os.environ.get('FAKE_GROUP_RESULT_AFTER_TERMINATION') == '1' and not state.get('terminated'):
      state_path.write_text(json.dumps(state))
      raise SystemExit(1)
    native_status=os.environ.get('FAKE_GROUP_NATIVE_STATUS','passed')
    native_failed=native_status == 'failed'
    transient_duplicate=(
      native_failed and os.environ.get('FAKE_GROUP_TRANSIENT_DUPLICATE') == '1'
    )
    failure_profile=os.environ.get('FAKE_GROUP_FAILURE_PROFILE','bad_source_seen')
    canonical=request['expectedCollapseIdentifierSha256']
    unknown='c'*64
    raw_dispatch=os.environ.get('FAKE_GROUP_RAW_DISPATCH')
    raw_provider=os.environ.get('FAKE_GROUP_RAW_PROVIDER')
    raw_collapse=os.environ.get('FAKE_GROUP_RAW_COLLAPSE')
    dispatch_sha=(hashlib.sha256(raw_dispatch.encode()).hexdigest()
                  if raw_dispatch else 'd'*64)
    provider_sha=(hashlib.sha256(raw_provider.encode()).hexdigest()
                  if raw_provider else 'e'*64)
    claimed_collapse_sha=(hashlib.sha256(raw_collapse.encode()).hexdigest()
                          if raw_collapse else canonical)
    diagnostics=[{
      'requestIdentifierSha256':canonical,
      'dispatchCorrelationSha256':dispatch_sha,
      'providerMessageIdSha256':provider_sha,
      'claimedCollapseIdentifierSha256':claimed_collapse_sha,
      'triggerOrigin':'remote',
      'sourceClass':'usefulProviderRich',
      'reason':'exactUseful',
      'expectedCollapseIdentifierMatch':True,
      'dispatchClaim':'groupInbox',
    }]
    if native_failed:
      diagnostics.append({
        'requestIdentifierSha256':unknown,
        'dispatchCorrelationSha256':None,
        'providerMessageIdSha256':None,
        'claimedCollapseIdentifierSha256':None,
        'triggerOrigin':'remote',
        'sourceClass':'unknown',
        'reason':'unclassifiedRemote',
        'expectedCollapseIdentifierMatch':False,
        'dispatchClaim':'groupInbox',
      })
    response={
      'schema':'mknoon.sims.ios-group-notification-observation-result.v3',
      'action':'observe_group',
      'phase':request['phase'],
      'captureNonce':request['captureNonce'],
      'receiverDeviceId':request['receiverDeviceId'],
      'bundleId':'com.mknoon.app',
      'expectedGroupIdSha256':request['expectedGroupIdSha256'],
      'expectedEventIdSha256':request['expectedEventIdSha256'],
      'expectedTargetMessageIdSha256':request['expectedTargetMessageIdSha256'],
      'expectedCollapseIdentifierSha256':canonical,
      'status':native_status,
      'resultCode':'bad_source_seen' if native_failed else 'ok',
      'matchingRemoteCount':1 if transient_duplicate else (2 if native_failed else 1),
      'matchingLocalCount':0,
      'matchingUsefulProviderCount':1,
      'matchingSanitizedProviderCount':0,
      'matchingFlutterLocalCount':0,
      'matchingUnknownCount':0 if transient_duplicate else (1 if native_failed else 0),
      'matchingTotalCount':1 if transient_duplicate else (2 if native_failed else 1),
      'stableSampleCount':3,
      'stableSampleIntervalMilliseconds':500,
      'observationDeadlineMilliseconds':8000,
      'sampledThroughDeadline':True,
      'badSourceSeen':native_failed,
      'duplicateSeen':native_failed,
      'requestIdentifierSha256':(
        [canonical]
        if transient_duplicate
        else sorted([row['requestIdentifierSha256'] for row in diagnostics])
      ),
      'diagnosticSchema':'mknoon.sims.ios-group-notification-diagnostics.v2',
      'diagnosticRecords':sorted(diagnostics,key=lambda row:row['requestIdentifierSha256']),
      'diagnosticRecordCount':len(diagnostics),
      'diagnosticOverflow':False,
      'diagnosticConflict':False,
      'diagnosticComplete':True,
      'childBuildCount':0,
      'manualActionCount':0,
      'completedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='milliseconds').replace('+00:00','Z'),
    }
    if native_failed and failure_profile == 'unstable_sample_count':
      response['stableSampleCount']=2
      response['resultCode']='source_inventory_unstable'
    elif native_failed and failure_profile == 'unstable_deadline':
      response['sampledThroughDeadline']=False
      response['diagnosticComplete']=False
      response['resultCode']='source_inventory_unstable'
    elif native_failed and failure_profile == 'duplicate_seen':
      duplicate=response['diagnosticRecords'][-1]
      duplicate['sourceClass']='usefulProviderRich'
      duplicate['reason']='exactUseful'
      response['matchingUsefulProviderCount']=2
      response['matchingUnknownCount']=0
      response['badSourceSeen']=False
      response['resultCode']='duplicate_seen'
    elif native_failed and failure_profile == 'source_inventory_mismatch':
      mismatch='f'*64
      record=response['diagnosticRecords'][0]
      record['requestIdentifierSha256']=mismatch
      record['expectedCollapseIdentifierMatch']=False
      response['diagnosticRecords']=[record]
      response['diagnosticRecordCount']=1
      response['matchingRemoteCount']=1
      response['matchingUsefulProviderCount']=1
      response['matchingUnknownCount']=0
      response['matchingTotalCount']=1
      response['requestIdentifierSha256']=[mismatch]
      response['badSourceSeen']=False
      response['duplicateSeen']=False
      response['resultCode']='source_inventory_mismatch'
    mutation=os.environ.get('FAKE_GROUP_DIAGNOSTIC_MUTATION','')
    if mutation == 'missing_dispatch':
      diagnostics[0].pop('dispatchCorrelationSha256')
    elif mutation == 'raw_dispatch':
      diagnostics[0]['dispatchCorrelationSha256']='raw-dispatch-id'
    elif mutation == 'uppercase_provider':
      diagnostics[0]['providerMessageIdSha256']='E'*64
    elif mutation == 'contradictory_match':
      diagnostics[0]['expectedCollapseIdentifierMatch']=False
    elif mutation == 'mismatched_top_level':
      response['requestIdentifierSha256']=['f'*64]
    elif mutation == 'failed_origin_total':
      response['matchingRemoteCount']+=1
    elif mutation == 'failed_source_total':
      response['matchingUnknownCount']+=1
    elif mutation == 'failed_origin_recompute':
      response['matchingRemoteCount']=0
      response['matchingLocalCount']=response['matchingTotalCount']
    elif mutation == 'failed_source_recompute':
      response['matchingUsefulProviderCount']=0
      response['matchingUnknownCount']=response['matchingTotalCount']
    elif mutation == 'unsorted_final':
      response['requestIdentifierSha256']=list(
        reversed(response['requestIdentifierSha256'])
      )
    elif mutation == 'duplicate_final':
      response['requestIdentifierSha256']=[canonical,canonical]
    elif mutation == 'failed_result_ok':
      response['resultCode']='ok'
    elif mutation == 'failed_result_unknown':
      response['resultCode']='plausible_future_failure'
    elif mutation == 'failed_result_wrong_precedence':
      response['resultCode']='duplicate_seen'
    elif mutation == 'failed_unstable_wrong_precedence':
      response['stableSampleCount']=2
      response['resultCode']='bad_source_seen'
    elif mutation == 'passed_failure_code':
      response['resultCode']='source_inventory_mismatch'
    elif mutation == 'incomplete_record_count':
      response['diagnosticRecordCount']=0
    elif mutation == 'unexpected_raw_key':
      diagnostics[0]['dispatchCorrelation']='raw-dispatch-id'
  elif recovery_result and request.get('action') in ('prove_recovery','observe_direct'):
    response={
      'schema':'mknoon.sims.ios-notification-recovery-result.v2',
      'action':request['action'],
      'proofStage':request['proofStage'],
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
      'matchingRemoteCount':1,
      'matchingLocalCount':0,
      'matchingUsefulProviderCount':1,
      'matchingSanitizedProviderCount':0,
      'matchingFlutterLocalCount':0,
      'matchingUnknownCount':0,
      'matchingTotalCount':1,
      'stableSampleCount':3,
      'stableSampleIntervalMilliseconds':500,
      'settleDelayMilliseconds':3000,
      'observationDeadlineMilliseconds':8000,
      'requestIdentifierSha256':['a'*64],
      'childBuildCount':0,
      'manualActionCount':0,
      'completedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='milliseconds').replace('+00:00','Z'),
    }
    if request['action'] == 'observe_direct':
      response.update({
        'badgeAfter':1,
        'deliveredWithSentinel':1,
        'sentinelSurvived':False,
        'removedExactOwnedNotification':False,
      })
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
