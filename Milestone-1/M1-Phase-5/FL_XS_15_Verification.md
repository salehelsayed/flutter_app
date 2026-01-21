### FL_XS_15 - Startup Router

- [ ] **Widget exists:** `StartupRouter`
- [ ] **Calls decideStartupRoute:** On initialization
- [ ] **Routes correctly:**
  - [ ] `hasIdentity` → main app screen
  - [ ] `needsIdentity` → IdentityChoiceScreen
- [ ] **Shows loading:** While deciding
- [ ] **Flow events:**
  - [ ] Emits `ID_STARTUP_FLOW_BEGIN`
  - [ ] Emits `ID_STARTUP_ROUTE_MAIN` or `ID_STARTUP_ROUTE_ONBOARDING`
