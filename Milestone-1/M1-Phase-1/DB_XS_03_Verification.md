
### DB_XS_03 - dbUpsertIdentityRow()

- [ ] **Function signature:** `Future<void> dbUpsertIdentityRow(Database db, Map<String, Object?> row)`
- [ ] **Accepts correct keys:** `peer_id`, `public_key`, `private_key`, `mnemonic12`, `created_at`, `updated_at`
- [ ] **Always writes id=1:** Hardcoded or enforced
- [ ] **Upsert behavior:** INSERT OR REPLACE works correctly
- [ ] **Flow events:**
  - [ ] Emits `ID_DB_UPSERT_IDENTITY_START`
  - [ ] Emits `ID_DB_UPSERT_IDENTITY_SUCCESS`
- [ ] **Error handling:** DB errors surface as exceptions

```dart
// Quick test
await dbUpsertIdentityRow(db, {
  'peer_id': 'test',
  'public_key': 'test',
  'private_key': 'test',
  'mnemonic12': 'test',
  'created_at': '2025-01-01T00:00:00.000Z',
  'updated_at': '2025-01-01T00:00:00.000Z',
});
final row = await dbLoadIdentityRow(db);
assert(row != null);
assert(row!['peer_id'] == 'test');
```