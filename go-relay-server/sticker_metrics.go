package main

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/json"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/libp2p/go-libp2p/core/network"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/redis/go-redis/v9"
)

const stickerUsageAction = "sticker_usage_v1"

// The only durable records are daily integer aggregates (28 days) and random
// retry nonces (72 hours). Actor tokens are salted, bounded RAM-only abuse
// admission state; no peer, IP, device, payload or report body is persisted.
type stickerMetrics struct {
	client   *redis.Client
	prefix   string
	now      func() time.Time
	mu       sync.Mutex
	salt     [32]byte
	hour     int64
	actors   map[[32]byte]int
	requests int
}

func newStickerMetrics(client *redis.Client, prefix string, now func() time.Time) *stickerMetrics {
	m := &stickerMetrics{client: client, prefix: prefix + "sticker:", now: now, actors: map[[32]byte]int{}}
	if _, err := rand.Read(m.salt[:]); err != nil {
		return nil
	}
	return m
}

func (m *stickerMetrics) admit(actor string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	hour := m.now().Unix() / 3600
	if hour != m.hour {
		m.hour = hour
		clear(m.actors)
		m.requests = 0
	}
	token := sha256.Sum256(append(append([]byte{}, m.salt[:]...), []byte(actor)...))
	if m.requests >= 600 || m.actors[token] >= 8 || len(m.actors) >= 10000 {
		return false
	}
	m.requests++
	m.actors[token]++
	return true
}

// Check all touched types and numeric bounds before any mutation: Redis Lua
// errors do not roll back earlier commands. Nonce + increments share one script.
const stickerReportLua = `
local kind=redis.call('TYPE',KEYS[1]).ok
if kind~='none' and kind~='hash' then return redis.error_reply('invalid aggregate type') end
if redis.call('EXISTS',KEYS[2])==1 then return 1 end
if not redis.acl_check_cmd then return 0 end
if not redis.acl_check_cmd('SET',KEYS[2],'1','EX',ARGV[2]) or
   not redis.acl_check_cmd('EXPIREAT',KEYS[1],ARGV[1]) then
 return redis.error_reply('aggregate write not permitted')
end
for i=3,#ARGV,2 do
 if not redis.acl_check_cmd('HINCRBY',KEYS[1],ARGV[i],ARGV[i+1]) then
  return redis.error_reply('aggregate write not permitted')
 end
 local old=redis.call('HGET',KEYS[1],ARGV[i])
 if old and ((old~='0' and not string.match(old,'^[1-9]%d*$')) or tonumber(old)>9007199254740991-tonumber(ARGV[i+1])) then
  return redis.error_reply('invalid aggregate count')
 end
end
for i=3,#ARGV,2 do redis.call('HINCRBY',KEYS[1],ARGV[i],ARGV[i+1]) end
redis.call('EXPIREAT',KEYS[1],ARGV[1])
redis.call('SET',KEYS[2],'1','EX',ARGV[2])
return 1
`

var stickerReportScript = redis.NewScript(stickerReportLua)

