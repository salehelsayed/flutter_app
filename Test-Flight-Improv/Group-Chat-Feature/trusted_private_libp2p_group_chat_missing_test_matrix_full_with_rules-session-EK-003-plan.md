# Session EK-003 Plan - Member Identity, Device Key, and Peer ID Binding

Status: prerequisite-blocked

## Run Mode

- Active mode: implementation-committed gap-closure.
- Source row: `EK-003` in `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`.
- Closure bar: this row can only become `Covered` when the repo proves member identity key, device key, and Peer ID binding for send, direct key updates, and membership events with concrete file and test evidence.
- Current outcome: keep the source row `Partial`; do not accept this session as closed.

## Scope

EK-003 asks for valid device binding to member identity and rejection of spoofed Peer ID or device-key mismatches. The current shipped implementation can prove member-level binding:

- Go PubSub validation rejects a claimed `senderId` that does not match the libp2p transport peer id.
- Go PubSub signature validation verifies the envelope against the stored member Ed25519 public key.
- Direct key-update receive now requires `message.from` to be a current group member with effective `rotateKeys` permission before key promotion or persistence.
- Fake-network same-user multi-device tests distinguish same-peer sibling devices from separate-human membership.

The row remains blocked because the production model does not yet have a first-class per-device identity or device key-package contract to validate.

## Device/Relay Proof Profile

- Profile: host raw-Go plus Flutter fake-network evidence is available; production per-device closure proof is unavailable because the product has no first-class device identity/key-package model.
- Live device/relay proof is not the blocker for this row. A real device run would exercise the current Peer ID contract, but it cannot prove a device-key mismatch without production device identity fields.
- Required missing product surfaces: per-device identity record, device key package, device-scoped membership/admission binding, per-device key distribution roster, offline replay/device-origin equivalence, and valid-device versus invalid-device test matrix.

## Evidence Collected

- `lib/features/groups/domain/models/group_member.dart` stores `peerId`, `publicKey`, and optional `mlKemPublicKey`, but no `deviceId`, device identity key, or device key-package field.
- `lib/features/groups/domain/models/group_invite_payload.dart` carries recipient Peer ID and invite policy, but no production device key package.
- `go-mknoon/internal/group_envelope.go` v3 `GroupEnvelope` carries `senderId`, `senderPublicKey`, signature, epoch, and encrypted payload, but no device identity or device key package.
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart` distributes rotated keys by member `peerId` and `mlKemPublicKey`, not by device-scoped recipient records.
- `lib/features/groups/application/group_key_update_listener.dart` now validates direct key updates against the sender's current group member state and `rotateKeys` permission, which closes the stale key-update authorization concern but not the missing per-device model.

## Commands Run

- `cd go-mknoon && go test ./node -run 'TestGroupTopicValidator_(TransportPeerIdMatchesEnvelopeSender|RejectsTransportPeerIdMismatch|BadSignature|SpoofedPublicKey|RejectsForgedMembershipSystemEventSignature)$' -v` passed.
- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'RP004'` passed (`+2`) after a prior parallel Flutter native-assets race.
- `flutter test --no-pub test/features/groups/integration/group_multi_device_convergence_test.dart --plain-name 'sibling device stays one member while new human admission adds a distinct member'` passed (`+1`).

## Blocker Classification

- Blocker class: `missing_first_class_device_identity_model`.
- Gap class: prerequisite-owned architecture/product gap, not a row-contained test-only or key-listener patch.
- Reason: closing EK-003 requires coordinated production schema and protocol work across group membership, invite/admission, Go v3 envelope or successor protocol, key distribution, replay equivalence, and device revocation/key-package semantics. Implementing only another host assertion around current Peer ID/member fields would not prove the row's device-key mismatch contract.

## Execution Verdict

`blocked`: EK-003 remains `Partial`. Current repo evidence proves the shipped member Peer ID plus stored Ed25519 key binding and direct key-update role authorization, but there is no production device identity/key-package surface to bind or reject a spoofed device key. Do not mark EK-003 `Covered` until that prerequisite model and valid/invalid device matrix exist.
