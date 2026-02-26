package main

import (
	"encoding/json"
	"sync"
	"time"
)

// incomingMessage represents a message received from the network.
type incomingMessage struct {
	From      string `json:"from"`
	To        string `json:"to"`
	Content   string `json:"content"`
	Timestamp string `json:"timestamp"`
}

// messageCollector is a thread-safe buffer for incoming messages.
// It implements node.EventCallback to receive events from the libp2p node.
type messageCollector struct {
	mu       sync.Mutex
	messages []incomingMessage
	cond     *sync.Cond
}

func newMessageCollector() *messageCollector {
	mc := &messageCollector{}
	mc.cond = sync.NewCond(&mc.mu)
	return mc
}

// OnEvent implements node.EventCallback. It parses "message:received" events
// and appends them to the message buffer.
func (mc *messageCollector) OnEvent(jsonStr string) {
	var ev struct {
		Event string                 `json:"event"`
		Data  map[string]interface{} `json:"data"`
	}
	if err := json.Unmarshal([]byte(jsonStr), &ev); err != nil {
		return
	}

	if ev.Event == "message:received" {
		msg := incomingMessage{
			From:      strVal(ev.Data, "from"),
			To:        strVal(ev.Data, "to"),
			Content:   strVal(ev.Data, "content"),
			Timestamp: strVal(ev.Data, "timestamp"),
		}
		mc.mu.Lock()
		mc.messages = append(mc.messages, msg)
		mc.cond.Broadcast()
		mc.mu.Unlock()

		// Also emit as async event on stdout.
		emitAsyncEvent("message:received", map[string]interface{}{
			"from":      msg.From,
			"to":        msg.To,
			"content":   msg.Content,
			"timestamp": msg.Timestamp,
		})
	}
}

// getMessages returns a copy of all collected messages.
func (mc *messageCollector) getMessages() []incomingMessage {
	mc.mu.Lock()
	defer mc.mu.Unlock()
	out := make([]incomingMessage, len(mc.messages))
	copy(out, mc.messages)
	return out
}

// waitMessage blocks until a message matching fromPeerId arrives or timeout.
func (mc *messageCollector) waitMessage(fromPeerId string, timeout time.Duration) *incomingMessage {
	deadline := time.Now().Add(timeout)

	mc.mu.Lock()
	defer mc.mu.Unlock()

	for {
		// Check existing messages.
		for i := range mc.messages {
			if fromPeerId == "" || mc.messages[i].From == fromPeerId {
				msg := mc.messages[i]
				return &msg
			}
		}

		remaining := time.Until(deadline)
		if remaining <= 0 {
			return nil
		}

		// Wait with timeout using a timer goroutine.
		done := make(chan struct{})
		go func() {
			timer := time.NewTimer(remaining)
			defer timer.Stop()
			select {
			case <-timer.C:
				mc.cond.Broadcast() // wake up to recheck deadline
			case <-done:
			}
		}()

		mc.cond.Wait()
		close(done)
	}
}

// clearMessages removes all collected messages.
func (mc *messageCollector) clearMessages() {
	mc.mu.Lock()
	defer mc.mu.Unlock()
	mc.messages = nil
}

func strVal(m map[string]interface{}, key string) string {
	if v, ok := m[key].(string); ok {
		return v
	}
	return ""
}