func (m *stickerMetrics) report(raw []byte, actor string) map[string]any {
	result := map[string]any{"supported": m != nil, "accepted": false}
	if m == nil {
		return result
	}
	if actor == "" || !m.admit(actor) {
		result["reason"] = "rate_limited"
		return result
	}
	var request struct {
		Action string         `json:"action"`
		Day    string         `json:"day"`
		Nonce  string         `json:"nonce"`
		Counts map[string]int `json:"counts"`
	}
	result["reason"] = "invalid_request"
	if actor == "" || len(raw) > 32768 || appDiagnosticDecode(raw, &request) != nil || request.Action != stickerUsageAction || !diagnosticUUID.MatchString(request.Nonce) {
		return result
	}
	day, err := time.Parse("2006-01-02", request.Day)
	today := m.now().UTC().Truncate(24 * time.Hour)
	if err != nil || !day.Before(today) || day.Before(today.AddDate(0, 0, -3)) || len(request.Counts) == 0 || len(request.Counts) > len(appDiagnosticRules.EnumValues["sticker"]) {
		return result
	}
	increments := map[string]int{}
	for id, count := range request.Counts {
		if !diagnosticContains(appDiagnosticRules.EnumValues["sticker"], id) || count <= 0 || count > 1000 {
			return result
		}
		pack := strings.SplitN(id, ".", 2)[0]
		increments["s:"+id] += count
		increments["p:"+pack] += count
		increments["total"] += count
		if increments["total"] > 1000 {
			return result
		}
	}
	args := []any{day.AddDate(0, 0, 28).Unix(), int64((72 * time.Hour) / time.Second)}
	for field, count := range increments {
		args = append(args, field, count)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	accepted, err := stickerReportScript.Run(ctx, m.client, []string{m.prefix + "day:" + request.Day, m.prefix + "nonce:" + request.Nonce}, args...).Int64()
	if err != nil {
		result["reason"] = "storage_unavailable"
		return result
	}
	if accepted != 1 {
		delete(result, "reason")
		result["supported"] = false
		return result
	}
	delete(result, "reason")
	result["accepted"] = true
	return result
}

func handleStickerUsageRequest(s network.Stream, raw []byte, actor string, m *stickerMetrics) {
	response := map[string]any{"status": "OK", "version": 1, "data": m.report(raw, actor)}
	encoded, _ := json.Marshal(response)
	_ = writeFrame(s, encoded)
}

var stickerTotalDesc = prometheus.NewDesc("relay_sticker_sends_daily", "Anonymous reported sticker sends by UTC day; exact accepted sums, not verified deliveries. Capped/opted-out/old builds are absent.", []string{"day"}, nil)
var stickerPackDesc = prometheus.NewDesc("relay_sticker_pack_sends_daily", "Anonymous reported sends per pack and UTC day.", []string{"day", "pack"}, nil)
var stickerIDDesc = prometheus.NewDesc("relay_sticker_sends_by_id_daily", "Anonymous reported sends per bundled sticker and UTC day.", []string{"day", "pack", "sticker"}, nil)
var stickerReadyDesc = prometheus.NewDesc("relay_sticker_metrics_storage_ready", "1 when the aggregate Redis read succeeds; missing daily series are unavailable, not zero.", nil, nil)

func (m *stickerMetrics) Describe(ch chan<- *prometheus.Desc) {
	ch <- stickerTotalDesc
	ch <- stickerPackDesc
	ch <- stickerIDDesc
	ch <- stickerReadyDesc
}
func (m *stickerMetrics) Collect(ch chan<- prometheus.Metric) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	pipe := m.client.Pipeline()
	days := make([]string, 28)
	commands := make([]*redis.MapStringStringCmd, 28)
	for i := range days {
		days[i] = m.now().UTC().AddDate(0, 0, -i).Format("2006-01-02")
		commands[i] = pipe.HGetAll(ctx, m.prefix+"day:"+days[i])
	}
	if _, err := pipe.Exec(ctx); err != nil {
		ch <- prometheus.MustNewConstMetric(stickerReadyDesc, prometheus.GaugeValue, 0)
		return
	}
	ch <- prometheus.MustNewConstMetric(stickerReadyDesc, prometheus.GaugeValue, 1)
	for i, cmd := range commands {
		for field, raw := range cmd.Val() {
			count, err := strconv.ParseUint(raw, 10, 53)
			if err != nil {
				continue
			}
			switch {
			case field == "total":
				ch <- prometheus.MustNewConstMetric(stickerTotalDesc, prometheus.GaugeValue, float64(count), days[i])
			case strings.HasPrefix(field, "p:"):
				ch <- prometheus.MustNewConstMetric(stickerPackDesc, prometheus.GaugeValue, float64(count), days[i], strings.TrimPrefix(field, "p:"))
			case strings.HasPrefix(field, "s:"):
				id := strings.TrimPrefix(field, "s:")
				if diagnosticContains(appDiagnosticRules.EnumValues["sticker"], id) {
					ch <- prometheus.MustNewConstMetric(stickerIDDesc, prometheus.GaugeValue, float64(count), days[i], strings.SplitN(id, ".", 2)[0], id)
				}
			}
		}
	}
}
