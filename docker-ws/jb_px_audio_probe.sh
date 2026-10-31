#!/bin/bash
# Batch-B: Pixel call-audio probe. Prints Mknoon (uid 11847) VOIP record/playback tracks from audio_flinger twice, 4 s apart,
# plus telecom call count. Container-side; needs ADB_SERVER_SOCKET.
#   bash docker-ws/jb_px_audio_probe.sh <label>
S=${PX_SERIAL:-21071FDF600CSC}; export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
for n in 1 2; do
  echo "--- $1 sample $n $(date -u +%T)"
  timeout 30 adb -s $S shell dumpsys media.audio_flinger | awk '
    /^(Output|Input|Mmap) thread/{th=$0; flag=""} /AUDIO_OUTPUT_FLAG_VOIP_RX|AUDIO_INPUT_FLAG_VOIP_TX/{flag=$NF}
    /Frames read:|Frames written:/{if(flag!="") print "  " flag " " $0}
    / 7559\/  11847 | [0-9]+\/  11847 /{if(flag!="") print "  " flag " track: " substr($0,1,170)}' | grep -vE 'AT::|removeTrack|^  [^ ]+ - ' | sort -u
  [ $n = 1 ] && sleep 4
done
echo "telecom calls: $(timeout 30 adb -s $S shell dumpsys telecom | grep -cE 'Call TC@|^ *Call id=')"
