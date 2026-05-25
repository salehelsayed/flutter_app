# Group Sender Device Binding GSD-001 Plan

Status: executed-accepted

## Scope

Add a minimal native sender-device resolver for group messages and reactions. The resolver must prevent publishing envelopes that local config already proves remote validators will reject.

## Problem

`PublishGroupMessage`, `SendGroupMessageReliable`, and `PublishGroupReaction` currently allow missing device metadata to default to account/member identifiers. That is valid for legacy no-device members, but invalid for deviceful members because validators require an active device id, transport peer id, device signing public key, optional key package id, and a signature from that selected device.

## Closure Bar

- Legacy no-device group members still publish with existing account-level fallback.
- Deviceful members must resolve to an active local sender device before encrypt/sign/publish.
- If multiple active devices exist and no explicit device id is supplied, publish fails fast.
- If one active local device exists, metadata can default to that device.
- Wrong device public key, wrong key package id, wrong transport peer, or private key mismatch fails before PubSub publish is reported successful.
- Both message and reaction publish paths use the same resolver.

## Device/Relay Proof Profile

Host-only. This is pure Go node envelope construction/validation behavior and does not require Flutter devices, simulators, relay fixtures, or real-network proof.

## Tests To Add First

1. `TestGroupPublishDeviceBinding_DevicefulMissingExplicitDeviceFailsWhenAmbiguous`
2. `TestGroupPublishDeviceBinding_DevicefulSingleLocalDeviceDefaultsAndSigns`
3. `TestGroupPublishDeviceBinding_DevicefulWrongDevicePublicKeyFails`
4. `TestGroupReactionDeviceBinding_DevicefulMissingExplicitDeviceFailsWhenAmbiguous`
5. Existing reliable-send focused tests must remain green.

## Implementation Steps

1. Add a small `groupSenderDeviceBinding` struct and resolver in `pubsub.go`.
2. Resolve legacy no-device members to existing member-level fallback.
3. Resolve deviceful members by explicit `senderDeviceId`, or by the single active device whose `TransportPeerId` equals the local node peer id.
4. Reject ambiguous, unbound, revoked, mismatched transport, mismatched public key, or mismatched key package cases.
5. Pass the resolved binding into message/reaction envelope construction.
6. Verify the just-created signature with the selected device public key before returning the envelope.

## Exact Gates

```bash
cd go-mknoon && go test ./node -count=1 -run 'TestGroupPublishDeviceBinding|TestGroupReactionDeviceBinding|TestSendGroupMessageReliable'
cd go-mknoon && go test ./bridge -count=1 -run 'TestGroupPublish|TestGroupSendReliable'
git diff --check -- go-mknoon/node/pubsub.go go-mknoon/node/pubsub_test.go Test-Flight-Improv/Group-Chat-Feature/group-sender-device-binding-session-breakdown.md Test-Flight-Improv/Group-Chat-Feature/group-sender-device-binding-session-GSD-001-plan.md
```

## Scope Guard

Do not redesign group membership, invite admission, Flutter key storage, relay inbox, or push notifications. Do not require explicit device metadata for legacy no-device configs.

## Execution Progress

- 2026-05-23: Plan created from pipeline controller intake. Ready for RED tests.
- 2026-05-23: RED tests added for ambiguous deviceful sends, single-local-device defaulting/signing, wrong device public key rejection, and ambiguous reactions. Initial failures showed the old account-level defaults or late PubSub validation.
- 2026-05-23: Implemented minimal shared sender-device binding in `pubsub.go` for `PublishGroupMessage`, `SendGroupMessageReliable`, and `PublishGroupReaction`. The resolver preserves legacy no-device fallback, selects exactly one active local device when possible, rejects mismatched metadata, and verifies the signature against the selected device public key before returning an envelope.

## Verification

Passed:

```bash
cd go-mknoon && go test ./node -count=1 -run 'TestGroupPublishDeviceBinding|TestGroupReactionDeviceBinding'
cd go-mknoon && go test ./node -count=1 -run 'TestGroupPublishDeviceBinding|TestGroupReactionDeviceBinding|TestSendGroupMessageReliable'
cd go-mknoon && go test ./bridge -count=1 -run 'TestGroupPublish|TestGroupSendReliable'
git diff --check -- go-mknoon/node/pubsub.go go-mknoon/node/pubsub_test.go Test-Flight-Improv/Group-Chat-Feature/group-sender-device-binding-session-breakdown.md Test-Flight-Improv/Group-Chat-Feature/group-sender-device-binding-session-GSD-001-plan.md
scripts/ensure_go_ios_bindings.sh
scripts/ensure_go_macos_bindings.sh
bash scripts/ensure_go_android_bindings.sh
scripts/verify_gomobile_bindings.sh all
```

Not accepted as a gate result:

```bash
cd go-mknoon && go test ./node ./bridge -count=1
```

This broader package command was stopped after several minutes with no package output while the focused required gates had already passed.

## Closure Verdict

Accepted. The bug is real and now fixed in the native envelope construction paths with focused TDD coverage and refreshed gomobile artifacts.
