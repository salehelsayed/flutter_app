import json,sys
d=json.load(open(sys.argv[1]))
for s in d.get('snapshots',[]): print(s['capturedAt'], s['contentCardCount'], s['ids'], s['genericCardPresent'], s['workerCardPresent'])
print({k:v for k,v in d.items() if k!='snapshots'})
