from pathlib import Path
import subprocess
p=Path('/Volumes/CrucialX9/flutter_app/artifacts/play-console-2026-09-09/videos');f=Path('/tmp/mknoon-play-videos');font='/System/Library/Fonts/Supplemental/Arial.ttf'
segments=[(0,4),(27.4,34.3),(41.8,45.3),(50,72),(76,78)]
filters=[]
shade="between(t,35,49)+between(t,74,85)"
phone=f"[0:v]setpts=PTS-STARTPTS,setsar=1,fps=30,drawbox=x=140:y=145:w=220:h=45:color=0x131b25:t=fill:enable='{shade}',drawbox=x=0:y=400:w=720:h=705:color=0x111722:t=fill:enable='{shade}',drawbox=x=0:y=1233:w=720:h=367:color=0x111722:t=fill:enable='{shade}'"
phone+=",drawbox=x=0:y=1105:w=720:h=128:color=0x111722:t=fill:enable='between(t,35,41.5)+between(t,79,85)'"
phone+=',split=5'+''.join(f'[p{i}]' for i in range(5));filters.append(phone)
filters.append("[1:v]setpts=PTS-STARTPTS,setsar=1,fps=30,drawbox=x=106:y=590:w=510:h=506:color=0x111722:t=fill:enable='between(t,4,36)',drawtext=fontfile="+font+":text='One-time QR hidden':fontsize=29:fontcolor=white:x=(w-text_w)/2:y=828:enable='between(t,4,36)',split=5"+''.join(f'[e{i}]' for i in range(5)))
for i,(a,b) in enumerate(segments):
 for role in ['p','e']:filters.append(f'[{role}{i}]trim=start={a}:end={b},setpts=PTS-STARTPTS[{role}{i}t]')
for role,idx in [('p',2),('e',3)]:
 filters.append(f'[{idx}:v]scale=720:1600,setpts=PTS-STARTPTS,setsar=1,fps=30,trim=duration=9,setpts=PTS-STARTPTS[{role}done]')
 filters.append(''.join(f'[{role}{i}t]' for i in range(5))+f'[{role}done]concat=n=6:v=1:a=0[{role}joined]')
filters.append('[pjoined]pad=1600:1860:40:150:color=0x0d131e[canvas]')
filters.append('[canvas][ejoined]overlay=840:150:eof_action=pass[paired]')
draw=[]
def txt(name,text,x,y,size=28,color='white',when=None):
 file=f/(name+'.txt');file.write_text(text)
 v=f'drawtext=fontfile={font}:textfile={file}:fontsize={size}:fontcolor={color}:x={x}:y={y}'
 if when:v+=f":enable='{when}'"
 draw.append(v)
txt('move-title','mknoon | Move account to a new phone',40,25,43)
txt('move-phone','Old phone | Pixel 6, physical Android',40,100,26,'0xb4c5dc')
txt('move-emulator','New phone | Pixel 7 Android emulator',840,100,26,'0xb4c5dc')
txt('move-context','Android 17 | Build 111 (1.0.1) | USB network tunnel at 128 KiB/s | Setup / idle gaps cut',40,1780,22,'0xb4c5dc')
steps=[(0,4,'1  Choose Move from old phone on the new device.'),(4,7.4,'2  Compare the confirmation code after pairing with the one-time QR.'),(7.4,10.9,'3  Tap Start transfer, then press Home on the old phone.'),(10.9,14.4,'4  Android shows Moving account while the app is in the background.'),(14.4,36.4,'5  Return to mknoon. The real account transfer advances on both devices.'),(36.4,38.4,'6  The account transfer continues with the old phone in the background.'),(38.4,47.4,'7  Completion (captured stills): Transfer complete and @pixel on the new phone.')]
for i,(a,b,t) in enumerate(steps):txt('move-step-'+str(i),t,40,1820,25,when=f'between(t,{a},{b})')
filters.append('[paired]'+','.join(draw)+'[out]')
script=f/'migration-filter.txt';script.write_text(';\n'.join(filters))
inputs=['migration-final2-phone.mp4','migration-final2-emulator.mp4','migration-complete-phone.png','migration-complete-emulator.png']
cmd=['ffmpeg','-hide_banner','-loglevel','error','-y']
for n in inputs:
 if n.endswith('.png'):cmd+=['-loop','1','-framerate','30','-t','9']
 cmd+=['-i',str(p/n)]
cmd+=['-filter_complex_script',str(script),'-map','[out]','-t','47.4','-r','30','-c:v','libx264','-preset','fast','-crf','24','-threads','2','-pix_fmt','yuv420p','-movflags','+faststart',str(p/'mknoon-account-transfer.mp4')]
subprocess.run(cmd,check=True)
print(p/'mknoon-account-transfer.mp4')
