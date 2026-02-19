# Task Prompt: QA_XS_01 - Manual Test Script: QR Generation Flow

## Instructions for AI Agent

You are creating a QA test script. Follow the specification exactly.

---

## Task Definition

```
[TASK QA_XS_01 – Manual test script: QR generation flow]

Goal: 
  Write a manual test script that verifies the complete QR code generation flow.

Prerequisites:
  - M1 complete (identity exists in database)
  - M2 implementation complete
  - App running on device/emulator
  - QR code scanner available (another device or app)

Test Scenarios:
  1. Happy path: Generate and display QR code
  2. Verify QR payload contents
  3. Error path: No identity (optional if can clear DB)

Pass Criteria:
  - QR code displays correctly
  - QR code is scannable
  - Scanned payload contains all required fields
  - Flow events fire in expected sequence

Expected Flow Events (in order):
  - QR_FL_SCREEN_INIT
  - QR_FL_BUILD_PAYLOAD_START
  - QR_FL_BUILD_PAYLOAD_IDENTITY_FOUND
  - QR_FL_BUILD_PAYLOAD_SIGNING
  - QR_FL_BRIDGE_SIGN_REQUEST
  - QR_JS_BRIDGE_SIGN_RECEIVED
  - QR_JS_SIGN_PAYLOAD_START
  - QR_JS_SIGN_PAYLOAD_SUCCESS
  - QR_JS_BRIDGE_SIGN_SUCCESS
  - QR_FL_BRIDGE_SIGN_RESPONSE
  - QR_FL_BUILD_PAYLOAD_SUCCESS
  - QR_FL_SCREEN_DISPLAY

Deliverable:
  - File: docs/qa/QA_M2_XS_01_qr_generation.md
```

---

## Begin Implementation

Output the complete test script document.

---

# QA_M2_XS_01: QR Code Generation Test Script

## Overview

This test script verifies the M2 QR Code Generation feature, including payload building, signing, and display.

---

## Prerequisites

Before running these tests:

- [ ] M1 Identity Initialization is complete
- [ ] Identity exists in database (run M1 new identity or restore flow first)
- [ ] M2 implementation is complete (all tasks JS_XS_01 through FL_XS_05)
- [ ] App is running on device or emulator
- [ ] Debug console is visible for flow event verification
- [ ] QR code scanner available (another phone with camera app, or dedicated QR scanner app)

---

## Test Environment Setup

1. **Start the app** with debug logging enabled
2. **Open debug console** to monitor flow events
3. **Prepare QR scanner** on a separate device or use an online QR scanner tool
4. **Note the current identity's peerId** from database or previous test

---

## Test Case 1: Happy Path - Generate and Display QR Code

### Objective
Verify that a user with an existing identity can successfully generate and view their QR code.

### Steps

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Launch app | App opens, identity already exists |
| 2 | Navigate to QR code screen (e.g., tap "Show my QR Code" or profile menu) | QR screen navigation begins |
| 3 | Observe loading state | Loading indicator appears briefly |
| 4 | Wait for QR to load | QR code displays in center of screen |
| 5 | Verify screen elements | - Title shows "My QR Code"<br>- QR code is visible and clear<br>- Instruction text "Scan to connect with me" visible<br>- PeerID card shows truncated ID<br>- Back/close button present |
| 6 | Tap back/close button | Screen closes, returns to previous screen |

### Expected Flow Events (Console)

```
[FLOW] FL | QR_FL_SCREEN_INIT | {}
[FLOW] FL | QR_FL_BUILD_PAYLOAD_START | {}
[FLOW] FL | QR_FL_BUILD_PAYLOAD_IDENTITY_FOUND | { "peerId": "12D3KooW..." }
[FLOW] FL | QR_FL_BUILD_PAYLOAD_SIGNING | {}
[FLOW] FL | QR_FL_BRIDGE_SIGN_REQUEST | { "dataLength": ... }
[FLOW] JS | QR_JS_BRIDGE_SIGN_RECEIVED | { "dataLength": ... }
[FLOW] JS | QR_JS_SIGN_PAYLOAD_START | { "dataLength": ... }
[FLOW] JS | QR_JS_SIGN_PAYLOAD_SUCCESS | { "signatureLength": ... }
[FLOW] JS | QR_JS_BRIDGE_SIGN_SUCCESS | {}
[FLOW] FL | QR_FL_BRIDGE_SIGN_RESPONSE | { "ok": true }
[FLOW] FL | QR_FL_BUILD_PAYLOAD_SUCCESS | {}
[FLOW] FL | QR_FL_SCREEN_DISPLAY | {}
```

### Pass Criteria
- [ ] Loading indicator shown briefly
- [ ] QR code renders clearly
- [ ] All UI elements present
- [ ] Flow events match expected sequence
- [ ] No errors in console

---

## Test Case 2: Verify QR Payload Contents

### Objective
Verify that the QR code contains valid, correctly structured JSON payload with all required fields.

