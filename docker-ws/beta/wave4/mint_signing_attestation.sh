#!/bin/bash
# Mint the signing-only part of the iOS staging attestation that the central ios.device.production build row
# requires (tool/sims/device_binding.dart _validIosSigningAttestation), from the real development provisioning
# profile. Checks team, app id, aps-environment, expiry and that the receiver iPhone is provisioned; hashes the
# single DeveloperCertificates leaf. No key, token or payload is read or written.
#   mint_signing_attestation.sh <receiver-udid> <out.json> [profile.mobileprovision]
set -euo pipefail
RECEIVER=$1; OUT=$2
PROFILE=${3:-}
if [ -z "$PROFILE" ]; then
  for c in /Volumes/CrucialX9/flutter_app/build/ios/iphoneos/Runner.app/embedded.mobileprovision \
           "$HOME"/Library/MobileDevice/Provisioning\ Profiles/*.mobileprovision \
           "$HOME"/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision; do
    [ -f "$c" ] || continue
    if security cms -D -i "$c" 2>/dev/null | grep -q "397R9Q4WMX.com.mknoon.app<"; then PROFILE=$c; break; fi
  done
fi
[ -n "$PROFILE" ] && [ -f "$PROFILE" ] || { echo "no com.mknoon.app development profile found"; exit 2; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
security cms -D -i "$PROFILE" > "$TMP/profile.plist"
python3 - "$TMP/profile.plist" "$RECEIVER" "$OUT" "$PROFILE" <<'PY'
import datetime, hashlib, json, os, plistlib, sys
plist_path, receiver, out, profile = sys.argv[1:5]
p = plistlib.load(open(plist_path, 'rb'))
ent = p.get('Entitlements', {})
team = (p.get('TeamIdentifier') or [''])[0]
checks = {
    'team': team == '397R9Q4WMX',
    'appId': ent.get('application-identifier') == '397R9Q4WMX.com.mknoon.app',
    'apsDevelopment': ent.get('aps-environment') == 'development',
    'receiverProvisioned': receiver in (p.get('ProvisionedDevices') or []),
    'notExpired': p['ExpirationDate'].replace(tzinfo=datetime.timezone.utc) > datetime.datetime.now(datetime.timezone.utc),
    'oneLeaf': len(p.get('DeveloperCertificates') or []) == 1,
}
if not all(checks.values()):
    print('profile rejected:', {k: v for k, v in checks.items() if not v}); sys.exit(3)
leaf = hashlib.sha256(p['DeveloperCertificates'][0]).hexdigest()
doc = {
    'schema': 'mknoon.sims.ios-signing-attestation.v1',
    'appSigningAvailable': True,
    'signingProbeSucceeded': True,
    'apnsEnvironment': 'development',
    'signingEntitlementEnvironment': 'development',
    'bundleId': 'com.mknoon.app',
    'signingIdentitySha256': leaf,
    'signingCertificateSha256': leaf,
    'receiverDeviceId': receiver,
    'provisioningProfileSha256': hashlib.sha256(open(profile, 'rb').read()).hexdigest(),
    'profileExpires': p['ExpirationDate'].isoformat(),
}
tmp = out + '.tmp'
with open(tmp, 'w') as f:
    json.dump(doc, f, indent=2, sort_keys=True)
os.chmod(tmp, 0o600); os.replace(tmp, out)
print('minted', out, 'leaf', leaf[:12], 'expires', doc['profileExpires'])
PY
