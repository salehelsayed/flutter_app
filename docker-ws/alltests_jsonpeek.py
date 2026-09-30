import json,sys
d=json.load(open(sys.argv[1]))
def walk(o,p=''):
    if isinstance(o,dict):
        for k,v in o.items(): walk(v,p+'.'+k)
    elif isinstance(o,list):
        for i,v in enumerate(o[:40]): walk(v,f'{p}[{i}]')
    else:
        s=str(o)
        if 'plan' in p and 'selected' not in p and len(p)<30: return
        print(p, '=', s[:400])
walk(d)
