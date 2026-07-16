#!/usr/bin/env python3

import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile
from types import SimpleNamespace
import unittest


ROOT = Path(__file__).resolve().parents[2]
DRIVER = ROOT / "integration_test/scripts/ios_notification_relay_fixture_driver.py"
REMOTE_HELPER = ROOT / "integration_test/scripts/ios_notification_relay_remote_helper.py"


def _load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _private(path: Path, value: str) -> None:
    path.write_text(value, encoding="utf-8")
    path.chmod(stat.S_IRUSR | stat.S_IWUSR)


def _executable(path: Path, value: str) -> None:
    path.write_text(value, encoding="utf-8")
    path.chmod(stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR)


def _valid_remote_request(helper):
    peer = "12D3KooW" + "a" * 44
    sender = "12D3KooW" + "b" * 44
    envelope = {
        "type": "chat_message",
        "version": "2",
        "id": "ios-sims-message-bound",
        "senderPeerId": sender,
        "encrypted": {"kem": "opaque-kem", "ciphertext": "opaque", "nonce": "opaque"},
    }
    envelope_text = helper._canonical(envelope)
    return {
        "schema": helper.REQUEST_SCHEMA,
        "action": "setup",
        "runId": "run-1234",
        "nonce": "nonce-1234",
        "peerDeviceId": peer,
        "senderPeerId": sender,
        "entryId": helper._stable_entry_id("run-1234", "nonce-1234", peer),
        "encryptedEnvelope": envelope_text,
        "apnsPayloadSha256": "a" * 64,
        "encryptedEnvelopeSha256": helper._sha256_text(envelope_text),
        "stagedEnvelopeSha256": "b" * 64,
        "expectedRelayRevision": "v1.6.0",
        "expectedRelaySha256": "c" * 64,
    }


class _FakeRedis:
    def __init__(self, entries: list[str]):
        self.entries = entries
        self.queued: tuple[str, tuple[object, ...]] | None = None

    def command(self, name: str, *parts: object):
        if name in {"WATCH", "UNWATCH"}:
            return "OK"
        if name == "LRANGE":
            return list(self.entries)
        if name == "MULTI":
            return "OK"
        if name in {"RPUSH", "LREM"}:
            self.queued = (name, parts)
            return "QUEUED"
        if name == "EXEC":
            if self.queued is None:
                raise AssertionError("EXEC without queued command")
            queued, queued_parts = self.queued
            self.queued = None
            if queued == "RPUSH":
                self.entries.append(str(queued_parts[1]))
                return [len(self.entries)]
            exact = str(queued_parts[2])
            self.entries.remove(exact)
            return [1]
        raise AssertionError(f"unexpected Redis command {name}")


