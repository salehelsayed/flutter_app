import re,sys
t=open(sys.argv[1],errors='replace').read()
for k in sys.argv[2:]:
    ms=[m.start() for m in re.finditer(k,t)]
    print(k,len(ms), repr(t[max(0,ms[0]-80):ms[0]+120]) if ms else '')
