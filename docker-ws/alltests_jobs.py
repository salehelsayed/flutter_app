import re,sys
t=open(sys.argv[1],errors='replace').read().replace('\r','')
m=re.search(r'^Registered(?:\s+\d+)?\s+jobs:',t,re.M); print('registered at',m.start() if m else None)
sec=t[m.end():] if m else t
ends=[i for i in (sec.find(x) for x in ['\nPending queue:','\nActive jobs:','\nRecently completed jobs:','\nConcurrency:']) if i>=0]
sec2=sec[:min(ends)] if ends else sec
hs=list(re.finditer(r'^\s*JOB\s+#?[^\s/]+/(\d+)(?::|\s+from\s+namespace\b[^\n]*:)',sec2,re.M))
print('headers',len(hs))
for i,h in enumerate(hs):
    b=sec2[h.start(): hs[i+1].start() if i+1<len(hs) else len(sec2)]
    tags=re.findall(r'#[A-Za-z]+Worker#?[^\s]*',b)
    print('JOB',h.group(1),'recovery' if '#HeadlessCanonicalRecoveryWorker#' in b else '', tags[:3])
    for key in ['Required constraints','Unsatisfied constraints','Satisfied constraints','Backoff','Earliest run time','Latest run time','Ready:','Enqueue time','Num failures','Last run heartbeat']:
        for l in b.splitlines():
            if key in l: print('   ',l.strip()[:200]); break
for key in ['mDeviceIdle','Doze','mReportedActive','Battery','charging','Power save','mLowPower','Thermal']:
    for mm in re.finditer(key, t):
        s=t.rfind('\n',0,mm.start()); print('dev:',t[s+1:t.find('\n',mm.start())].strip()[:200]); break