class IosNotificationRelayRemoteHelperTest(unittest.TestCase):
    def test_request_and_envelope_reject_duplicate_keys(self) -> None:
        helper = _load(REMOTE_HELPER, "ios_relay_remote_helper_duplicates")
        request = _valid_remote_request(helper)
        encoded = helper._canonical(request)
        schema_field = f'"schema":"{helper.REQUEST_SCHEMA}"'
        duplicate_request = encoded.replace(
            schema_field,
            f"{schema_field},{schema_field}",
            1,
        )
        with self.assertRaises(helper.RemoteFailure):
            helper._validated_request(duplicate_request.encode())

        envelope = json.loads(request["encryptedEnvelope"])
        cases = {
            "envelope": request["encryptedEnvelope"].replace(
                '"id":"ios-sims-message-bound"',
                '"id":"ios-sims-message-bound","id":"ios-sims-message-bound"',
                1,
            ),
            "encrypted": request["encryptedEnvelope"].replace(
                '"kem":"opaque-kem"',
                '"kem":"opaque-kem","kem":"opaque-kem"',
                1,
            ),
        }
        self.assertEqual(envelope["id"], "ios-sims-message-bound")
        for name, envelope_text in cases.items():
            with self.subTest(name=name):
                candidate = dict(request)
                candidate["encryptedEnvelope"] = envelope_text
                candidate["encryptedEnvelopeSha256"] = helper._sha256_text(envelope_text)
                with self.assertRaises(helper.RemoteFailure):
                    helper._validated_request(helper._canonical(candidate).encode())

    def test_request_envelope_and_encrypted_objects_require_exact_keys(self) -> None:
        helper = _load(REMOTE_HELPER, "ios_relay_remote_helper_exact_keys")
        request = _valid_remote_request(helper)

        request_cases = {}
        missing_request = dict(request)
        missing_request.pop("nonce")
        request_cases["request missing"] = missing_request
        extra_request = dict(request)
        extra_request["unexpected"] = "value"
        request_cases["request extra"] = extra_request

        for name, candidate in request_cases.items():
            with self.subTest(name=name):
                with self.assertRaises(helper.RemoteFailure):
                    helper._validated_request(helper._canonical(candidate).encode())

        envelope = json.loads(request["encryptedEnvelope"])
        envelope_cases = {}
        missing_envelope = dict(envelope)
        missing_envelope.pop("id")
        envelope_cases["envelope missing"] = missing_envelope
        extra_envelope = dict(envelope)
        extra_envelope["unexpected"] = "value"
        envelope_cases["envelope extra"] = extra_envelope
        missing_encrypted = dict(envelope)
        missing_encrypted["encrypted"] = dict(envelope["encrypted"])
        missing_encrypted["encrypted"].pop("nonce")
        envelope_cases["encrypted missing"] = missing_encrypted
        extra_encrypted = dict(envelope)
        extra_encrypted["encrypted"] = dict(envelope["encrypted"])
        extra_encrypted["encrypted"]["unexpected"] = "value"
        envelope_cases["encrypted extra"] = extra_encrypted

        for name, candidate_envelope in envelope_cases.items():
            with self.subTest(name=name):
                candidate = dict(request)
                envelope_text = helper._canonical(candidate_envelope)
                candidate["encryptedEnvelope"] = envelope_text
                candidate["encryptedEnvelopeSha256"] = helper._sha256_text(envelope_text)
                with self.assertRaises(helper.RemoteFailure):
                    helper._validated_request(helper._canonical(candidate).encode())

    def test_relay_revision_attestation_requires_exact_version_token(self) -> None:
        helper = _load(REMOTE_HELPER, "ios_relay_remote_helper_revision")
        self.assertTrue(
            helper._relay_revision_matches("v1.6.0", "relay-server v1.6.0\n")
        )
        for expected, actual in (
            ("v1.6.0", "relay-server v1.6.0evil"),
            ("v1.6.0", "prefix relay-server v1.6.0"),
            ("v1.6.0", "relay-server v1.6.0 suffix"),
        ):
            with self.subTest(expected=expected, actual=actual):
                self.assertFalse(helper._relay_revision_matches(expected, actual))

    def test_exact_fixture_is_idempotent_and_never_evicts_unrelated_rows(self) -> None:
        helper = _load(REMOTE_HELPER, "ios_relay_remote_helper")
        peer = "12D3KooW" + "a" * 44
        sender = "12D3KooW" + "b" * 44
        envelope = {
            "type": "chat_message",
            "version": "2",
            "id": "ios-sims-message-1",
            "senderPeerId": sender,
            "encrypted": {"kem": "opaque-kem", "ciphertext": "opaque", "nonce": "opaque"},
        }
        request = {
            "entryId": helper._stable_entry_id("run-1234", "nonce-1234", peer),
            "senderPeerId": sender,
            "encryptedEnvelope": helper._canonical(envelope),
        }

        at_capacity = _FakeRedis(
            [
                helper._canonical(
                    {
                        "id": f"unrelated-{index}",
                        "from": "peer-unrelated",
                        "message": json.dumps({"id": f"unrelated-message-{index}"}),
                        "timestamp": 1,
                    }
                )
                for index in range(2)
            ]
        )
        with self.assertRaises(helper.RemoteFailure):
            helper.seed_exact_entry(at_capacity, "relay:inbox:key", request, 2)
        self.assertEqual(len(at_capacity.entries), 2)

        redis = _FakeRedis([])
        entry_sha, mutated = helper.seed_exact_entry(redis, "relay:inbox:key", request, 2)
        self.assertTrue(mutated)
        self.assertRegex(entry_sha, r"^[0-9a-f]{64}$")
        self.assertEqual(len(redis.entries), 1)

        replay_sha, replay_mutated = helper.seed_exact_entry(
            redis, "relay:inbox:key", request, 2
        )
        self.assertFalse(replay_mutated)
        self.assertEqual(replay_sha, entry_sha)
        self.assertEqual(len(redis.entries), 1)

        removed_sha, removed = helper.clear_exact_entry(redis, "relay:inbox:key", request)
        self.assertEqual((removed_sha, removed), (entry_sha, 1))
        self.assertEqual(redis.entries, [])
        self.assertEqual(
            helper.clear_exact_entry(redis, "relay:inbox:key", request),
            (None, 0),
        )

    def test_conflicting_run_identity_fails_without_mutation(self) -> None:
        helper = _load(REMOTE_HELPER, "ios_relay_remote_helper_conflict")
        request = {
            "entryId": "sims-ios-relay-" + "a" * 32,
            "senderPeerId": "12D3KooW" + "b" * 44,
            "encryptedEnvelope": helper._canonical(
                {
                    "type": "chat_message",
                    "version": "2",
                    "id": "message-bound",
                    "senderPeerId": "12D3KooW" + "b" * 44,
                    "encrypted": {"kem": "k", "ciphertext": "c", "nonce": "n"},
                }
            ),
        }
        conflicting = helper._canonical(
            {
                "id": request["entryId"],
                "from": "peer-other",
                "message": json.dumps({"id": "other-message"}),
                "timestamp": 1,
            }
        )
        redis = _FakeRedis([conflicting])
        with self.assertRaises(helper.RemoteFailure):
            helper.clear_exact_entry(redis, "relay:inbox:key", request)
        self.assertEqual(redis.entries, [conflicting])


