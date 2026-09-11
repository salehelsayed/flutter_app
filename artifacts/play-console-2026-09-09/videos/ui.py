import base64,json,subprocess,time,urllib.request,urllib.error,xml.etree.ElementTree as ET
from pathlib import Path
BASE='http://127.0.0.1:4736'
ROOT=Path('/tmp/mknoon-play-videos')
DEVICES={'phone':'21071FDF600CSC','emulator':'emulator-5554'}
def request(method,path,data=None,timeout=90):
    body=None if data is None else json.dumps(data).encode()
    req=urllib.request.Request(BASE+path,data=body,method=method,headers={'Content-Type':'application/json'})
    try:
        with urllib.request.urlopen(req,timeout=timeout) as r: result=json.load(r)
    except urllib.error.HTTPError as e: raise RuntimeError(e.read().decode()[:2000])
    return result.get('value',result)
def create(role,port):
    caps={'platformName':'Android','appium:automationName':'UiAutomator2','appium:udid':DEVICES[role],'appium:systemPort':port,'appium:noReset':True,'appium:autoLaunch':False,'appium:dontStopAppOnReset':True,'appium:skipUnlock':True,'appium:newCommandTimeout':1800,'appium:adbExecTimeout':120000,'appium:uiautomator2ServerLaunchTimeout':120000,'appium:settings[waitForIdleTimeout]':0}
    value=request('POST','/session',{'capabilities':{'alwaysMatch':caps,'firstMatch':[{}]}},180)
    sid=value['sessionId']; (ROOT/f'{role}-session.txt').write_text(sid)
    return sid
def sid(role): return (ROOT/f'{role}-session.txt').read_text().strip()
def call(role,method,path,data=None): return request(method,f'/session/{sid(role)}'+path,data)
def adb(role,*args,timeout=60):
    return subprocess.run(['adb','-s',DEVICES[role],*args],capture_output=True,check=True,timeout=timeout).stdout
def source(role):
    xml=call(role,'GET','/source'); (ROOT/f'{role}-ui.xml').write_text(xml); return xml
def describe(role):
    root=ET.fromstring(source(role)); return [{k:e.attrib.get(k) for k in ['text','content-desc','resource-id','class','bounds','clickable']} for e in root.iter() if e.attrib.get('text') or e.attrib.get('content-desc')]
def find(role,value,using='accessibility id'): return call(role,'POST','/element',{'using':using,'value':value})['element-6066-11e4-a52e-4f735466cecf']
def click(role,value,using='accessibility id'):
    element=find(role,value,using); call(role,'POST',f'/element/{element}/click',{})
    with (ROOT/'commands.jsonl').open('a') as f:f.write(json.dumps({'time':time.time(),'role':role,'action':'click','locator':value})+'\n')
def fill(role,value,using='class name',locator='android.widget.EditText'):
    element=find(role,locator,using); call(role,'POST',f'/element/{element}/value',{'text':value})
def screenshot(role,name):
    path=ROOT/f'{name}.png'; path.write_bytes(base64.b64decode(call(role,'GET','/screenshot'))); return str(path)
def mobile(role,command,args=None): return call(role,'POST','/execute/sync',{'script':'mobile: '+command,'args':[args or {}]})
def visible(role,label): return any(r.get('content-desc')==label or r.get('text')==label for r in describe(role))
def wait_label(role,label,seconds=30):
    end=time.monotonic()+seconds
    while time.monotonic()<end:
        if visible(role,label): return
        time.sleep(.4)
    raise RuntimeError(f'{role}: timed out waiting for {label}')
def record_start(role,take):
    existing=adb(role,'shell','sh','-c',"'pidof screenrecord || true'").decode().strip()
    if existing: raise RuntimeError(f'Another screen recorder is active on {role}: {existing}')
    remote=f'/sdcard/mknoon-{take}-{role}.mp4'
    log=(ROOT/f'{take}-{role}-record.log').open('wb')
    process=subprocess.Popen(['adb','-s',DEVICES[role],'shell','screenrecord','--size','720x1600','--bit-rate','3000000','--time-limit','0',remote],stdout=log,stderr=log)
    time.sleep(.5)
    pid=adb(role,'shell','pidof','screenrecord').decode().strip()
    assert pid.isdigit(),pid
    return {'role':role,'take':take,'remote':remote,'pid':pid,'hostPid':process.pid,'startedAt':time.time()}
def record_stop(rec):
    role=rec['role']
    try: adb(role,'shell','kill','-2',rec['pid'])
    except Exception: pass
    time.sleep(.7)
    destination=ROOT/f"{rec['take']}-{role}.mp4"
    adb(role,'pull',rec['remote'],str(destination),timeout=120)
    rec['local']=str(destination); rec['finishedAt']=time.time(); return rec
