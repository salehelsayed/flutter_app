// Package main implements a headless Go CLI test peer for E2E transport testing.
//
// It reads line-oriented JSON commands on stdin and writes JSON responses
// (plus async events) on stdout. This allows a Dart orchestration script to
// coordinate the test peer with a Flutter app running on a simulator.
//
// Protocol:
//
//	→ {"cmd":"generate_identity"}
//	← {"ok":true,"cmd":"generate_identity","peerId":"12D3...","publicKey":"..."}
//	← {"event":"message:received","data":{"from":"...","content":"..."}}
//
// Build:
//
//	cd go-mknoon && go build -o bin/testpeer ./cmd/testpeer
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"sync"
)

// outputMu serializes writes to stdout so that concurrent event emissions
// and command responses don't interleave.
var outputMu sync.Mutex

func main() {
	// Redirect Go log output to stderr so it doesn't corrupt the JSON protocol.
	log.SetOutput(os.Stderr)
	log.SetFlags(log.Ltime | log.Lmicroseconds)

	log.Println("[testpeer] started — reading commands from stdin")

	scanner := bufio.NewScanner(os.Stdin)
	// Allow large input lines (e.g. for send_raw with big payloads).
	scanner.Buffer(make([]byte, 0, 256*1024), 256*1024)

	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			continue
		}

		var req struct {
			Cmd    string                 `json:"cmd"`
			Params map[string]interface{} `json:"params"`
		}
		if err := json.Unmarshal([]byte(line), &req); err != nil {
			writeResponse(map[string]interface{}{
				"ok":           false,
				"errorMessage": fmt.Sprintf("invalid JSON: %v", err),
			})
			continue
		}

		if req.Cmd == "" {
			writeResponse(map[string]interface{}{
				"ok":           false,
				"errorMessage": "missing cmd field",
			})
			continue
		}

		log.Printf("[testpeer] cmd=%s", req.Cmd)

		if req.Params == nil {
			req.Params = make(map[string]interface{})
		}

		result := handleCommand(req.Cmd, req.Params)
		result["cmd"] = req.Cmd
		writeResponse(result)
	}

	if err := scanner.Err(); err != nil {
		log.Printf("[testpeer] stdin read error: %v", err)
	}

	// Cleanup on exit.
	if state.node != nil {
		state.node.Stop()
	}

	log.Println("[testpeer] exiting")
}

// writeResponse writes a JSON response line to stdout.
func writeResponse(resp map[string]interface{}) {
	outputMu.Lock()
	defer outputMu.Unlock()

	b, err := json.Marshal(resp)
	if err != nil {
		log.Printf("[testpeer] marshal error: %v", err)
		return
	}
	fmt.Fprintln(os.Stdout, string(b))
}

// emitAsyncEvent writes an async event to stdout (called from messageCollector).
func emitAsyncEvent(eventName string, data map[string]interface{}) {
	outputMu.Lock()
	defer outputMu.Unlock()

	ev := map[string]interface{}{
		"event": eventName,
		"data":  data,
	}
	b, err := json.Marshal(ev)
	if err != nil {
		log.Printf("[testpeer] event marshal error: %v", err)
		return
	}
	fmt.Fprintln(os.Stdout, string(b))
}
