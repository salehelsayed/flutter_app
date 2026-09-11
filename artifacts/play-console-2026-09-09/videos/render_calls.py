from pathlib import Path
import subprocess,json
p=Path('/Volumes/CrucialX9/flutter_app/artifacts/play-console-2026-09-09/videos')
f=Path('/tmp/mknoon-play-videos');font='/System/Library/Fonts/Supplemental/Arial.ttf'
s=json.loads((p/'calls-final-state.json').read_text());offset=s['captures'][1]['startedAt']-s['captures'][0]['startedAt']
filters=[]
# Hide the Wi-Fi name and unrelated notification cards, preserving the genuine mknoon card and system microphone indicator.
filters.append("[0:v]setpts=PTS-STARTPTS,setsar=1,drawbox=x=142:y=149:w=214:h=32:color=0x151b23:t=fill:enable='between(t,26.8,35.8)+gte(t,43.2)',drawbox=x=0:y=682:w=720:h=918:color=0x111722:t=fill:enable='between(t,26.8,35.8)',drawbox=x=0:y=602:w=720:h=998:color=0x111722:t=fill:enable='gte(t,43.2)'[phone]")
filters.append(f'[1:v]setpts=PTS-STARTPTS,setsar=1,tpad=start_duration={offset}:start_mode=clone[emulator]')
filters.append('[phone]pad=1600:1860:40:150:color=0x0d131e[canvas]')
filters.append('[canvas][emulator]overlay=840:150:eof_action=pass[paired]')
draw=[]
def txt(label,text,x,y,size=32,color='white',when=None):
 path=f/(label+'.txt');path.write_text(text)
 v=f'drawtext=fontfile={font}:textfile={path}:fontsize={size}:fontcolor={color}:x={x}:y={y}'
 if when:v+=f":enable='{when}'"
 draw.append(v)
txt('calls-title','mknoon | Background voice call',40,25,43)
txt('calls-phone','Pixel 6 | Physical Android phone',40,100,27,'0xb4c5dc')
txt('calls-emulator','Pixel 7 | Android emulator',840,100,27,'0xb4c5dc')
txt('calls-context','Real device capture | Android 17 | Installed build 111 (1.0.1)',40,1780,22,'0xb4c5dc')
captions=[(0,4,'1  Open a conversation with a QR-paired contact.'),(4,8.3,'2  Start a voice call. The receiving phone shows the incoming call.'),(8.3,14.5,'3  Answer the call and wait for both devices to connect.'),(14.5,19.6,'4  Both devices show Connected and the call timer.'),(19.6,24.8,'5  Mute and unmute the microphone during the live call.'),(24.8,30.4,'6  Press Home. The call continues while mknoon is in the background.'),(30.4,36.5,'7  Android shows Call in progress, Hang Up, and microphone use.'),(36.5,40.0,'8  Return to mknoon. The call timer has continued.'),(40.0,43.5,'9  End the call using the in-app End control.'),(43.5,48,'10  The ongoing-call card is gone. An earlier missed-call alert remains.')]
for i,(a,b,t) in enumerate(captions):txt('calls-step-'+str(i),t,40,1820,27,when=f'between(t,{a},{b})')
filters.append('[paired]'+','.join(draw)+'[out]')
script=f/'calls-filter.txt';script.write_text(';\n'.join(filters))
cmd=['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(p/'calls-final-phone.mp4'),'-i',str(p/'calls-final-emulator.mp4'),'-filter_complex_script',str(script),'-map','[out]','-t','47.65','-r','30','-c:v','libx264','-preset','fast','-crf','24','-threads','2','-pix_fmt','yuv420p','-movflags','+faststart',str(p/'mknoon-background-calls.mp4')]
subprocess.run(cmd,check=True)
print(p/'mknoon-background-calls.mp4')
