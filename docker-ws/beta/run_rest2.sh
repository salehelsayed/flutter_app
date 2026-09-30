#!/bin/bash
# Remaining scenarios, sequential. Results go to the run timeline + maestro dirs.
H="$(dirname "$0")"
. "$H/beta_env.sh"
RUN=$(current_run)
N=n4
N5=n5
# S06a: Pixel offline (app force-stopped), iPhone sends 3, Pixel relaunches and must get all 3
bash "$H/pair.sh" s06a_recv2 - relaunch_wait.yaml NONCE=$N P=OFFI
bash "$H/dump_ui.sh" s06a_recv2 android
# S06b: iPhone offline, Pixel sends 3, iPhone relaunches
bash "$H/pair.sh" s06b2_stop stop_app.yaml -
bash "$H/pair.sh" s06b2_send - send_many.yaml NONCE=$N5 P=OFFA
sleep 20
bash "$H/pair.sh" s06b2_recv relaunch_wait.yaml - NONCE=$N5 P=OFFA
bash "$H/dump_ui.sh" s06b2_recv ios
# S07: cold restart both, history kept, one message each way
bash "$H/pair.sh" s07_restart2 s07_restart.yaml s07_restart.yaml NONCE=$N
# S08: group
bash "$H/pair.sh" s08_group2 s08_group_ios.yaml s08_group_android.yaml NONCE=$N
echo "REST DONE $(date '+%H:%M:%S')" >> "$RUN/timeline.txt"
