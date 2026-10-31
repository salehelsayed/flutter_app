#!/bin/bash
# Read-only: list object/group names and vertex bounds per object in the emulator virtual scene model.
SDK="$HOME/Library/Android/sdk"; R="$SDK/emulator/resources"
ls "$R" | head -30
awk '/^[og] /{n=$2} /^v /{if(!(n in mnx)){mnx[n]=$2;mxx[n]=$2;mny[n]=$3;mxy[n]=$3;mnz[n]=$4;mxz[n]=$4} if($2<mnx[n])mnx[n]=$2; if($2>mxx[n])mxx[n]=$2; if($3<mny[n])mny[n]=$3; if($3>mxy[n])mxy[n]=$3; if($4<mnz[n])mnz[n]=$4; if($4>mxz[n])mxz[n]=$4} END{for(n in mnx) printf "%s x[%.2f,%.2f] y[%.2f,%.2f] z[%.2f,%.2f]\n", n,mnx[n],mxx[n],mny[n],mxy[n],mnz[n],mxz[n]}' "$R/Toren1BD.obj" | sort | head -80
