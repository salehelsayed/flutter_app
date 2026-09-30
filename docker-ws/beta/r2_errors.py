#!/usr/bin/env python3
"""Round 2 error scan: group error/exception/crash lines from both phones' logs by
signature and by the scenario that was running (from timeline.txt).
Android: only the app's own processes count as app errors; other crashing processes are
listed once as ENVIRONMENT. Usage: r2_errors.py <run dir> [--samples N]"""
import re, sys, os, glob, collections

run = sys.argv[1]
samples = int(sys.argv[sys.argv.index('--samples') + 1]) if '--samples' in sys.argv else 2

wins = []
for line in open(os.path.join(run, 'timeline.txt'), errors='replace'):
    m = re.match(r'\[(\d\d:\d\d:\d\d)\] (start|end)\s+(\S+) (ios|android)', line)
    if m: wins.append((m.group(1), m.group(2), m.group(3)))
def scenario_at(hms):
    cur = '-'
    for t, kind, label in wins:
        if t > hms: break
        if kind == 'start': cur = label
    return cur

FAILWORD = re.compile(r'(FAIL|FAILED|FAILURE|ERROR|EXCEPTION|TIMEOUT|TIMED_OUT|REJECT|REJECTED|REFUSED|DROPPED|ABORT|ABORTED|CORRUPT|DENIED|CRASH)')
NEUTRAL_END = re.compile(r'_(BEGIN|START|STARTED|NONE|TIMING|DONE|SUCCESS|SKIP|SKIPPED|REQUEST|RESPONSE|COUNT)$')
EVENT = re.compile(r'"event":"([A-Z0-9_]+)"')
FLUTTER_EXC = re.compile(r'EXCEPTION CAUGHT BY|Unhandled Exception|RenderFlex overflowed|overflowed by|setState\(\) called after dispose|Null check operator|Bad state:|is not a subtype of|Looking up a deactivated widget|Another exception was thrown|PlatformException|MissingPluginException|StateError|RangeError|FormatException')
APP_FATAL = re.compile(r'FATAL EXCEPTION|ANR in com\.mknoon|Process: com\.mknoon|Process com\.mknoon[^ ]* \(pid \d+\) has died|Fatal signal|Abort message|am_crash|am_anr')
IGNORE = re.compile(r'peer:ping|remoteIce|iceCandidate|Maestro|uiautomator|dev\.mobile\.maestro')

def norm(s):
    s = re.sub(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '<uuid>', s)
    s = re.sub(r'12D3KooW[A-Za-z0-9]+', '<peer>', s)
    s = re.sub(r'\d{4}-\d\d-\d\dT[\d:.]+Z', '<ts>', s)
    s = re.sub(r'\b\d+(\.\d+)?\b', 'N', s)
    return s[:170]

class Acc:
    def __init__(self): self.sig = collections.OrderedDict(); self.n = 0
    def add(self, sig, hms, line):
        e = self.sig.setdefault(sig, {'n': 0, 'first': hms, 'last': hms, 'scn': collections.Counter(), 'ex': []})
        e['n'] += 1; e['last'] = hms; e['scn'][scenario_at(hms)] += 1
        if len(e['ex']) < samples: e['ex'].append(line.strip()[:320])
        self.n += 1
    def dump(self, title):
        print(f'\n##### {title}  ({self.n} lines, {len(self.sig)} signatures)')
        for sig, e in sorted(self.sig.items(), key=lambda kv: -kv[1]['n']):
            scns = ', '.join(f'{k}×{v}' for k, v in e['scn'].most_common(5))
            print(f"- [{e['n']}] {sig}\n    {e['first']}..{e['last']}  in: {scns}")
            for x in e['ex']: print(f'      > {x}')

