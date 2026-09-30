"""Read-only: format/prefix only of peerDeviceId in the iOS staging manifest and provider request (no full values)."""
import json, pathlib
d = pathlib.Path('/Volumes/CrucialX9/flutter_app/.codex-test-logs/all-tests-y227gs8x/ios-fixtures-metric-deployed')
for name in ('ios-staging-manifest.json', 'provider-request.json'):
    try:
        v = json.loads((d / name).read_text()).get('peerDeviceId')
        print(name, 'peerDeviceId prefix:', (v or '')[:6], 'len', len(v or ''), 'mtime', (d / name).stat().st_mtime)
    except Exception as e:
        print(name, 'err', type(e).__name__)
