package main

import (
 "context"
 "encoding/json"
 "strings"
 "testing"
 "time"

 "github.com/alicebob/miniredis/v2"
 "github.com/redis/go-redis/v9"
)

func TestStickerMetricsExactRetryRestartAndPrivacy(t *testing.T) {
 server := miniredis.RunT(t)
 client := redis.NewClient(&redis.Options{Addr:server.Addr()}); defer client.Close()
 now := time.Date(2026,11,9,12,0,0,0,time.UTC)
 m := newStickerMetrics(client,"synthetic:",func() time.Time{return now})
 raw := []byte(`{"action":"sticker_usage_v1","day":"2026-11-08","nonce":"7b719404-d2bb-4d98-b3b6-b7be5d8186f1","counts":{"orbit_crew.planet.hello":3,"orbit_crew.planet.love":2}}`)
 for i:=0;i<2;i++ { if r:=m.report(raw,"PRIVATE_PEER_ID");r["accepted"]!=true {t.Fatalf("not accepted: %v",r)} }
 restarted := newStickerMetrics(client,"synthetic:",func() time.Time{return now})
 if r:=restarted.report(raw,"PRIVATE_PEER_ID");r["accepted"]!=true {t.Fatal(r)}
 values,err:=client.HGetAll(context.Background(),"synthetic:sticker:day:2026-11-08").Result()
 if err!=nil || values["total"]!="5" || values["p:orbit_crew"]!="5" || values["s:orbit_crew.planet.hello"]!="3" {t.Fatalf("wrong exact totals %v %v",values,err)}
 for _,k:=range server.Keys() { if strings.Contains(k,"PRIVATE") || strings.Contains(server.Dump(),"PRIVATE") {t.Fatal("peer stored")}}
 if ttl:=server.TTL("synthetic:sticker:nonce:7b719404-d2bb-4d98-b3b6-b7be5d8186f1");ttl!=72*time.Hour {t.Fatalf("nonce TTL %v",ttl)}
 server.FastForward(29*24*time.Hour)
 if len(server.Keys())!=0 {t.Fatal("expired metrics retained")}
}

func TestStickerMetricsValidateBeforeMutation(t *testing.T) {
 server:=miniredis.RunT(t);client:=redis.NewClient(&redis.Options{Addr:server.Addr()});defer client.Close()
 now:=time.Date(2026,11,9,12,0,0,0,time.UTC)
 m:=newStickerMetrics(client,"test:",func()time.Time{return now})
 good:=map[string]any{"action":"sticker_usage_v1","day":"2026-11-08","nonce":"7b719404-d2bb-4d98-b3b6-b7be5d8186f1","counts":map[string]int{"orbit_crew.planet.hello":1}}
 for _,change:=range []func(map[string]any){
 func(r map[string]any){r["peerId"]="private"},
 func(r map[string]any){r["nonce"]="device"},
 func(r map[string]any){r["day"]="2026-11-09"},
 func(r map[string]any){r["day"]="2026-11-05"},
 func(r map[string]any){r["counts"]=map[string]int{"private.sticker.id":1}},
 func(r map[string]any){r["counts"]=map[string]int{"orbit_crew.planet.hello":1001}},
 func(r map[string]any){r["counts"]=map[string]int{"orbit_crew.planet.hello":-1}},
 } {r:=map[string]any{};for k,v:=range good {r[k]=v};change(r);raw,_:=json.Marshal(r);if m.report(raw,"actor")["accepted"]==true {t.Fatal("invalid report accepted")}}
 if len(server.Keys())!=0 {t.Fatal("invalid report mutated store")}
}

func TestStickerMetricsRateLimitAndUnavailable(t *testing.T) {
 server:=miniredis.RunT(t);client:=redis.NewClient(&redis.Options{Addr:server.Addr()});defer client.Close()
 now:=time.Date(2026,11,9,12,0,0,0,time.UTC)
 m:=newStickerMetrics(client,"test:",func()time.Time{return now})
 raw:=[]byte(`{"action":"sticker_usage_v1","day":"2026-11-08","nonce":"7b719404-d2bb-4d98-b3b6-b7be5d8186f1","counts":{"orbit_crew.planet.hello":1}}`)
 limited:=false
 for i:=0;i<100;i++ {if m.report(raw,"actor")["reason"]=="rate_limited" {limited=true;break}}
 if !limited {t.Fatal("unbounded admission")}
 server.Close()
 if m.report(raw,"another-actor")["accepted"]==true {t.Fatal("unavailable storage ACKed")}
}
