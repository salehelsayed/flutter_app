#!/usr/bin/env bash
# Reproducible reviewed Linux candidate; no deployment or native binding mutation.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
candidate_dir="$repo_root/build/app-diagnostics"
mkdir -p "$candidate_dir"
source_digest="$(python3 - "$repo_root" <<'PY'
import hashlib,pathlib,sys
root=pathlib.Path(sys.argv[1]);base=root/'go-relay-server';h=hashlib.sha256()
files=sorted([p for p in base.glob('*.go') if not p.name.endswith('_test.go')] + [base/name for name in ['go.mod','go.sum','call_diagnostics_schema_v1.json','app_diagnostics_schema_v1.json']])
for p in files:h.update(p.relative_to(base).as_posix().encode()+b'\0'+hashlib.sha256(p.read_bytes()).digest())
print(h.hexdigest())
PY
)"
(
 cd "$repo_root/go-relay-server"
 GOTOOLCHAIN=go1.25.0 CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags "-s -w -X main.callDiagnosticBuild=$source_digest" -o "$candidate_dir/relay-server" .
)
python3 - "$repo_root" "$source_digest" <<'PY'
import datetime,hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]);out=root/'build/app-diagnostics';binary=out/'relay-server'
m={'createdAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'toolchain':'go1.25.0','goos':'linux','goarch':'amd64','cgoEnabled':False,'sourceDigest':sys.argv[2],'buildStampField':'main.callDiagnosticBuild','binary':str(binary.relative_to(root)),'sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'bytes':binary.stat().st_size,'deploymentPerformed':False,'operator':{}}
for name in ['app_diagnostics.py','app_diagnostics_schema_v1.json','app_diagnostics_install.sh','app_diagnostics_monitor.py']:
 p=root/'docker-ws'/name;m['operator'][name]=hashlib.sha256(p.read_bytes()).hexdigest()
(out/'relay-candidate.json').write_text(json.dumps(m,indent=2)+'\n');print(json.dumps(m,indent=2))
PY
