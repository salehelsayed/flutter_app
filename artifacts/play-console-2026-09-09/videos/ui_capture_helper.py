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
