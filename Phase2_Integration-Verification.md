
### After Phase 2

```dart
// Test: Bridge round-trip
final response = await callJsSignPayload(
  dataToSign: '{"test":"data"}',
  privateKey: 'test-private-key-base64',
);
print(response); // {ok: true/false, ...}
```
