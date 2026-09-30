#!/bin/bash
# A4 frame check: pull the transcoder outputs made today, pick the one whose duration matches r25_motion (6 s),
# then compare it to the source frame by frame (pts order + per-frame SSIM).
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); FF=/opt/homebrew/bin/ffmpeg; FP=/opt/homebrew/bin/ffprobe
D=/sdcard/Android/data/$PKG/files/video_compress; OUT="$RUN/extra/a4"; mkdir -p "$OUT"
$ADB shell "ls -l --time-style=+%H:%M:%S $D" | tr -d '\r' | grep "VID_2026-09-28" | grep "\.mp4" | awk '{print $6, $5}' | sort > "$OUT/list.txt"
echo "today's outputs:"; cat "$OUT/list.txt"
SRC="$BETA/r2-5-media/r25_motion.mp4"
best=""
while read -r t sz; do :; done < /dev/null
$ADB shell "ls $D" | tr -d '\r' | grep "VID_2026-09-28.*\.mp4" | while read -r f; do
  $ADB pull "$D/$f" "$OUT/$f" > /dev/null 2>&1
  d=$($FP -v error -show_entries format=duration -of csv=p=0 "$OUT/$f"); wh=$($FP -v error -select_streams v -show_entries stream=width,height,nb_frames -of csv=p=0 "$OUT/$f")
  echo "$f duration=$d video=$wh"
done
F=$(ls -t "$OUT"/VID_2026-09-28*.mp4 2>/dev/null | while read -r f; do d=$($FP -v error -show_entries format=duration -of csv=p=0 "$f"); case "$d" in 5.9*|6.0*) echo "$f"; break;; esac; done)
echo "motion output: $F"
[ -n "$F" ] || exit 0
$FP -v error -select_streams v -show_entries frame=pts_time -of csv=p=0 "$F" > "$OUT/pts.txt"
echo "frames $(wc -l < "$OUT/pts.txt" | tr -d ' '), non-increasing pts steps: $(awk 'NR>1 && $1<=p {n++} {p=$1} END {print n+0}' "$OUT/pts.txt"), min step: $(awk 'NR>1 {s=$1-p; if (NR==2||s<m) m=s} {p=$1} END {printf "%.4f", m}' "$OUT/pts.txt")"
SW=$($FP -v error -select_streams v -show_entries stream=width,height -of csv=p=0 "$SRC")
$FF -hide_banner -loglevel error -i "$F" -i "$SRC" -lavfi "[0:v]scale=${SW%,*}:${SW#*,}:flags=bicubic,setpts=PTS-STARTPTS[a];[1:v]setpts=PTS-STARTPTS[b];[a][b]ssim=stats_file=$OUT/ssim.log" -f null - 2> "$OUT/ffmpeg.err"
awk '{for(i=1;i<=NF;i++) if($i ~ /^All:/){split($i,a,":"); v=a[2]; n++; s+=v; if(n==1||v<m)m=v; if(v<0.80)low++}} END {printf "per-frame SSIM vs source: frames=%d mean=%.3f min=%.3f below0.80=%d\n", n, s/n, m, low+0}' "$OUT/ssim.log"
# Same comparison with the output shifted by one frame either way: if frames were misordered, a shifted
# alignment would match some frames better than the straight one.
for off in -1 1; do
  $FF -hide_banner -loglevel error -i "$F" -i "$SRC" -lavfi "[0:v]scale=${SW%,*}:${SW#*,}:flags=bicubic,setpts=PTS-STARTPTS+(${off})/30/TB[a];[1:v]setpts=PTS-STARTPTS[b];[a][b]ssim=stats_file=$OUT/ssim_shift${off}.log" -f null - 2>/dev/null
  awk -v o=$off '{for(i=1;i<=NF;i++) if($i ~ /^All:/){split($i,a,":"); n++; s+=a[2]}} END {printf "shifted %+d frame: mean SSIM %.3f\n", o, s/n}' "$OUT/ssim_shift${off}.log"
done