def scan_android(path):
    ts = re.compile(r'^\d\d-\d\d (\d\d:\d\d:\d\d)\.\d+\s+(\d+)\s+(\d+)\s+([VDIWEF])\s+(.*?):')
    app_pids = set()
    with open(path, errors='replace') as fh:
        for line in fh:
            m = ts.match(line)
            if m and (' flutter ' in line or 'Mknoon' in m.group(5) or 'mknoon' in line.split(':', 3)[-1][:80]):
                if ' flutter ' in line or m.group(5).startswith(('Mknoon', 'GoLog', 'mknoon')): app_pids.add(m.group(2))
    app, env, flow = Acc(), Acc(), Acc()
    env_cmd = collections.Counter()
    with open(path, errors='replace') as fh:
        for line in fh:
            m = ts.match(line)
            if not m or IGNORE.search(line): continue
            hms, pid, lvl, tag = m.group(1), m.group(2), m.group(4), m.group(5).strip()
            c = re.search(r'Cmdline: (\S+)', line)
            if c: env_cmd[c.group(1)] += 1; continue
            ev = EVENT.search(line)
            if ev:
                name = ev.group(1)
                if FAILWORD.search(name) and not NEUTRAL_END.search(name):
                    flow.add(f'FLOW {name}', hms, line)
                continue
            if FLUTTER_EXC.search(line) and (pid in app_pids or 'flutter' in tag):
                app.add('FLUTTER ' + norm(line[FLUTTER_EXC.search(line).start():]), hms, line); continue
            if APP_FATAL.search(line):
                if 'com.mknoon' in line or pid in app_pids: app.add('FATAL ' + norm(line[APP_FATAL.search(line).start():]), hms, line)
                continue
            if re.search(r' E flutter\s*:\s*(#\d+\s|<asynchronous suspension>|$)', line.rstrip('\n') + ('' if line.strip() else '')):
                continue  # stack frames / blank lines belong to the exception above
            if lvl in 'EF' and pid in app_pids:
                app.add(f'{lvl} {tag}: ' + norm(line.split(':', 3)[-1] if line.count(':') >= 3 else line), hms, line)
    print(f'\n########## ANDROID {os.path.basename(path)}  app pids: {sorted(app_pids)}')
    app.dump('ANDROID app errors (E/F level from app pids, Flutter exceptions, app crashes/ANRs)')
    flow.dump('ANDROID app FLOW events with failure words')
    print('\n##### ANDROID environment: crashing system processes (tombstone Cmdline counts)')
    for k, v in env_cmd.most_common(): print(f'- [{v}] {k}')

def scan_ios(paths):
    ts = re.compile(r'^\d{4}-\d\d-\d\d (\d\d:\d\d:\d\d)\.\d+\s+(\w+)\s+Runner')
    app, flow = Acc(), Acc()
    for path in paths:
        with open(path, errors='replace') as fh:
            for line in fh:
                m = ts.match(line)
                if not m or IGNORE.search(line) or 'com.apple.dt.xctest' in line: continue
                hms, lvl = m.group(1), m.group(2)
                ev = EVENT.search(line)
                if ev:
                    name = ev.group(1)
                    if FAILWORD.search(name) and not NEUTRAL_END.search(name): flow.add(f'FLOW {name}', hms, line)
                    continue
                if FLUTTER_EXC.search(line):
                    app.add('FLUTTER ' + norm(line[FLUTTER_EXC.search(line).start():]), hms, line); continue
                if lvl in ('E', 'Er', 'F', 'Ft') or re.search(r'\bfault\b|\berror\b', line[:60]):
                    body = line.split(']', 1)[-1] if ']' in line[:120] else line
                    app.add(f'{lvl} ' + norm(body), hms, line)
    print(f'\n########## IPHONE {", ".join(os.path.basename(p) for p in paths)}')
    app.dump('IPHONE app errors (error/fault level, Flutter exceptions)')
    flow.dump('IPHONE app FLOW events with failure words')

for p in sorted(glob.glob(os.path.join(run, 'android_logcat_live*.txt'))): scan_android(p)
ios = sorted(glob.glob(os.path.join(run, 'ios_log_*.txt')))
if ios: scan_ios(ios)
