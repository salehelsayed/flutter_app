#!/usr/bin/env python3
"""Short-lived authenticated relay probes; all credential material stays in memory."""
import concurrent.futures
import datetime
import json
import re
import subprocess
from pathlib import Path

ROOT = Path('/Volumes/CrucialX9/flutter_app')
OUTPUT = Path('/tmp/beta-call-review-20260908/turn-tls-controlled.json')
REMOTE = '''import base64,hashlib,hmac,json,time
secret=None
for line in open('/etc/turnserver.conf'):
 line=line.strip()
 if line.startswith('static-auth-secret='):secret=line.split('=',1)[1].strip()
if not secret:raise SystemExit('No configured static auth secret')
username=str(int(time.time())+300)+':codex-tls-probe'
password=base64.b64encode(hmac.new(secret.encode(),username.encode(),hashlib.sha1).digest()).decode()
print(json.dumps({'username':username,'password':password}))
'''
credentials = json.loads(subprocess.check_output([
    'ssh', '-i', str(ROOT/'se.pem'), '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15',
    'ubuntu@13.60.15.36', 'sudo python3 -'], input=REMOTE, text=True))

cases = [
    ('IPv4', 'TLS', 20, False), ('IPv6', 'TLS', 20, False),
    ('IPv4', 'TLS', 200, False), ('IPv6', 'TLS', 200, False),
    ('IPv4', 'TLS', 20, True), ('IPv6', 'TLS', 20, True),
    ('IPv4', 'TCP', 20, False), ('IPv6', 'TCP', 20, False),
]

def run(case):
    family, transport, interval, send_indication = case
    host = '13.60.15.36' if family == 'IPv4' else '2a05:d016:c4d:7100:ec85:94ed:b90d:e20'
    flags = ['-v', '-y', '-c', '-n', '30', '-l', '100', '-z', str(interval), '-t']
    if transport == 'TLS': flags += ['-S', '-E', '/etc/ssl/cert.pem']
    if family == 'IPv6': flags += ['-x']
    if send_indication: flags += ['-s']
    flags += ['-p', '5349' if transport == 'TLS' else '3478']
    command = ['/opt/homebrew/bin/turnutils_uclient', *flags, '-u', credentials['username'], '-w', credentials['password'], host]
    start = datetime.datetime.now(datetime.timezone.utc).isoformat()
    try:
        proc = subprocess.run(command, capture_output=True, text=True, timeout=60)
        raw = proc.stdout + proc.stderr
        exit_code = proc.returncode
    except subprocess.TimeoutExpired:
        return {'family': family, 'transport': transport, 'intervalMs': interval, 'sendIndications': send_indication, 'timedOut': True}
    allowed = re.compile(r'(?:start_mclient: tot_send_msgs=\d+, tot_recv_msgs=\d+|Total lost packets \d+.*total send dropped \d+.*|response received: size=\d+|ERROR: Unknown message received of size: \d+|ERROR: received buffer have wrong length: \d+, must be \d+, len=\d+)')
    evidence = []
    for line in raw.splitlines():
        match = allowed.search(line)
        if match: evidence.append(match.group(0))
    totals = re.findall(r'start_mclient: tot_send_msgs=(\d+), tot_recv_msgs=(\d+)', raw)
    sent, received = map(int, totals[-1]) if totals else (None, None)
    result = {'family': family, 'transport': transport, 'intervalMs': interval, 'sendIndications': send_indication,
        'startedAt': start, 'finishedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'flagsWithoutCredentials': flags, 'exitCode': exit_code, 'sent': sent, 'received': received,
        'strictPass': exit_code == 0 and sent == 60 and received == 60, 'sanitizedEvidence': evidence}
    return result

with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(run, cases))
report = {'capturedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'clientVersion': 'coturn 4.18.0 macOS arm64',
    'serverVersion': 'coturn 4.6.1', 'expectedMessagesPerCase': 60, 'results': results,
    'limits': 'Payload is synthetic; credential material and complete client output are never persisted. Exit zero alone is not a pass. CA verification enabled for TLS; hostname verification was separately tested by the coordinating task.'}
OUTPUT.write_text(json.dumps(report, indent=2)+'\n')
for row in results:
    print(json.dumps({k:v for k,v in row.items() if k not in ('sanitizedEvidence','flagsWithoutCredentials')}),flush=True)
print('Sanitized report:', OUTPUT)
