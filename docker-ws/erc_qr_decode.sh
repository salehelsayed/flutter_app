#!/bin/bash
# Decode the QR in a simulator screenshot with CoreImage and write the payload to a private file (never printed).
#   erc_qr_decode.sh <png> <out.private.txt>
set -uo pipefail
IMG="$1"; OUT="$2"
S=$(mktemp -t qrdec).swift
cat > "$S" <<'SW'
import CoreImage
import Foundation
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let img = CIImage(contentsOf: url),
      let det = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else { exit(2) }
let msgs = det.features(in: img).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
guard let m = msgs.first else { exit(3) }
FileManager.default.createFile(atPath: CommandLine.arguments[2], contents: m.data(using: .utf8))
SW
swift "$S" "$IMG" "$OUT"; rc=$?
rm -f "$S"
[ $rc -eq 0 ] && echo "decoded bytes=$(wc -c < "$OUT" | tr -d ' ')" || echo "decode failed rc=$rc"
exit $rc
