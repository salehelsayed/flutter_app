### DB_XS_01 - Identity Table Migration

- [ ] **File exists:** Migration file created at expected location
- [ ] **Syntax valid:** SQL syntax is correct
- [ ] **Idempotent:** Running twice doesn't error (CREATE TABLE IF NOT EXISTS)
- [ ] **Schema matches:** All columns match GLOBAL_CONTEXT specification:
  - [ ] `id INTEGER PRIMARY KEY`
  - [ ] `peer_id TEXT NOT NULL`
  - [ ] `public_key TEXT NOT NULL`
  - [ ] `private_key TEXT NOT NULL`
  - [ ] `mnemonic12 TEXT NOT NULL`
  - [ ] `created_at TEXT NOT NULL`
  - [ ] `updated_at TEXT NOT NULL`
- [ ] **Flow events:** Emits `ID_DB_IDENTITY_MIGRATION_START` and `ID_DB_IDENTITY_MIGRATION_SUCCESS`

```sql
-- Quick test: Run this after migration
SELECT sql FROM sqlite_master WHERE name = 'identity';
-- Should return the CREATE TABLE statement
```



