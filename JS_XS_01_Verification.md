
### JS_XS_01 - QRPayloadJson Type Definition

- [ ] **File exists:** `core_lib_js/src/types/qr_payload.ts`
- [ ] **TypeScript typecheck command passes:**
  ```bash
  cd core_lib_js && npx tsc --noEmit
  ```
- [ ] **UnsignedQRPayload interface defined:**
  - [ ] `pk: string` (public key)
  - [ ] `ns: string` (namespace/peerId)
  - [ ] `rv: string` (rendezvous)
  - [ ] `ts: string` (timestamp)
- [ ] **SignedQRPayload interface defined:**
  - [ ] Extends UnsignedQRPayload
  - [ ] `sig: string` (signature)
- [ ] **Exported:** Both interfaces are exported
- [ ] **TypeScript compiles:** No type errors

```typescript
// Quick test
import { UnsignedQRPayload, SignedQRPayload } from './qr_payload';

const unsigned: UnsignedQRPayload = {
  pk: 'test',
  ns: 'test',
  rv: 'test',
  ts: new Date().toISOString(),
};

const signed: SignedQRPayload = {
  ...unsigned,
  sig: 'test-signature',
};
```