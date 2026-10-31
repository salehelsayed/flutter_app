#!/bin/bash
# Read-only: list host processes for the plan 399 / direct-media fixtures (go test, relay, coturn).
ps -axo pid=,etime=,args= | grep -E 'go test|ProductionAudioCallDeviceFixture|turnserver|coturn|run_production_audio_call_sims|plan399' | grep -v grep | cut -c1-170
exit 0
