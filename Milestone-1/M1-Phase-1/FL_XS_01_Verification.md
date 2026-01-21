### FL_XS_01 - IdentityModel

- [ ] **Class exists:** `IdentityModel` class defined
- [ ] **All fields present:**
  - [ ] `String peerId`
  - [ ] `String publicKey`
  - [ ] `String privateKey`
  - [ ] `String mnemonic12`
  - [ ] `String createdAt`
  - [ ] `String updatedAt`
- [ ] **Immutable:** All fields are `final`
- [ ] **fromJson works:** Factory constructor accepts `Map<String, dynamic>`
- [ ] **toJson works:** Returns `Map<String, dynamic>` with correct keys
- [ ] **Round-trip test passes:**

```dart
final json = {
  'peerId': '12D3KooW...',
  'publicKey': 'base64...',
  'privateKey': 'base64...',
  'mnemonic12': 'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
  'createdAt': '2025-01-01T00:00:00.000Z',
  'updatedAt': '2025-01-01T00:00:00.000Z',
};
final model = IdentityModel.fromJson(json);
final back = model.toJson();
assert(back['peerId'] == json['peerId']);
// ... all fields match
```