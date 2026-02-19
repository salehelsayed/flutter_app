
## QR Payload Validation

After generating a QR, scan it and verify:

- [ ] **Valid JSON:** Parses without error
- [ ] **pk field:** Base64 string, matches identity.publicKey
- [ ] **ns field:** String, matches identity.peerId
- [ ] **rv field:** Equals `/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`
- [ ] **ts field:** Valid ISO-8601 timestamp
- [ ] **sig field:** Base64 string, non-empty

```json
// Example valid payload
{
  "pk": "SGVsbG8gV29ybGQhIFRoaXMgaXMgYSB0ZXN0Lg==",
  "ns": "12D3KooWA1b2C3d4E5f6G7h8I9j0K1L2M3N4O5P6",
  "rv": "/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g",
  "ts": "2025-01-22T15:30:00.000Z",
  "sig": "U2lnbmF0dXJlQmFzZTY0RW5jb2RlZFN0cmluZw=="
}
```