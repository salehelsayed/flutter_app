#!/bin/bash
# Usage: mapping_registrar_ctor.sh <mapping.txt>; prints whether each listed registrar keeps a no-arg constructor.
M="$1"
for c in com.google.mlkit.vision.barcode.internal.BarcodeRegistrar com.google.mlkit.common.internal.CommonComponentRegistrar com.google.mlkit.vision.common.internal.VisionCommonRegistrar com.google.firebase.messaging.FirebaseMessagingRegistrar; do
  if awk -v c="$c -> " 'index($0,c)==1{f=1;next} f&&/^[^ #]/{exit} f&&/void <init>\(\)/{found=1;exit} END{exit !found}' "$M"; then echo "$c ctor=KEPT"; else echo "$c ctor=MISSING"; fi
done
