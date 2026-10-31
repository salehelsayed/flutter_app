#!/bin/bash
# Encode a private payload file as a QR PNG with CoreImage (payload never printed).
#   host-run bash docker-ws/qr_encode_png.sh <payload.private.txt> <out.png>
set -uo pipefail
IN="$1"; OUT="$2"
S=$(mktemp -t qrenc).swift
cat > "$S" <<'SW'
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
let data = try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let f = CIFilter(name: "CIQRCodeGenerator")!
f.setValue(data, forKey: "inputMessage"); f.setValue("M", forKey: "inputCorrectionLevel")
let img = f.outputImage!.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
let ctx = CIContext()
let cg = ctx.createCGImage(img, from: img.extent)!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, cg, nil); exit(CGImageDestinationFinalize(dest) ? 0 : 4)
SW
swift "$S" "$IN" "$OUT"; rc=$?; rm -f "$S"
[ $rc -eq 0 ] && echo "encoded" || echo "encode failed rc=$rc"; exit $rc