class IosNotificationRelayFixtureDriverTest(unittest.TestCase):
    def test_relay_surface_has_no_standalone_apns_token_dependency(self) -> None:
        obsolete_environment = "SIMS_IOS_APNS_" + "DEVICE_TOKEN_PATH"
        for relative in (
            "integration_test/scripts/ios_notification_relay_fixture_driver.py",
            "integration_test/scripts/ios_notification_relay_remote_helper.py",
            "integration_test/scripts/ios_notification_relay_fixture.md",
        ):
            source = (ROOT / relative).read_text(encoding="utf-8")
            self.assertNotIn(obsolete_environment, source, relative)
            self.assertNotIn("--device-token", source, relative)
        driver_source = DRIVER.read_text(encoding="utf-8")
        helper_source = REMOTE_HELPER.read_text(encoding="utf-8")
        self.assertNotIn("apnsDeviceToken", driver_source)
        self.assertNotIn("apnsDeviceToken", helper_source)

    def test_payload_digest_binds_exact_private_file_bytes(self) -> None:
        driver = _load(DRIVER, "ios_relay_fixture_driver_exact_bytes")
        with tempfile.TemporaryDirectory(prefix="ios-relay-payload-sha-") as raw:
            root = Path(raw)
            payload = {
                "fixture_schema": driver.PRIVATE_PAYLOAD_SCHEMA,
                "aps": {
                    "alert": {"title": "Title", "body": "Body"},
                    "mutable-content": 1,
                },
                "type": "new_message",
                "sender_id": "12D3KooW" + "b" * 44,
                "message_id": "message-exact-byte-sha",
                "kem": base64.b64encode(b"k" * 1088).decode(),
                "ciphertext": base64.b64encode(b"c" * 64).decode(),
                "nonce": base64.b64encode(b"n" * 12).decode(),
            }
            compact_path = root / "compact.json"
            reordered_path = root / "reordered.json"
            _private(
                compact_path,
                json.dumps(payload, separators=(",", ":"), sort_keys=True) + "\n",
            )
            reordered = dict(reversed(list(payload.items())))
            _private(reordered_path, json.dumps(reordered, indent=2) + "\n")
            compact = driver._json_object(compact_path, "compact payload")
            reparsed = driver._json_object(reordered_path, "reordered payload")
            self.assertEqual(compact, reparsed)

            args = SimpleNamespace(
                action="setup",
                run_id="exact-byte-run",
                nonce="exact-byte-nonce",
                peer_device="12D3KooW" + "a" * 44,
            )
            staging = {
                "candidateRelayRevision": "relay-revision",
                "candidateRelaySha256": "a" * 64,
            }
            compact_request = driver._remote_request(
                args, staging, compact_path, compact
            )
            reordered_request = driver._remote_request(
                args, staging, reordered_path, reparsed
            )
            self.assertNotEqual(
                compact_request["apnsPayloadSha256"],
                reordered_request["apnsPayloadSha256"],
            )
            self.assertEqual(
                compact_request["apnsPayloadSha256"],
                hashlib.sha256(compact_path.read_bytes()).hexdigest(),
            )
            self.assertEqual(
                reordered_request["apnsPayloadSha256"],
                hashlib.sha256(reordered_path.read_bytes()).hexdigest(),
            )
            self.assertEqual(
                compact_request["encryptedEnvelopeSha256"],
                reordered_request["encryptedEnvelopeSha256"],
            )

    def test_private_json_reader_rejects_nested_duplicate_keys(self) -> None:
        driver = _load(DRIVER, "ios_relay_fixture_driver_duplicate_keys")
        with tempfile.TemporaryDirectory(prefix="ios-relay-duplicate-json-") as raw:
            path = Path(raw) / "duplicate.json"
            _private(path, '{"outer":{"sender_id":"one","sender_id":"two"}}')
            with self.assertRaises(driver.FixtureBlocked):
                driver._json_object(path, "private payload")

    def test_lifecycle_requires_exact_action_pending_state_and_digests(self) -> None:
        driver = _load(DRIVER, "ios_relay_fixture_driver_lifecycle")
        with tempfile.TemporaryDirectory(prefix="ios-relay-lifecycle-") as raw:
            root = Path(raw)
            request_path = root / "request.json"
            staging_path = root / "staging.json"
            payload_path = root / "payload.json"
            request_path.write_bytes(b'{"request":"exact"}\n')
            staging_path.write_bytes(b'{"staging":"exact"}\n')
            payload_path.write_bytes(b'{"payload":"exact"}\n')
            payload = {
                "message_id": "message-bound",
                "sender_id": "12D3KooW" + "b" * 44,
                "kem": "opaque-kem",
                "ciphertext": "opaque-ciphertext",
                "nonce": "opaque-nonce",
            }
            args = SimpleNamespace(
                action="setup",
                run_id="lifecycle-run",
                nonce="lifecycle-nonce",
                receiver="00008150-001C3C6A3684401C",
                peer_device="12D3KooW" + "a" * 44,
                apns_payload_sha256=hashlib.sha256(payload_path.read_bytes()).hexdigest(),
                receiver_handoff_sha256="d" * 64,
            )
            lifecycle = {
                "schema": driver.LIFECYCLE_SCHEMA,
                "state": "fixture_spawn_pending",
                "runId": args.run_id,
                "nonce": args.nonce,
                "receiverDeviceIdSha256": hashlib.sha256(args.receiver.encode()).hexdigest(),
                "peerDeviceIdSha256": hashlib.sha256(args.peer_device.encode()).hexdigest(),
                "requestSha256": hashlib.sha256(request_path.read_bytes()).hexdigest(),
                "stagingManifestSha256": hashlib.sha256(staging_path.read_bytes()).hexdigest(),
                "apnsPayloadSha256": args.apns_payload_sha256,
                "receiverHandoffSha256": args.receiver_handoff_sha256,
                "stagedEnvelopeSha256": driver._staged_digest(payload),
                "recordedAt": "2026-07-16T12:00:00.000Z",
            }
            driver._validate_lifecycle(
                args,
                lifecycle,
                request_path,
                staging_path,
                payload_path,
                payload,
            )

            invalid_lifecycles = {}
            wrong_state = dict(lifecycle)
            wrong_state["state"] = "cleanup_spawn_pending"
            invalid_lifecycles["wrong action state"] = wrong_state
            extra_key = dict(lifecycle)
            extra_key["unexpected"] = "value"
            invalid_lifecycles["extra key"] = extra_key
            missing_key = dict(lifecycle)
            missing_key.pop("stagingManifestSha256")
            invalid_lifecycles["missing key"] = missing_key
            wrong_handoff = dict(lifecycle)
            wrong_handoff["receiverHandoffSha256"] = "e" * 64
            invalid_lifecycles["wrong handoff"] = wrong_handoff
            for name, candidate in invalid_lifecycles.items():
                with self.subTest(name=name):
                    with self.assertRaises(driver.FixtureBlocked):
                        driver._validate_lifecycle(
                            args,
                            candidate,
                            request_path,
                            staging_path,
                            payload_path,
                            payload,
                        )

            for field in ("apns_payload_sha256", "receiver_handoff_sha256"):
                with self.subTest(invalid_digest=field):
                    invalid_args = SimpleNamespace(**vars(args))
                    setattr(invalid_args, field, "not-a-sha256")
                    with self.assertRaises(driver.FixtureBlocked):
                        driver._validate_lifecycle(
                            invalid_args,
                            lifecycle,
                            request_path,
                            staging_path,
                            payload_path,
                            payload,
                        )

            payload_path.write_bytes(b'{"payload":"changed"}\n')
            with self.assertRaises(driver.FixtureBlocked):
                driver._validate_lifecycle(
                    args,
                    lifecycle,
                    request_path,
                    staging_path,
                    payload_path,
                    payload,
                )

    def test_setup_cleanup_and_rollback_emit_bound_receipts_over_ssh_stdin(self) -> None:
        driver = _load(DRIVER, "ios_relay_fixture_driver")
        with tempfile.TemporaryDirectory(prefix="ios-relay-fixture-") as raw:
            root = Path(raw)
            fake_bin = root / "bin"
            fake_bin.mkdir()
            captures = root / "captures"
            captures.mkdir()
            peer = "12D3KooW" + "a" * 44
            sender = "12D3KooW" + "b" * 44
            receiver = "00008150-001C3C6A3684401C"
            run_id = "ios-relay-run-1234"
            nonce = "ios-relay-nonce-1234"
            request = {
                "schema": driver.REQUEST_SCHEMA,
                "expectedTitle": "Private title",
                "expectedBody": "Private body",
                "expectedMessageText": "plaintext must stay encrypted",
                "receiverDeviceId": receiver,
                "peerDeviceId": peer,
            }
            staging = {
                "schema": driver.STAGING_SCHEMA,
                "environment": "staging",
                "provider": "apns",
                "apnsEnvironment": "development",
                "signingEntitlementEnvironment": "development",
                "relayActive": True,
                "relayInboxSeedDriverAvailable": True,
                "providerCleanupAvailable": True,
                "productionDeploymentPerformed": False,
                "receiverDeviceId": receiver,
                "peerDeviceId": peer,
                "candidateRelayRevision": "relay-revision-1234",
                "candidateRelaySha256": "a" * 64,
            }
            payload = {
                "fixture_schema": driver.PRIVATE_PAYLOAD_SCHEMA,
                "aps": {
                    "alert": {
                        "title": request["expectedTitle"],
                        "body": request["expectedBody"],
                    },
                    "mutable-content": 1,
                },
                "type": "new_message",
                "sender_id": sender,
                "message_id": "ios-sims-message-1234",
                "kem": base64.b64encode(b"k" * 1088).decode(),
                "ciphertext": base64.b64encode(b"c" * 64).decode(),
                "nonce": base64.b64encode(b"n" * 12).decode(),
            }
            request_path = root / "request.json"
            staging_path = root / "staging.json"
            payload_path = root / "payload.json"
            lifecycle_path = root / "lifecycle.json"
            relay_key = root / "relay-key"
            _private(request_path, json.dumps(request))
            _private(staging_path, json.dumps(staging))
            _private(payload_path, json.dumps(payload, separators=(",", ":"), sort_keys=True) + "\n")
            _private(relay_key, "fake-private-relay-key\n")
            payload_sha = hashlib.sha256(payload_path.read_bytes()).hexdigest()
            handoff_sha = "d" * 64

            def write_lifecycle(action: str) -> None:
                state = {
                    "setup": "fixture_spawn_pending",
                    "cleanup": "cleanup_spawn_pending",
                    "rollback": "rollback_spawn_pending",
                }[action]
                lifecycle = {
                    "schema": driver.LIFECYCLE_SCHEMA,
                    "state": state,
                    "runId": run_id,
                    "nonce": nonce,
                    "receiverDeviceIdSha256": hashlib.sha256(receiver.encode()).hexdigest(),
                    "peerDeviceIdSha256": hashlib.sha256(peer.encode()).hexdigest(),
                    "requestSha256": hashlib.sha256(request_path.read_bytes()).hexdigest(),
                    "stagingManifestSha256": hashlib.sha256(staging_path.read_bytes()).hexdigest(),
                    "apnsPayloadSha256": payload_sha,
                    "receiverHandoffSha256": handoff_sha,
                    "stagedEnvelopeSha256": driver._staged_digest(payload),
                    "recordedAt": "2026-07-16T12:00:00.000Z",
                }
                _private(lifecycle_path, json.dumps(lifecycle))

            fake_ssh = fake_bin / "ssh"
            _executable(
                fake_ssh,
                """#!/usr/bin/env python3
import base64, hashlib, json, os, pathlib, re, sys
source=sys.stdin.buffer.read().decode()
match=re.search(r'REQUEST_BYTES = base64\\.b64decode\\("([A-Za-z0-9+/=]+)"\\)', source)
if match is None: sys.exit(2)
request=json.loads(base64.b64decode(match.group(1)))
capture=pathlib.Path('""" + str(captures) + """') / (request['action'] + '.json')
capture.write_text(json.dumps({'argv':sys.argv[1:], 'source':source, 'request':request}))
with open(pathlib.Path('""" + str(captures) + """') / 'ssh-calls.txt','a') as calls:
 calls.write(request['action']+'\\n')
def h(value): return hashlib.sha256(value.encode()).hexdigest()
setup=request['action'] == 'setup'
result={
 'schema':'mknoon.sims.ios-payload-relay-remote-result.v1',
 'action':request['action'],
 'status':'seeded' if setup else 'cleared',
 'mutated':True,
 'removedCount':0 if setup else 1,
 'apnsPayloadSha256':request['apnsPayloadSha256'],
 'encryptedEnvelopeSha256':request['encryptedEnvelopeSha256'],
 'stagedEnvelopeSha256':request['stagedEnvelopeSha256'],
 'liveRelayRevisionSha256':h(request['expectedRelayRevision']),
 'liveRelaySha256':request['expectedRelaySha256'],
 'relayEntrySha256':h(request['entryId']+request['encryptedEnvelope']),
}
print(json.dumps(result, separators=(',',':'), sort_keys=True))
""",
            )

            environment = {
                **os.environ,
                "PATH": f"{fake_bin}:/usr/bin:/bin",
                "SIMS_CHILD_BUILDS_FORBIDDEN": "1",
                "SIMS_MANUAL_ACTIONS_FORBIDDEN": "1",
            }

            exposed_request = dict(request)
            exposed_request["expectedBody"] = (
                "fallback exposes " + request["expectedMessageText"]
            )
            _private(request_path, json.dumps(exposed_request))
            write_lifecycle("setup")
            rejected = subprocess.run(
                self._command(
                    action="setup",
                    receiver=receiver,
                    peer=peer,
                    request=request_path,
                    staging=staging_path,
                    payload=payload_path,
                    relay_key=relay_key,
                    run_id=run_id,
                    nonce=nonce,
                    apns_payload_sha256=payload_sha,
                    receiver_handoff_sha256=handoff_sha,
                    lifecycle=lifecycle_path,
                    output=root / "rejected-receipt.json",
                ),
                cwd=ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("exposes expectedMessageText", rejected.stderr)
            self.assertFalse((captures / "ssh-calls.txt").exists())
            _private(request_path, json.dumps(request))

            setup_output = root / "setup-receipt.json"
            setup_capture = captures / "setup.json"
            write_lifecycle("setup")
            setup = subprocess.run(
                self._command(
                    action="setup",
                    receiver=receiver,
                    peer=peer,
                    request=request_path,
                    staging=staging_path,
                    payload=payload_path,
                    relay_key=relay_key,
                    run_id=run_id,
                    nonce=nonce,
                    apns_payload_sha256=payload_sha,
                    receiver_handoff_sha256=handoff_sha,
                    lifecycle=lifecycle_path,
                    output=setup_output,
                ),
                cwd=ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(setup.returncode, 0, setup.stderr)
            setup_receipt = json.loads(setup_output.read_text())
            self.assertEqual(setup_receipt["status"], "seeded")
            self.assertTrue(setup_receipt["relayInboxSeeded"])
            self.assertEqual(setup_receipt["childBuildCount"], 0)
            self.assertRegex(setup_receipt["apnsPayloadSha256"], r"^[0-9a-f]{64}$")
            self.assertRegex(setup_receipt["encryptedEnvelopeSha256"], r"^[0-9a-f]{64}$")
            self.assertRegex(setup_receipt["relayEntrySha256"], r"^[0-9a-f]{64}$")
            self.assertEqual(setup_receipt["receiverHandoffSha256"], handoff_sha)

            capture = json.loads(setup_capture.read_text())
            argv_text = json.dumps(capture["argv"])
            self.assertNotIn(payload["ciphertext"], argv_text)
            self.assertNotIn(payload["kem"], argv_text)
            self.assertNotIn(payload["ciphertext"], capture["source"])
            self.assertEqual(capture["argv"][-4:], ["sudo", "-n", "python3", "-"])
            self.assertEqual(
                capture["request"]["entryId"],
                driver._stable_entry_id(run_id, nonce, peer),
            )
            envelope = json.loads(capture["request"]["encryptedEnvelope"])
            self.assertEqual(envelope["id"], payload["message_id"])
            self.assertEqual(envelope["senderPeerId"], sender)

            provider_receipt = root / "provider-receipt.json"
            provider = {
                "schema": driver.PROVIDER_RECEIPT_SCHEMA,
                "status": "accepted",
                "runId": run_id,
                "nonce": nonce,
                "receiverDeviceIdSha256": hashlib.sha256(receiver.encode()).hexdigest(),
                "requestSha256": hashlib.sha256(request_path.read_bytes()).hexdigest(),
                "apnsPayloadSha256": payload_sha,
                "receiverHandoffSha256": handoff_sha,
                "stagedEnvelopeSha256": setup_receipt["stagedEnvelopeSha256"],
            }
            _private(provider_receipt, json.dumps(provider))

            for action in ("cleanup", "rollback"):
                output = root / f"{action}-receipt.json"
                action_capture = captures / f"{action}.json"
                write_lifecycle(action)
                completed = subprocess.run(
                    self._command(
                        action=action,
                        receiver=receiver,
                        peer=peer,
                        request=request_path,
                        staging=staging_path,
                        payload=payload_path,
                        relay_key=relay_key,
                        run_id=run_id,
                        nonce=nonce,
                        apns_payload_sha256=payload_sha,
                        receiver_handoff_sha256=handoff_sha,
                        lifecycle=lifecycle_path,
                        output=output,
                        provider_receipt=provider_receipt if action == "cleanup" else None,
                    ),
                    cwd=ROOT,
                    env=environment,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(completed.returncode, 0, completed.stderr)
                receipt = json.loads(output.read_text())
                self.assertEqual(receipt["status"], "cleared")
                self.assertTrue(receipt["relayFixtureCleared"])
                self.assertEqual(receipt["receiverHandoffSha256"], handoff_sha)
                if action == "cleanup":
                    self.assertEqual(
                        receipt["providerReceiptSha256"],
                        hashlib.sha256(provider_receipt.read_bytes()).hexdigest(),
                    )

            ssh_calls = captures / "ssh-calls.txt"
            self.assertEqual(ssh_calls.read_text().splitlines(), ["setup", "cleanup", "rollback"])
            blocked_output = root / "blocked-receipt.json"
            write_lifecycle("cleanup")
            wrong_state = subprocess.run(
                self._command(
                    action="setup",
                    receiver=receiver,
                    peer=peer,
                    request=request_path,
                    staging=staging_path,
                    payload=payload_path,
                    relay_key=relay_key,
                    run_id=run_id,
                    nonce=nonce,
                    apns_payload_sha256=payload_sha,
                    receiver_handoff_sha256=handoff_sha,
                    lifecycle=lifecycle_path,
                    output=blocked_output,
                ),
                cwd=ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(wrong_state.returncode, 78, wrong_state.stderr)

            write_lifecycle("setup")
            wrong_payload_sha = subprocess.run(
                self._command(
                    action="setup",
                    receiver=receiver,
                    peer=peer,
                    request=request_path,
                    staging=staging_path,
                    payload=payload_path,
                    relay_key=relay_key,
                    run_id=run_id,
                    nonce=nonce,
                    apns_payload_sha256="0" * 64,
                    receiver_handoff_sha256=handoff_sha,
                    lifecycle=lifecycle_path,
                    output=blocked_output,
                ),
                cwd=ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(wrong_payload_sha.returncode, 78, wrong_payload_sha.stderr)
            self.assertEqual(ssh_calls.read_text().splitlines(), ["setup", "cleanup", "rollback"])
            self.assertFalse(blocked_output.exists())

            durable = "\n".join(
                [
                    setup.stdout,
                    setup.stderr,
                    setup_output.read_text(),
                    (root / "cleanup-receipt.json").read_text(),
                    (root / "rollback-receipt.json").read_text(),
                ]
            )
            self.assertNotIn(payload["ciphertext"], durable)
            self.assertNotIn(request["expectedMessageText"], durable)
            self.assertNotIn("fake-private-relay-key", durable)
            self.assertEqual(stat.S_IMODE(setup_output.stat().st_mode), 0o600)

    @staticmethod
    def _command(
        *,
        action: str,
        receiver: str,
        peer: str,
        request: Path,
        staging: Path,
        payload: Path,
        relay_key: Path,
        run_id: str,
        nonce: str,
        apns_payload_sha256: str,
        receiver_handoff_sha256: str,
        lifecycle: Path,
        output: Path,
        provider_receipt: Path | None = None,
    ) -> list[str]:
        command = [
            str(DRIVER),
            "--action",
            action,
            "--scenario",
            "payload_fast_path_ios_receiver",
            "--receiver",
            receiver,
            "--peer-device",
            peer,
            "--provider-request",
            str(request),
            "--staging-manifest",
            str(staging),
            "--relay-target",
            "fixture-user@relay.example.test",
            "--relay-key",
            str(relay_key),
            "--run-id",
            run_id,
            "--nonce",
            nonce,
            "--apns-payload",
            str(payload),
            "--apns-payload-sha256",
            apns_payload_sha256,
            "--receiver-handoff-sha256",
            receiver_handoff_sha256,
            "--lifecycle",
            str(lifecycle),
        ]
        if provider_receipt is not None:
            command.extend(["--provider-receipt", str(provider_receipt)])
        command.extend(["--output", str(output)])
        return command


if __name__ == "__main__":
    unittest.main()
