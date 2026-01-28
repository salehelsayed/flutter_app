# Task Prompt: QA_XS_01 - Automated Smoke Test: QR Generation Flow (REAL runtime)

## Instructions for AI Agent

You are implementing an automated smoke test for a Flutter application. Follow the specification exactly. Output complete, working code that can be directly used.

---

## Global Context

```
Milestone: M2 – QR Code Generation

Smoke Test Requirements:
  - Must exercise REAL runtime boundaries (WebView JS bridge + SQLite)
  - NOT a unit test with mocks - this is integration/smoke testing
  - Runnable as a standalone Flutter app
  - Validates the complete QR generation flow end-to-end

Runtime Boundaries Tested:
  - WebView JS Bridge: Real JavaScript execution for signing
  - SQLite: Real database for identity storage/retrieval
  - Full integration of FL + JS layers
```

---

## Task Definition

```
[TASK QA_XS_01 – Automated Smoke Test: QR Generation Flow (REAL runtime)]

Owner: QA

Goal:
  Create an automated smoke test that validates the QR code generation flow
  using REAL runtime boundaries (WebView JS bridge + SQLite).

What to implement:
  - File: lib/smoke_test_m2_qr_generation.dart
  - Runnable via: flutter run -t lib/smoke_test_m2_qr_generation.dart
  - Exercises the complete flow with real dependencies
  - Prints "PASS" on success, "FAIL: <reason>" on failure

Validation Checks:
  1. QR payload is valid JSON (parseable)
  2. All required keys present: pk, ns, rv, sig, ts
  3. pk field matches identity's publicKey
  4. ns field matches identity's peerId
  5. rv field equals the constant rendezvous address
  6. sig field is base64 encoded and non-empty
  7. FAIL immediately if any stub markers detected (e.g., "STUB", "TODO", "MOCK")

Test Flow:
  1. Initialize real dependencies (SQLite, WebView bridge)
  2. Ensure identity exists (create if needed)
  3. Call buildQRPayload with real repo and real callJsSignPayload
  4. Parse the returned JSON
  5. Validate all fields against expected values
  6. Print result and exit

Deliverable:
  - File: lib/smoke_test_m2_qr_generation.dart
```

---

## Output Requirements

1. **File:** `lib/smoke_test_m2_qr_generation.dart`

2. **Must include:**
   - Standalone runnable main() function
   - Real SQLite repository initialization
   - Real WebView JS bridge initialization
   - Call to buildQRPayload with real dependencies
   - Comprehensive validation of QR payload
   - Clear PASS/FAIL output

3. **Implementation:**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:your_app/core/bridge/js_bridge_client.dart';
import 'package:your_app/core/database/database_helper.dart';
import 'package:your_app/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:your_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:your_app/features/qr_code/application/build_qr_payload_use_case.dart';

/// Expected rendezvous address constant
const String kRendezvousAddress =
    '/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g';

/// Smoke test for M2 QR Generation Flow
///
/// Run with: flutter run -t lib/smoke_test_m2_qr_generation.dart
///
/// This test exercises REAL runtime boundaries:
/// - WebView JS bridge (real JavaScript execution)
/// - SQLite database (real persistence)
///
/// Validation:
/// - Valid JSON output
/// - All keys present (pk, ns, rv, sig, ts)
/// - pk/ns match stored identity
/// - rv equals constant rendezvous address
/// - sig is base64 and non-empty
/// - FAIL on any stub markers
void main() {
  runApp(const SmokeTestApp());
}

class SmokeTestApp extends StatelessWidget {
  const SmokeTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'M2 QR Generation Smoke Test',
      home: const SmokeTestRunner(),
    );
  }
}

class SmokeTestRunner extends StatefulWidget {
  const SmokeTestRunner({super.key});

  @override
  State<SmokeTestRunner> createState() => _SmokeTestRunnerState();
}

