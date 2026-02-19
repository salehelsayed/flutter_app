# Milestone Orchestration Prompt

Use this prompt when asking scrum master and project engineer agents to create milestone task breakdowns.

---

## Prompt

```
You are creating a milestone orchestration for a Flutter/JS application. Your goal is to produce a set of task files that, when executed by coding agents, will result in a WORKING feature—not stubs, mocks, or placeholder code.

## Critical Rule: The "Runnable Output" Principle

Every milestone MUST end with code that actually runs and produces real output. If a feature involves:
- Cryptographic operations → real crypto libraries, real keys
- API calls → real endpoints or clearly marked test endpoints
- Database operations → real queries, real data persistence
- Cross-language communication → real runtime bridge, not simulated responses

**Anti-pattern to avoid:**
```dart
// "For now, we'll simulate responses for demo purposes"
return jsonEncode({'mnemonic': 'demo fake words here'});
```

**Required pattern:**
```dart
// Actual bridge call to real JS crypto library
final response = await webViewBridge.send(request);
```

---

## Required Task Categories

For every milestone, you MUST include tasks in ALL of these categories:

### 1. Implementation Tasks
The core functionality. Example: "Implement generateIdentity() function"

### 2. Integration/Glue Tasks
**CRITICAL: This is commonly missed.** When two systems need to communicate, you MUST create explicit tasks for:
- The runtime that connects them (WebView, FFI, channels, etc.)
- Build/bundle steps to prepare code for consumption
- Configuration (pubspec.yaml, package.json, assets)

Example tasks that MUST exist if Flutter calls JavaScript:
- "Implement WebView-based JS bridge runtime"
- "Create esbuild configuration to bundle JS for browser"
- "Configure Flutter assets to include JS bundle"
- "Add required npm dependencies (list them explicitly)"

### 3. Build Tasks
If code needs transformation, create explicit tasks:
- "Create build script for TypeScript → JavaScript bundle"
- "Configure polyfills for browser environment"
- "Set up asset pipeline in pubspec.yaml"

### 4. Automated Verification Tasks
**CRITICAL: Manual test documents are NOT sufficient.**

Every milestone MUST have at least one task that creates a runnable smoke test:
- Entry point: `lib/smoke_test_[feature].dart`
- Runs the actual code path
- Validates output quality (not just existence)
- Prints PASS/FAIL to console
- Can be run with: `flutter run -t lib/smoke_test_[feature].dart`

### 5. Stub Detection Tasks
Include explicit checks that fail on placeholder data:

```dart
// REQUIRED in verification
assert(!result.contains('demo'), 'Stub data detected');
assert(!result.contains('placeholder'), 'Stub data detected');
assert(!result.contains('TODO'), 'Incomplete implementation');
assert(isValidFormat(result), 'Invalid output format');
```

---

## Task File Template

Each task file MUST include:

```markdown
# Task: [ID] - [Name]

## Goal
[One sentence: what this task accomplishes]

## Prerequisites
[List task IDs that must be COMPLETE and VERIFIED before this task]
[If this task needs OUTPUT from another task, say so explicitly]
- Requires: [TASK_ID] complete
- Requires: Output from [TASK_ID] available at [path]

## What to Implement
[Specific deliverables with exact file paths]

## Technology/Approach
[CRITICAL: Specify HOW, not just WHAT]
- Package to use: [exact package name and version]
- Approach: [WebView/FFI/HTTP/etc.]
- Why this approach: [brief justification]

## Inputs
[What this code receives]

## Outputs
[What this code produces - be specific about format and validation]

## Verification Criteria
[How to verify this task is ACTUALLY working, not just "file exists"]
- [ ] Code compiles without errors
- [ ] Function produces output matching [specific format]
- [ ] Output passes validation: [specific checks]
- [ ] Integration test passes: [specific command to run]

## Anti-Patterns to Avoid
[Explicitly list what NOT to do]
- Do NOT use hardcoded/fake data
- Do NOT skip error handling
- Do NOT leave TODO comments

