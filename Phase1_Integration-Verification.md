
### After Phase 1

```typescript
// Test: JS types + signing
import { UnsignedQRPayload } from './types/qr_payload';
import { signPayload } from './signing/sign_payload';

const payload: UnsignedQRPayload = {
  pk: 'test-pk',
  ns: 'test-ns',
  rv: '/dns4/test',
  ts: new Date().toISOString(),
};

const data = JSON.stringify(payload);
const sig = await signPayload(data, testPrivateKey);
console.log('Signature:', sig);
```
