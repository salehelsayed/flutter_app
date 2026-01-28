

### FL_XS_01 - QRPayloadModel

- [ ] **Class exists:** `QRPayloadModel`
- [ ] **All fields present:**
  - [ ] `String pk`
  - [ ] `String ns`
  - [ ] `String rv`
  - [ ] `String ts`
  - [ ] `String sig`
- [ ] **Immutable:** All fields are `final`
- [ ] **fromJson works:** Factory constructor accepts `Map<String, dynamic>`
- [ ] **toJson works:** Returns `Map<String, dynamic>` with correct keys
- [ ] **toJsonString works:** Returns canonical JSON string (sorted keys: ns, pk, rv, ts)
- [ ] **Canonical JSON verification:**
  - [ ] Keys are sorted alphabetically
  - [ ] No extra whitespace
  - [ ] Consistent ordering for signature verification
- [ ] **Round-trip test passes:**

```dart
final json = {
  'pk': 'public-key-base64',
  'ns': '12D3KooW...',
  'rv': '/dns4/mknoun.xyz/...',
  'ts': '2025-01-22T12:00:00.000Z',
  'sig': 'signature-base64',
};
final model = QRPayloadModel.fromJson(json);
final back = model.toJson();
assert(back['pk'] == json['pk']);
// ... all fields match
```