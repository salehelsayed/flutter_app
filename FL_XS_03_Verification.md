
### FL_XS_03 - buildQRPayloadUseCase()

- [ ] **Enum exists:**
  ```dart
  enum BuildQRPayloadResult { success, noIdentity, signingError }
  ```
- [ ] **Function signature:**
  ```dart
  Future<(BuildQRPayloadResult, String?)> buildQRPayload({
    required IdentityRepository repo,
    required Future<Map<String, dynamic>> Function(String, String) callJsSign,
  })
  ```
- [ ] **Uses RENDEZVOUS_ADDRESS constant:**
  - [ ] Constant defined: `/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`
  - [ ] Used in payload `rv` field
- [ ] **Logic flow:**
  - [ ] Loads identity from repo
  - [ ] Returns `noIdentity` if null
  - [ ] Builds unsigned payload with pk, ns, rv, ts
  - [ ] Serializes to canonical JSON (sorted keys)
  - [ ] Calls JS sign with data and privateKey
  - [ ] Returns `signingError` if signing fails
  - [ ] Adds signature to payload
  - [ ] Returns `success` with final JSON string
- [ ] **Flow events:**
  - [ ] Emits `QR_FL_BUILD_PAYLOAD_START`
  - [ ] Emits `QR_FL_BUILD_PAYLOAD_IDENTITY_LOADED` or `QR_FL_BUILD_PAYLOAD_NO_IDENTITY`
  - [ ] Emits `QR_FL_BUILD_PAYLOAD_SIGNING`
  - [ ] Emits `QR_FL_BUILD_PAYLOAD_SUCCESS` or `QR_FL_BUILD_PAYLOAD_ERROR`

```dart
// Quick test with mock
final result = await buildQRPayload(
  repo: mockRepo,
  callJsSign: (data, key) async => {'ok': true, 'signature': 'test-sig'},
);
assert(result.$1 == BuildQRPayloadResult.success);
assert(result.$2 != null);
final parsed = jsonDecode(result.$2!);
assert(parsed['sig'] == 'test-sig');
```
