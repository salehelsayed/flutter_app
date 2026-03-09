---
description: Implement a specific phase from the Resilient libp2p Network Architecture TDD plan
user-invocable: true
---

# Phase Implementation Agent

You are implementing **Phase $ARGUMENTS** from the Resilient libp2p Network Architecture TDD plan.

## Step 1: Read the Plan

Read the full plan document:
```
Network-Arch/Resilient-libp2p-TDD-Plan.md
```

Extract ONLY the section for **Phase $ARGUMENTS**. Pay attention to:
- **Goal** — what this phase achieves
- **Production Scope** — which files to create or modify
- **RED Tests** — every test listed must be written
- **GREEN Implementation** — the production code changes
- **Exit Criteria** — what must be true when done
- **Commands** — test commands to verify

## Step 2: Understand the Codebase

Before writing any code, read the existing files listed in the phase's "Production Scope" section. Understand the current implementation before modifying it.

For Go code, also read:
- `go-mknoon/node/node.go` (core node structure)
- `go-mknoon/bridge/bridge.go` (bridge command dispatch)
- `go-mknoon/node/config.go` (node configuration)

For Flutter code, also read:
- `lib/core/services/p2p_service_impl.dart` (P2P service)
- `lib/core/bridge/go_bridge_client.dart` (bridge client)
- `test/shared/fakes/` (existing test fakes and helpers)

## Step 3: TDD Order — RED First

Write ALL tests listed in the RED Tests section BEFORE writing production code.

### Flutter test conventions:
- Use `flutter_test` package
- Group tests with `group()` and `test()` / `testWidgets()`
- Use existing fakes from `test/shared/fakes/` — extend them if needed, don't duplicate
- Key fakes: `FakeP2PNetwork`, `LifecycleBridge`, `FakeGroupPubSubNetwork`, `GroupTestUser`, `TestUser`
- Repositories use in-memory fakes: `InMemoryMessageRepository`, `InMemoryGroupRepository`, etc.
- Use `emitFlowEvent()` pattern for structured logging assertions if needed

### Go test conventions:
- Standard `testing` package
- Table-driven tests where appropriate
- Use `require` and `assert` from `testify` if already in deps
- Test file goes next to the source file: `foo.go` → `foo_test.go`

### Test naming:
- Follow the exact test names from the plan document
- Each test name in the plan corresponds to one `test()` or `func Test...()` call

## Step 4: GREEN Implementation

After ALL RED tests exist, implement the production code to make them pass.

### Flutter code conventions:
- **Clean Architecture**: DB helpers → Repositories → Use Cases → Wired/Screen
- **Use cases** are top-level functions, NOT classes
- **DI chain** flows through `main.dart → MyApp → StartupRouter → ...`
  - New dependencies must be threaded through the full chain
  - `QRScannerWired` also constructs `FeedWired`
  - `OrbitWired` also constructs `QRScannerWired` and `ConversationWired`
- **Bridge** abstract type used everywhere; `GoBridgeClient` is the only implementation
- **Command naming**: identity/crypto use dots (`identity.generate`), P2P uses colons (`node:start`, `peer:dial`)
- **Models**: `fromMap`/`toMap` for DB, `fromJson`/`toJson` for wire format
- **Listeners**: subscribe to `p2pService.messageStream`, filter `isIncoming`, broadcast via `StreamController`
- **UI**: pure `Screen` (StatelessWidget) + `Wired` (StatefulWidget) pair
- Do NOT add unnecessary comments, docstrings, or type annotations to code you didn't write

### Go code conventions:
- Go library lives in `go-mknoon/`
- Build with: `cd go-mknoon && PATH="$PATH:$(go env GOPATH)/bin" make all && cd ../ios && pod install`
- `flutter run` alone does NOT rebuild Go code
- gomobile symbols use Go package prefix (`Bridge*`)
- Relay server code is in `go-relay-server/`

## Step 5: Verify

Run the test commands specified in the phase's **Commands** section.

For Go changes:
```bash
cd go-mknoon && go build ./... 2>&1
```

For Flutter changes:
```bash
flutter analyze <changed-files>
```

Then run the phase-specific test commands.

## Step 6: Completion Report

When done, output a structured report:

```
## Phase $ARGUMENTS Implementation Report

### Files Created
- <list of new files>

### Files Modified
- <list of modified files with brief description of changes>

### Tests Written
- <list of test files and test names>

### Tests Passing
- <list of passing tests>

### Tests Failing
- <list of failing tests with reason>

### Exit Criteria Status
- [ ] <criterion 1> — PASS/FAIL
- [ ] <criterion 2> — PASS/FAIL
...

### Notes
- <any caveats, partial implementations, or decisions made>
```

## Critical Rules

1. **Do NOT skip tests.** Every test in the RED section must exist.
2. **Do NOT implement code from other phases.** Stay within your phase boundary.
3. **Do NOT break existing tests.** Run `flutter test test/core/services` and `flutter test test/core/lifecycle` to verify baseline.
4. **Do NOT modify the plan document.**
5. **Preserve backward compatibility** — additive changes only for bridge JSON, status fields, push events.
6. **Keep the DI chain intact** — if you add a new dependency, thread it properly through main.dart and all constructors that need it.
7. **Do NOT create documentation files** unless the plan explicitly calls for them.
8. **Go code changes require `go build ./...` to pass** before reporting completion.
