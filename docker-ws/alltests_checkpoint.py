"""One wrapper checkpoint, with its exact manifest dependency closure.
Copy of the run root source047-localnetwork-checkpoint.py with the device config as optional argv[3]."""
import sys,json,subprocess,datetime
from pathlib import Path
run=Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run')
ids=sys.argv[1].split(',');label=sys.argv[2];device_config=sys.argv[3] if len(sys.argv)>3 else 'device-config-next.json';no_deps=len(sys.argv)>4 and sys.argv[4]=='nodeps'
plan=json.loads((run/'source047-final-full-plan/plan.json').read_text())
checks={x['id']:x for x in plan['selected']};selected=set()
def add(k):
 if k in selected:return
 assert k in checks,k
 selected.add(k)
 if no_deps:return
 for d in checks[k].get('depends_on',checks[k].get('dependencies',[])):add(d)
for k in ids:add(k)
output=run/label
assert not output.exists(),output
progress=run/'repair-progress.json'
def update(fn):
 d=json.loads(progress.read_text());fn(d);progress.write_text(json.dumps(d,indent=2)+'\n')
def running(d):
 d['active_checkpoint']=label
 for k in selected:d['checks'][k]['status']='running'
update(running)
command=['python3','scripts/mknoon_checks.py','full','--base',plan['baseline'],'--local','--device-config',str(run/device_config),'--jobs','2','--flutter-workers','2','--sims-jobs','2','--only',','.join(sorted(selected)),'--output',str(output)]
with (run/(label+'.wrapper.log')).open('w') as log:
 result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
report=output/'results.json'
if not report.exists():
 print('No completed report; retain interrupted attempt as unproven',flush=True)
 sys.exit(result.returncode or 1)
data=json.loads(report.read_text())
rows={x['id']:x for x in data['results']}
invalidated=any('Source/configuration changed during execution' in x for x in data.get('gaps',[]))
def complete(d):
 for k in selected:
  row=rows.get(k,{'status':'NOT RUN'})
  entry=d['checks'][k]
  entry.setdefault('attempts',[]).append({'report':str(report.relative_to(run)),'status':row['status'],'identity':data['identity'],'counts':row.get('counts'), 'checkpoint':row.get('checkpoint')})
  entry['status']='invalidated' if invalidated else ('passed-on-recorded-candidate' if row['status']=='PASS' else row['status'].lower())
  if row['status']=='PASS' and not invalidated and k in d['remaining_queue']:d['remaining_queue'].remove(k)
 d['active_checkpoint']=None
 d['current_checkpoint']=label
update(complete)
for k in sorted(selected):
 row=rows.get(k,{})
 print(json.dumps({'id':k,'status':row.get('status'),'counts':row.get('counts'),'checkpoint':row.get('checkpoint'),'report':str(report)}),flush=True)
sys.exit(result.returncode)
