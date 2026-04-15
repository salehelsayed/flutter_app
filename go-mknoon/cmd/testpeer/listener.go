package main

import (
	"encoding/json"
	"sync"
	"time"
)

// incomingMessage represents a message received from the network.
type incomingMessage struct {
	From         string `json:"from"`
	To           string `json:"to"`
	Content      string `json:"content"`
	Timestamp    string `json:"timestamp"`
	ConfirmNonce string `json:"confirmNonce"`
}

type incomingGroupMessage struct {
	GroupId        string `json:"groupId"`
	SenderId       string `json:"senderId"`
	SenderUsername string `json:"senderUsername"`
	Text           string `json:"text"`
	Timestamp      string `json:"timestamp"`
	MessageId      string `json:"messageId"`
	DeliveryMs     int64  `json:"deliveryMs"`
	DecryptMs      int64  `json:"decryptMs"`
}

// messageCollector is a thread-safe buffer for incoming messages.
// It implements node.EventCallback to receive events from the libp2p node.
type messageCollector struct {
	mu            sync.Mutex
	messages      []incomingMessage
	groupMessages []incomingGroupMessage
	cond          *sync.Cond
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
			From:         strVal(ev.Data, "from"),
			To:           strVal(ev.Data, "to"),
			Content:      strVal(ev.Data, "content"),
			Timestamp:    strVal(ev.Data, "timestamp"),
			ConfirmNonce: strVal(ev.Data, "confirmNonce"),
		}
		mc.mu.Lock()
		mc.messages = append(mc.messages, msg)
		mc.cond.Broadcast()
		mc.mu.Unlock()

		if msg.ConfirmNonce != "" && state.autoConfirmDirectAck && state.node != nil {
			state.node.ResolveDirectConfirm(msg.ConfirmNonce, true)
		}

		// Also emit as async event on stdout.
		emitAsyncEvent("message:received", map[string]interface{}{
			"from":         msg.From,
			"to":           msg.To,
			"content":      msg.Content,
			"timestamp":    msg.Timestamp,
			"confirmNonce": msg.ConfirmNonce,
		})
		return
	}

	if ev.Event == "group_message:received" {
		msg := incomingGroupMessage{
			GroupId:        strVal(ev.Data, "groupId"),
			SenderId:       strVal(ev.Data, "senderId"),
			SenderUsername: strVal(ev.Data, "senderUsername"),
			Text:           strVal(ev.Data, "text"),
			Timestamp:      strVal(ev.Data, "timestamp"),
			MessageId:      strVal(ev.Data, "messageId"),
			DeliveryMs:     int64Val(ev.Data, "deliveryMs"),
			DecryptMs:      int64Val(ev.Data, "decryptMs"),
		}
		mc.mu.Lock()
		mc.groupMessages = append(mc.groupMessages, msg)
		mc.cond.Broadcast()
		mc.mu.Unlock()

		emitAsyncEvent("group_message:received", map[string]interface{}{
			"groupId":        msg.GroupId,
			"senderId":       msg.SenderId,
			"senderUsername": msg.SenderUsername,
			"text":           msg.Text,
			"timestamp":      msg.Timestamp,
			"messageId":      msg.MessageId,
			"deliveryMs":     msg.DeliveryMs,
			"decryptMs":      msg.DecryptMs,
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

func (mc *messageCollector) getGroupMessages() []incomingGroupMessage {
	mc.mu.Lock()
	defer mc.mu.Unlock()
	out := make([]incomingGroupMessage, len(mc.groupMessages))
	copy(out, mc.groupMessages)
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

func (mc *messageCollector) waitGroupMessage(groupId string, timeout time.Duration) *incomingGroupMessage {
	deadline := time.Now().Add(timeout)

	mc.mu.Lock()
	defer mc.mu.Unlock()

	for {
		for i := range mc.groupMessages {
			if groupId == "" || mc.groupMessages[i].GroupId == groupId {
				msg := mc.groupMessages[i]
				return &msg
			}
		}

		remaining := time.Until(deadline)
		if remaining <= 0 {
			return nil
		}

		done := make(chan struct{})
		go func() {
			timer := time.NewTimer(remaining)
			defer timer.Stop()
			select {
			case <-timer.C:
				mc.cond.Broadcast()
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
	mc.groupMessages = nil
}

func strVal(m map[string]interface{}, key string) string {
	if v, ok := m[key].(string); ok {
		return v
	}
	return ""
}

func int64Val(m map[string]interface{}, key string) int64 {
	if v, ok := m[key].(float64); ok {
		return int64(v)
	}
	if v, ok := m[key].(int64); ok {
		return v
	}
	if v, ok := m[key].(int); ok {
		return int64(v)
	}
	return 0
}
