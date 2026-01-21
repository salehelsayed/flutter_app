### FL_XS_05 - decideStartupRoute()

- [ ] **Enum exists:** `enum StartupDecision { hasIdentity, needsIdentity }`
- [ ] **Function signature:** `Future<StartupDecision> decideStartupRoute(IdentityRepository repo)`
- [ ] **Correct logic:**
  - [ ] Calls `repo.loadIdentity()`
  - [ ] Returns `hasIdentity` when identity != null
  - [ ] Returns `needsIdentity` when identity == null
- [ ] **Flow events:**
  - [ ] Emits `ID_STARTUP_DECIDE_ROUTE_CALL`
  - [ ] Emits `ID_STARTUP_HAS_ID` or `ID_STARTUP_NEEDS_ID`