class _SmokeTestRunnerState extends State<SmokeTestRunner> {
  String _status = 'Starting smoke test...';
  bool _passed = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _runSmokeTest();
  }

  Future<void> _runSmokeTest() async {
    try {
      // Step 1: Initialize REAL dependencies
      _updateStatus('Initializing real dependencies...');

      final db = await DatabaseHelper.instance.database;
      final IdentityRepository repo = IdentityRepositoryImpl(db);
      final JsBridgeClient bridgeClient = JsBridgeClient();

      // Wait for WebView bridge to be ready
      await bridgeClient.initialize();

      // Step 2: Ensure identity exists
      _updateStatus('Checking for existing identity...');

      var identity = await repo.loadIdentity();
      if (identity == null) {
        _updateStatus('No identity found. Creating new identity...');
        // This would trigger M1 flow - for smoke test, we expect identity to exist
        _fail('No identity found. Please run M1 identity initialization first.');
        return;
      }

      _updateStatus('Identity found: ${identity.peerId.substring(0, 20)}...');

      // Step 3: Call buildQRPayload with REAL dependencies
      _updateStatus('Calling buildQRPayload with real repo and bridge...');

      final (result, qrString) = await buildQRPayload(
        repo: repo,
        callJsSign: ({required dataToSign, required privateKey}) =>
            bridgeClient.callJsSignPayload(
              dataToSign: dataToSign,
              privateKey: privateKey,
            ),
      );

      // Step 4: Check result status
      if (result != BuildQRPayloadResult.success) {
        _fail('buildQRPayload returned non-success: $result');
        return;
      }

      if (qrString == null || qrString.isEmpty) {
        _fail('QR string is null or empty');
        return;
      }

      _updateStatus('QR payload generated, validating...');

      // Step 5: Validate - Check for stub markers FIRST
      final stubMarkers = ['STUB', 'TODO', 'MOCK', 'FAKE', 'PLACEHOLDER'];
      for (final marker in stubMarkers) {
        if (qrString.toUpperCase().contains(marker)) {
          _fail('Stub marker detected in QR payload: $marker');
          return;
        }
      }

      // Step 6: Validate - Parse JSON
      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(qrString) as Map<String, dynamic>;
      } catch (e) {
        _fail('QR payload is not valid JSON: $e');
        return;
      }

      // Step 7: Validate - All required keys present
      final requiredKeys = ['pk', 'ns', 'rv', 'sig', 'ts'];
      for (final key in requiredKeys) {
        if (!payload.containsKey(key)) {
          _fail('Missing required key: $key');
          return;
        }
      }

      // Step 8: Validate - pk matches identity's publicKey
      final pk = payload['pk'] as String?;
      if (pk == null || pk.isEmpty) {
        _fail('pk field is null or empty');
        return;
      }
      if (pk != identity.publicKey) {
        _fail('pk does not match identity publicKey. Expected: ${identity.publicKey}, Got: $pk');
        return;
      }

      // Step 9: Validate - ns matches identity's peerId
      final ns = payload['ns'] as String?;
      if (ns == null || ns.isEmpty) {
        _fail('ns field is null or empty');
        return;
      }
      if (ns != identity.peerId) {
        _fail('ns does not match identity peerId. Expected: ${identity.peerId}, Got: $ns');
        return;
      }

      // Step 10: Validate - rv equals constant
      final rv = payload['rv'] as String?;
      if (rv == null || rv.isEmpty) {
        _fail('rv field is null or empty');
        return;
      }
      if (rv != kRendezvousAddress) {
        _fail('rv does not match expected rendezvous address. Expected: $kRendezvousAddress, Got: $rv');
        return;
      }

      // Step 11: Validate - sig is base64 and non-empty
      final sig = payload['sig'] as String?;
      if (sig == null || sig.isEmpty) {
        _fail('sig field is null or empty');
        return;
      }

      // Check if sig is valid base64
      try {
        final decoded = base64Decode(sig);
        if (decoded.isEmpty) {
          _fail('sig decodes to empty bytes');
          return;
        }
      } catch (e) {
        _fail('sig is not valid base64: $e');
        return;
      }

      // Step 12: Validate - ts is present and looks like ISO-8601
      final ts = payload['ts'] as String?;
      if (ts == null || ts.isEmpty) {
        _fail('ts field is null or empty');
        return;
      }

      // Basic ISO-8601 format check
      try {
        DateTime.parse(ts);
      } catch (e) {
        _fail('ts is not a valid ISO-8601 timestamp: $ts');
        return;
      }

      // All validations passed!
      _pass();

    } catch (e, stack) {
      _fail('Unexpected exception: $e\n$stack');
    }
  }

  void _updateStatus(String status) {
    setState(() {
      _status = status;
    });
    print('[SMOKE TEST] $status');
  }

  void _pass() {
    setState(() {
      _status = 'PASS';
      _passed = true;
      _completed = true;
    });
    print('');
    print('========================================');
    print('PASS');
    print('========================================');
    print('');
    print('M2 QR Generation smoke test completed successfully.');
    print('All validations passed:');
    print('  - Valid JSON');
    print('  - All keys present (pk, ns, rv, sig, ts)');
    print('  - pk matches identity publicKey');
    print('  - ns matches identity peerId');
    print('  - rv equals rendezvous constant');
    print('  - sig is valid base64 and non-empty');
    print('  - ts is valid ISO-8601 timestamp');
    print('  - No stub markers detected');
  }

  void _fail(String reason) {
    setState(() {
      _status = 'FAIL: $reason';
      _passed = false;
      _completed = true;
    });
    print('');
    print('========================================');
    print('FAIL: $reason');
    print('========================================');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('M2 QR Generation Smoke Test'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_completed)
                const CircularProgressIndicator()
              else
                Icon(
                  _passed ? Icons.check_circle : Icons.error,
                  size: 64,
                  color: _passed ? Colors.green : Colors.red,
                ),
              const SizedBox(height: 24),
              Text(
                _status,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _completed
                      ? (_passed ? Colors.green : Colors.red)
                      : null,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              if (_completed)
                ElevatedButton(
                  onPressed: () => exit(_passed ? 0 : 1),
                  child: Text(_passed ? 'Exit (Success)' : 'Exit (Failure)'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

---

## How to Run

```bash
# Run the smoke test
flutter run -t lib/smoke_test_m2_qr_generation.dart

# Or on a specific device
flutter run -t lib/smoke_test_m2_qr_generation.dart -d <device-id>
```

---

## Validation Checklist

| Check | Description | PASS Criteria |
|-------|-------------|---------------|
| Valid JSON | QR payload parses as JSON | No parse errors |
| All keys present | pk, ns, rv, sig, ts | All 5 keys exist |
| pk matches | pk equals identity.publicKey | Exact string match |
| ns matches | ns equals identity.peerId | Exact string match |
| rv constant | rv equals rendezvous address | Exact string match |
| sig base64 | sig is valid base64 | Decodes without error |
| sig non-empty | sig has content | Decoded bytes.length > 0 |
| ts format | ts is ISO-8601 | DateTime.parse succeeds |
| No stubs | No STUB/TODO/MOCK markers | None found in payload |

---

## Expected Output

### On Success:
```
========================================
PASS
========================================

M2 QR Generation smoke test completed successfully.
All validations passed:
  - Valid JSON
  - All keys present (pk, ns, rv, sig, ts)
  - pk matches identity publicKey
  - ns matches identity peerId
  - rv equals rendezvous constant
  - sig is valid base64 and non-empty
  - ts is valid ISO-8601 timestamp
  - No stub markers detected
```

### On Failure:
```
========================================
FAIL: <specific reason>
========================================
```

---

## Prerequisites

Before running this smoke test:
1. M1 Identity Initialization must be complete (identity exists in SQLite)
2. M2 implementation complete (all tasks JS_XS_01 through FL_XS_05)
3. WebView bridge functional with real JavaScript runtime

---

## Begin Implementation

Output the complete Dart file for the automated smoke test.
