#!/bin/bash
# Remaining scenarios, sequential. Results go to the run timeline + maestro dirs.
H="$(dirname "$0")"
. "$H/beta_env.sh"
RUN=$(current_run)
N=n4
bash "$H/pair.sh" s05e_nock5 s05e_ios.yaml s05e_android.yaml
# S06a: Pixel offline (app force-stopped), iPhone sends 3, Pixel relaunches and must get all 3
bash "$H/pair.sh" s06a_stop - stop_app.yaml
bash "$H/pair.sh" s06a_send send_many.yaml - NONCE=$N P=OFFI
sleep 20
bash "$H/pair.sh" s06a_recv - relaunch_wait.yaml NONCE=$N P=OFFI
bash "$H/dump_ui.sh" s06a_recv android
# S06b: iPhone offline, Pixel sends 3, iPhone relaunches
bash "$H/pair.sh" s06b_stop stop_app.yaml -
bash "$H/pair.sh" s06b_send - send_many.yaml NONCE=$N P=OFFA
sleep 20
bash "$H/pair.sh" s06b_recv relaunch_wait.yaml - NONCE=$N P=OFFA
bash "$H/dump_ui.sh" s06b_recv ios
# S07: cold restart both, history kept, one message each way
bash "$H/pair.sh" s07_restart s07_restart.yaml s07_restart.yaml NONCE=$N
# S08: group
bash "$H/pair.sh" s08_group s08_group_ios.yaml s08_group_android.yaml NONCE=$N
echo "REST DONE $(date '+%H:%M:%S')" >> "$RUN/timeline.txt"