## Deliverables
[Exact file paths]
- lib/path/to/file.dart
```

---

## Required Orchestration Files

Your orchestration directory MUST contain:

```
[milestone]-orchestration/
├── GLOBAL_CONTEXT.md      # Shared types, contracts, schemas
├── execution-order.md      # Dependency graph and phases
├── verification-checklist.md  # Per-task verification
├── tasks/
│   ├── [LAYER]_XS_01.md   # Implementation tasks
│   ├── [LAYER]_XS_02.md
│   ├── ...
│   ├── BUILD_01.md        # Build/bundle tasks (REQUIRED)
│   ├── INT_01.md          # Integration wiring tasks (REQUIRED)
│   └── SMOKE_01.md        # Automated smoke test tasks (REQUIRED)
```

---

## Integration Task Requirements

When System A calls System B, you MUST have tasks for:

1. **Interface Definition** (both sides)
   - Task A: Define interface/contract on System A side
   - Task B: Define interface/contract on System B side

2. **Implementation** (both sides)
   - Task C: Implement logic on System A side
   - Task D: Implement logic on System B side

3. **Runtime Bridge** (THE GLUE - commonly missed!)
   - Task E: Implement the actual runtime that connects A to B
   - This includes: initialization, message passing, response handling

4. **Build Pipeline** (if code transformation needed)
   - Task F: Build/bundle System B code for System A consumption
   - Include: exact build commands, dependencies, output paths

5. **Integration Verification**
   - Task G: Test that A can actually call B and get real responses

### Example: Flutter ↔ JavaScript Integration

```
FL_XS_08: callJsGenerate() - calls bridge.send()     [Interface]
JS_XS_04: Handle identity.generate command            [Implementation]
FL_XS_16: WebView bridge runtime implementation       [THE GLUE] ← MUST EXIST
BUILD_01: Bundle JS with esbuild for browser          [Build] ← MUST EXIST
INT_01: Smoke test Flutter→JS→Real crypto→Response    [Verification] ← MUST EXIST
```

---

## Verification Checklist Requirements

Your verification-checklist.md MUST include for each task:

### Functional Checks
- [ ] Code compiles
- [ ] Function exists with correct signature
- [ ] Function produces output

### Quality Checks (CRITICAL - commonly missed)
- [ ] Output contains real data, not placeholders
- [ ] Output format matches specification exactly
- [ ] Cryptographic output passes validation (if applicable)
- [ ] Database queries return real persisted data (if applicable)

### Integration Checks
- [ ] End-to-end flow works with real runtime
- [ ] No "demo", "test", "placeholder", "TODO" in production output

### Runnable Verification
- [ ] Smoke test command: `flutter run -t lib/smoke_test_[feature].dart`
- [ ] Expected console output: [specific success message]
- [ ] Failure indicators: [what to look for if broken]

---

## Smoke Test Task Template

Every milestone MUST have at least one smoke test task:

```markdown
# Task: SMOKE_01 - Automated Smoke Test

## Goal
Create a runnable test that verifies the feature works end-to-end with real data.

## Prerequisites
- ALL implementation tasks complete
- ALL build tasks complete
- ALL integration tasks complete

## What to Implement
A standalone Flutter entry point that:
1. Initializes all required systems (DB, bridge, etc.)
2. Exercises the main user flow programmatically
3. Validates output quality (not just existence)
4. Prints clear PASS/FAIL status

## Stub Detection (REQUIRED)
The smoke test MUST include checks like:
```dart
// Detect placeholder data
if (result.contains('demo') || result.contains('placeholder')) {
  print('FAIL: Stub data detected');
  exit(1);
}

// Validate format
if (!isValidFormat(result)) {
  print('FAIL: Invalid output format');
  exit(1);
}

print('PASS: Real data validated');
```

## Run Command
```bash
flutter run -t lib/smoke_test_[feature].dart
```

## Pass Criteria
- Console shows "PASS" messages
- No "FAIL" messages
- No exceptions or errors
- Output matches expected format

## Deliverable
- lib/smoke_test_[feature].dart
```

---

## Common Gaps to Avoid

### Gap 1: Missing "Glue" Tasks
❌ Wrong: "Task A calls interface, Task B implements interface"
✅ Right: "Task A calls interface, Task B implements interface, Task C implements runtime that connects A to B"

### Gap 2: Missing Build Tasks
❌ Wrong: "JS code exists in src/"
✅ Right: "JS code exists in src/, BUILD_01 bundles it to assets/js/, pubspec.yaml configured"

### Gap 3: Manual-Only Verification
❌ Wrong: "QA_01: Manual test script document"
✅ Right: "QA_01: Manual test script, SMOKE_01: Automated runnable test"

### Gap 4: Assumed Dependencies
❌ Wrong: "Uses bip39 library"
✅ Right: "Uses bip39 library - add to package.json: bip39@^3.1.0"

### Gap 5: Interface Without Runtime
❌ Wrong: "abstract class JsBridge { Future<String> send(); }"
✅ Right: "abstract class JsBridge {...} AND WebViewJsBridge implements JsBridge with actual WebView"

---

## Final Checklist Before Submission

Before finalizing the orchestration, verify:

- [ ] Every cross-system communication has a runtime/glue task
- [ ] Every code transformation has a build task
- [ ] Every external dependency is explicitly listed with version
- [ ] At least one automated smoke test task exists
- [ ] Smoke test includes stub/placeholder detection
- [ ] Verification criteria include output quality, not just existence
- [ ] All file paths in tasks are explicit and complete
- [ ] No task assumes another task's output without explicit dependency

## Remember

**If the coding agent can complete all tasks and still have non-working code, your orchestration has gaps.**

The goal is: execute all tasks → run smoke test → see PASS → feature works.
```

---

## Usage

Provide this prompt to your scrum master / project engineer agent along with:
1. The feature requirements
2. The technology stack
3. Any existing code/architecture to integrate with

The agent should produce an orchestration directory following this structure that guarantees working output.
