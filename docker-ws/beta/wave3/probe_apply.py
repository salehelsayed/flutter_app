import json,os,sys,shutil
# Wave 3 negative probes.  probe_apply.py apply|restore <spec.json>
# apply: swap spec['old'] for spec['new'] in spec['file'] (under PROBE_ROOT, default the wave3-next worktree),
# keeping a byte copy (.orig) and the file's times (.times). restore: put bytes AND times back, so the
# queue's "recent source edit" check does not wait 5 minutes for a file whose content is unchanged.
root=os.environ.get('PROBE_ROOT','/workspace/.claude/worktrees/wave3-next').rstrip('/')
spec=json.load(open(sys.argv[2])); f=root+'/'+spec['file']
if sys.argv[1]=='apply':
    s=open(f).read(); assert s.count(spec['old'])==1, 'anchor'
    st=os.stat(f); open(sys.argv[2]+'.times','w').write(f'{st.st_atime_ns} {st.st_mtime_ns}')
    shutil.copy(f, sys.argv[2]+'.orig'); open(f,'w').write(s.replace(spec['old'],spec['new'])); print('probe applied')
else:
    shutil.copy(sys.argv[2]+'.orig', f)
    if os.path.exists(sys.argv[2]+'.times'):
        a,m=map(int,open(sys.argv[2]+'.times').read().split()); os.utime(f, ns=(a,m))
    print('restored')
