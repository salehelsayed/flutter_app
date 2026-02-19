
### After Phase 3

```dart
// Test: Use case end-to-end
final (result, qrString) = await buildQRPayload(
  repo: realRepo,
  callJsSign: realBridgeFunction,
);
if (result == BuildQRPayloadResult.success) {
  final payload = jsonDecode(qrString!);
  print('PK: ${payload['pk']}');
  print('NS: ${payload['ns']}');
  print('RV: ${payload['rv']}');
  print('TS: ${payload['ts']}');
  print('SIG: ${payload['sig']}');
}
```