import sys,time,pathlib,json,subprocess,base64,hashlib,traceback
sys.path.insert(0,'/tmp/mknoon-play-videos');import ui
p=pathlib.Path('/tmp/mknoon-play-videos');take='migration-final2';state={'events':[],'captures':[],'network':'ADB USB tunnel via Mac, sender limited to 128 KiB/s for visible transfer progress'};dns=None

def save():p.joinpath(take+'-state.json').write_text(json.dumps(state,indent=2))
def mark(s):state['events'].append({'at':time.time(),'action':s});save();print(s,flush=True)
def desc(role):return ui.describe(role)
try:
 ui.click('phone','Retry');time.sleep(.7)
 ui.click('emulator','Back');time.sleep(.7)
 for role in ['phone','emulator']:state['captures'].append(ui.record_start(role,take));save()
 mark('Old phone transfer entry and new phone welcome')
 time.sleep(2);ui.click('emulator','Move from old phone\nBring your existing account to this device');mark('New phone chooses Move from old phone')
 ui.wait_label('emulator','qr code',15);time.sleep(.8)
 qr=subprocess.run(['swift',str(p/'decode-qr.swift'),str(ui.screenshot('emulator','migration-final-qr-private'))],capture_output=True,text=True,check=True).stdout.strip()
 j=json.loads(qr);peer='account-migration-'+hashlib.sha256(j['sessionId'].encode()).hexdigest()[:32]
 dns=subprocess.Popen(['dns-sd','-P','mknoon-play-usb-final','_mknoon._tcp','local.','43218','mknoon-play-usb-final.local.','127.0.0.1','peerId='+peer],stdout=open(p/'migration-final-dns-private.log','w'),stderr=subprocess.STDOUT)
 time.sleep(5)
 ui.click('phone','Scan migration QR');time.sleep(.8);ui.click('phone','Paste migration QR');time.sleep(.6)
 ui.mobile('phone','setClipboard',{'content':base64.b64encode(qr.encode()).decode(),'contentType':'plaintext'})
 ui.click('phone','Paste migration QR from Clipboard');time.sleep(.5);ui.click('phone','Submit');time.sleep(.8)
 ui.wait_label('phone','Start transfer',10);mark('Matching confirmation codes shown on both devices');time.sleep(3)
 ui.click('phone','Start transfer');mark('User starts transfer')
 time.sleep(1)
 print('PHONE',json.dumps(desc('phone')),flush=True);# Defer emulator UI query until background evidence has been captured.
 for role in ['phone','emulator']:p.joinpath(take+'-'+role+'-services.txt').write_bytes(ui.adb(role,'shell','dumpsys','activity','services','com.mknoon.app'))
 ui.adb('phone','shell','input','keyevent','KEYCODE_HOME');mark('Old phone goes Home during transfer');time.sleep(2)
 ui.adb('phone','shell','input','swipe','540','40','540','1600','500');mark('Old phone notification shade opened')
 time.sleep(10)
 for _ in range(2):ui.adb('phone','shell','input','swipe','540','2050','540','750','500');time.sleep(.6)
 ui.screenshot('phone','migration-final-source-notification');print('PHONE SHADE',json.dumps(desc('phone')),flush=True)
 print('EMU PROGRESS',json.dumps(desc('emulator')),flush=True)
 mark('Transfer notification inspection')
 ui.adb('phone','shell','cmd','statusbar','collapse');ui.adb('phone','shell','am','start','-n','com.mknoon.app/.MainActivity');time.sleep(1);mark('Return to transfer in mknoon')
 deadline=time.time()+180
 while time.time()<deadline:
  a=desc('phone');b=desc('emulator');labels=[x.get('content-desc','') for x in a+b]
  print('STATES',json.dumps(labels),flush=True)
  if any(x and ('failed' in x.lower() or 'complete' in x.lower() or 'moved' in x.lower()) for x in labels):break
  time.sleep(3)
 state['finalUi']={'phone':desc('phone'),'emulator':desc('emulator')};mark('Final transfer state');time.sleep(4)
except Exception as e:
 state['error']=str(e);save();traceback.print_exc()
finally:
 for rec in state['captures']:
  try:ui.record_stop(rec)
  except Exception as e:print('Record stop',e,flush=True)
 if dns:dns.terminate()
 state['status']='finished';save()
