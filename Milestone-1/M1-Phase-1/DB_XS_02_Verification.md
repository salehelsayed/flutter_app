### DB_XS_02 - dbLoadIdentityRow()

- [ ] **Function signature:** `Future<Map<String, Object?>?> dbLoadIdentityRow(Database db)`
- [ ] **Returns Map when row exists:** All column keys present
- [ ] **Returns null when no row:** Not an empty map, actual `null`
- [ ] **Column names correct:** Uses `peer_id`, `public_key`, etc. (snake_case)
- [ ] **Flow events:**
  - [ ] Emits `ID_DB_LOAD_IDENTITY_START`
  - [ ] Emits `ID_DB_LOAD_IDENTITY_FOUND` or `ID_DB_LOAD_IDENTITY_NOT_FOUND`
- [ ] **Error handling:** DB errors surface as exceptions

```dart
// Quick test
final row = await dbLoadIdentityRow(db);
print(row); // null on empty DB
```