### Steps

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Display QR code | QR code is visible on screen |
| 2 | Scan QR code with another device | Scanner reads the QR successfully |
| 3 | Copy/view scanned content | JSON string is captured |
| 4 | Parse JSON content | Valid JSON, no parse errors |
| 5 | Verify `pk` field | Base64 string, matches identity's publicKey |
| 6 | Verify `ns` field | String, matches identity's peerId |
| 7 | Verify `rv` field | Equals `/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g` |
| 8 | Verify `ts` field | Valid ISO-8601 timestamp, recent |
| 9 | Verify `sig` field | Base64 string, non-empty |
| 10 | Verify key ordering | Keys are in alphabetical order: ns, pk, rv, sig, ts |

### Expected Payload Structure

```json
{
  "ns": "12D3KooWAbcdefghijklmnopqrstuvwxyz...",
  "pk": "SGVsbG8gV29ybGQhIFRoaXMgaXMgYSB0ZXN0Lg==",
  "rv": "/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g",
  "sig": "U2lnbmF0dXJlQmFzZTY0RW5jb2RlZFN0cmluZw==",
  "ts": "2025-01-22T15:30:00.000Z"
}
```

### Verification Checklist

- [ ] QR code scans successfully
- [ ] Content is valid JSON
- [ ] `pk` is non-empty base64 string
- [ ] `ns` matches identity peerId
- [ ] `rv` is exact rendezvous address
- [ ] `ts` is valid ISO-8601 timestamp
- [ ] `sig` is non-empty base64 string
- [ ] Keys are alphabetically ordered

---

## Test Case 3: Error Path - No Identity (Optional)

### Objective
Verify proper error handling when no identity exists.

### Prerequisites
- Ability to clear identity from database
- Or fresh app install without M1 completion

### Steps

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Clear identity from database (or use fresh install) | No identity row exists |
| 2 | Navigate to QR code screen | QR screen navigation begins |
| 3 | Observe loading state | Loading indicator appears briefly |
| 4 | Wait for error | Error screen displays |
| 5 | Verify error message | Shows "No identity found. Please create one first." or similar |
| 6 | Verify no retry button | Retry not shown (user needs to create identity) |
| 7 | Tap back button | Returns to previous screen |

### Expected Flow Events (Console)

```
[FLOW] FL | QR_FL_SCREEN_INIT | {}
[FLOW] FL | QR_FL_BUILD_PAYLOAD_START | {}
[FLOW] FL | QR_FL_BUILD_PAYLOAD_NO_IDENTITY | {}
[FLOW] FL | QR_FL_SCREEN_ERROR | { "reason": "noIdentity" }
```

### Pass Criteria
- [ ] Error screen displays (not crash)
- [ ] User-friendly error message shown
- [ ] Back navigation works
- [ ] Flow events indicate no identity

---

## Test Case 4: Re-generate QR Code

### Objective
Verify that QR code can be regenerated with new timestamp.

### Steps

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Navigate to QR screen | QR displays |
| 2 | Note the timestamp (`ts` field) by scanning | Record timestamp |
| 3 | Close QR screen | Screen closes |
| 4 | Wait 5 seconds | Time passes |
| 5 | Navigate to QR screen again | QR displays |
| 6 | Scan and note new timestamp | Timestamp is different (later) |
| 7 | Verify other fields unchanged | `pk`, `ns`, `rv` are same |

### Pass Criteria
- [ ] New QR generates successfully each time
- [ ] Timestamp updates on each generation
- [ ] Other identity fields remain consistent
- [ ] Signature is different (because data changed)

---

## Test Case 5: QR Code Readability

### Objective
Verify QR code is readable from various distances and angles.

### Steps

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Display QR code | QR visible |
| 2 | Scan from ~6 inches away | Scans successfully |
| 3 | Scan from ~12 inches away | Scans successfully |
| 4 | Scan at slight angle (~15°) | Scans successfully |
| 5 | Scan in low light | Scans successfully (may need more time) |
| 6 | Verify all scans produce same content | Identical JSON each time |

### Pass Criteria
- [ ] QR readable from reasonable distances
- [ ] QR readable at slight angles
- [ ] QR size is adequate (256px+ recommended)
- [ ] White background provides good contrast

---

## Test Results Summary

| Test Case | Status | Notes |
|-----------|--------|-------|
| TC1: Happy Path | ⬜ Pass / ⬜ Fail | |
| TC2: Payload Verification | ⬜ Pass / ⬜ Fail | |
| TC3: No Identity Error | ⬜ Pass / ⬜ Fail / ⬜ Skipped | |
| TC4: Re-generate | ⬜ Pass / ⬜ Fail | |
| TC5: Readability | ⬜ Pass / ⬜ Fail | |

---

## Issues Found

| Issue # | Description | Severity | Steps to Reproduce |
|---------|-------------|----------|-------------------|
| | | | |

---

## Sign-Off

- [ ] All mandatory test cases pass (TC1, TC2, TC4, TC5)
- [ ] Flow events match expected patterns
- [ ] No critical issues found
- [ ] QR codes are consistently scannable

**Tester:** _______________ 

**Date:** _______________

**M2 QR Generation: ⬜ APPROVED / ⬜ NEEDS FIXES**
