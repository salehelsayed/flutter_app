"""Read-only: print lines [a,b] of device-logcat matching optional regex, excluding noisy regex."""
import sys, re
p='/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/proofs/notifications.android_payload_campaign/device-logcat.txt'
a,b=int(sys.argv[1]),int(sys.argv[2]); inc=re.compile(sys.argv[3]) if len(sys.argv)>3 and sys.argv[3] else None
exc=re.compile(sys.argv[4]) if len(sys.argv)>4 and sys.argv[4] else None; w=int(sys.argv[5]) if len(sys.argv)>5 else 240
n=0
with open(p,errors='replace') as f:
    for i,l in enumerate(f,1):
        if i<a: continue
        if i>b: break
        if inc and not inc.search(l): continue
        if exc and exc.search(l): continue
        print(i, l.rstrip()[:w]); n+=1
        if n>=150: break
print('total lines seen up to', i)
