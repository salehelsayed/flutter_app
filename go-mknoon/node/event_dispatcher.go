package node

import (
	"encoding/json"
	"log"
	"sync"
	"time"
)

const (
	dispatcherPressureEvent  = "group:dispatcher_pressure"
	dispatcherOverflowEvent  = "group:dispatcher_overflow"
	dispatcherPressureFactor = 4
	dispatcherPressureBase   = 5
)

// eventItem represents a single event to be dispatched.
type eventItem struct {
	eventName string
	data      map[string]interface{}
	timestamp time.Time
	emittedAt time.Time
}

// EventDispatcher provides async delivery of events from Go to Flutter.
// Status-like events (addresses:updated, relay:state) are coalesced to keep
// only the latest state. Critical message-bearing events are preserved even
// when the queue is already at maxMessageQueueSize; non-critical events may be
// dropped at capacity after an overflow diagnostic is recorded.
type EventDispatcher struct {
	mu       sync.Mutex
	callback EventCallback

	// FIFO queue for events that cannot be coalesced. Critical message-bearing
	// events may exceed maxMessageQueueSize; non-critical events are capped.
	messageQueue []eventItem

	// Coalesced status events — only the latest of each type is kept.
	statusLatest map[string]eventItem

	// Channel to signal the dispatch goroutine.
	notify chan struct{}

	// Lifecycle.
	stopCh   chan struct{}
	stopOnce sync.Once
	stopped  bool
	wg       sync.WaitGroup

	// Configuration.
	maxMessageQueueSize int

	// Diagnostic counters.
	coalesced int64
	delivered int64
	dropped   int64
}

// coalescedEventTypes lists events where only the latest state matters.
// These are status-like events that can safely skip intermediate states.
var coalescedEventTypes = map[string]bool{
	"addresses:updated":     true,
	"relay:state":           true,
	"media:upload_progress": true,
	dispatcherPressureEvent: true,
	dispatcherOverflowEvent: true,
}

// criticalEventTypes must never be dropped by the dispatcher. If the queue is
// full, these events are appended past the configured cap and an overflow
// diagnostic is coalesced for observability and replay recovery.
var criticalEventTypes = map[string]bool{
	"message:received":        true,
	"group_message:received":  true,
	"group_reaction:received": true,
}

// NewEventDispatcher creates a dispatcher that delivers events to the callback
// asynchronously. Status-like events are coalesced; critical message-bearing
// events are queued losslessly, even if that temporarily exceeds maxQueueSize.
func NewEventDispatcher(callback EventCallback, maxQueueSize int) *EventDispatcher {
	if maxQueueSize <= 0 {
		maxQueueSize = 1024
	}

	d := &EventDispatcher{
		callback:            callback,
		messageQueue:        make([]eventItem, 0, 64),
		statusLatest:        make(map[string]eventItem),
		notify:              make(chan struct{}, 1),
		stopCh:              make(chan struct{}),
		maxMessageQueueSize: maxQueueSize,
	}

	d.wg.Add(1)
	go d.dispatchLoop()

	return d
}

// Emit queues an event for async delivery. This method never blocks the caller
// for more than the time it takes to acquire the lock and enqueue.
func (d *EventDispatcher) Emit(eventName string, data map[string]interface{}) {
	if d.callback == nil {
		return
	}

	now := time.Now()
	item := eventItem{
		eventName: eventName,
		data:      cloneEventData(data),
		timestamp: now,
		emittedAt: now,
	}

	d.mu.Lock()
	if d.stopped {
		d.mu.Unlock()
		return
	}

	if coalescedEventTypes[eventName] {
		d.setStatusLatestLocked(item)
	} else {
		if len(d.messageQueue) >= d.maxMessageQueueSize {
			if criticalEventTypes[eventName] {
				d.recordOverflowDiagnosticLocked(item, "preserved_critical")
				d.messageQueue = append(d.messageQueue, item)
				log.Printf("[EVENT_DISPATCHER] Queue full (%d), preserving critical event over capacity: %s",
					d.maxMessageQueueSize, eventName)
			} else {
				d.dropped++
				d.recordOverflowDiagnosticLocked(item, "dropped")
				log.Printf("[EVENT_DISPATCHER] Queue full (%d), dropping non-critical event: %s",
					d.maxMessageQueueSize, eventName)
			}
		} else {
			d.messageQueue = append(d.messageQueue, item)
			d.maybeRecordPressureLocked(eventName)
		}
	}

	d.mu.Unlock()

	// Signal the dispatch goroutine (non-blocking).
	select {
	case d.notify <- struct{}{}:
	default:
	}
}

func cloneEventData(data map[string]interface{}) map[string]interface{} {
	if data == nil {
		return nil
	}

	cloned := make(map[string]interface{}, len(data))
	for key, value := range data {
		cloned[key] = value
	}
	return cloned
}

func (d *EventDispatcher) setStatusLatestLocked(item eventItem) {
	if _, existed := d.statusLatest[item.eventName]; existed {
		d.coalesced++
	}
	d.statusLatest[item.eventName] = item
}

func (d *EventDispatcher) maybeRecordPressureLocked(eventName string) {
	if d.maxMessageQueueSize <= 0 {
		return
	}

	threshold := (d.maxMessageQueueSize * dispatcherPressureFactor) / dispatcherPressureBase
	if threshold <= 0 {
		threshold = 1
	}
	if len(d.messageQueue) < threshold {
		return
	}

	now := time.Now()
	d.setStatusLatestLocked(eventItem{
		eventName: dispatcherPressureEvent,
		data:      d.dispatcherDiagnosticDataLocked("near_overflow", eventName),
		timestamp: now,
		emittedAt: now,
	})
}

func (d *EventDispatcher) recordOverflowDiagnosticLocked(item eventItem, action string) {
	diagnosticData := d.dispatcherDiagnosticDataLocked("overflow", item.eventName)
	diagnosticData["criticalEvent"] = criticalEventTypes[item.eventName]
	diagnosticData["overflowAction"] = action
	addCriticalEventIdentifiers(diagnosticData, item)

	now := time.Now()
	d.setStatusLatestLocked(eventItem{
		eventName: dispatcherOverflowEvent,
		data:      diagnosticData,
		timestamp: now,
		emittedAt: now,
	})
}

func (d *EventDispatcher) dispatcherDiagnosticDataLocked(
	state string,
	eventName string,
) map[string]interface{} {
	return map[string]interface{}{
		"state":          state,
		"queueDepth":     len(d.messageQueue),
		"statusCount":    len(d.statusLatest),
		"maxQueueSize":   d.maxMessageQueueSize,
		"droppedCount":   d.dropped,
		"coalescedCount": d.coalesced,
		"deliveredCount": d.delivered,
		"lastEvent":      eventName,
	}
}

func addCriticalEventIdentifiers(
	diagnosticData map[string]interface{},
	item eventItem,
) {
	var fields []string
	switch item.eventName {
	case "message:received":
		fields = []string{"from", "to", "timestamp", "transport"}
	case "group_message:received":
		fields = []string{
			"groupId",
			"messageId",
			"keyEpoch",
			"senderId",
			"senderDeviceId",
			"transportPeerId",
		}
	case "group_reaction:received":
		fields = []string{
			"groupId",
			"senderId",
			"senderDeviceId",
			"transportPeerId",
		}
	default:
		return
	}

	for _, field := range fields {
		if value, ok := item.data[field]; ok {
			diagnosticData[field] = value
		}
	}
}

// Stop shuts down the dispatcher, draining any remaining events.
func (d *EventDispatcher) Stop() {
	d.stopOnce.Do(func() {
		d.mu.Lock()
		d.stopped = true
		d.mu.Unlock()
		close(d.stopCh)
	})
	d.wg.Wait()
}

// Diagnostics returns dispatch counters for observability.
func (d *EventDispatcher) Diagnostics() (delivered, coalesced, dropped int64) {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.delivered, d.coalesced, d.dropped
}

// QueueDepth returns the current number of pending events.
func (d *EventDispatcher) QueueDepth() int {
	d.mu.Lock()
	defer d.mu.Unlock()
	return len(d.messageQueue) + len(d.statusLatest)
}

// dispatchLoop runs on a dedicated goroutine and delivers events to the callback.
func (d *EventDispatcher) dispatchLoop() {
	defer d.wg.Done()

	for {
		select {
		case <-d.stopCh:
			// Drain remaining events before exiting.
			d.drainAll()
			return
		case <-d.notify:
			d.drainAll()
		}
	}
}

// drainAll delivers all pending events to the callback.
func (d *EventDispatcher) drainAll() {
	for {
		item, ok := d.dequeue()
		if !ok {
			return
		}
		d.deliver(item)
	}
}

// dequeue removes and returns the next event to deliver.
// Priority: queued non-coalesced events first, then coalesced status events.
func (d *EventDispatcher) dequeue() (eventItem, bool) {
	d.mu.Lock()
	defer d.mu.Unlock()

	// Non-coalesced events first (FIFO).
	if len(d.messageQueue) > 0 {
		item := d.messageQueue[0]
		d.messageQueue = d.messageQueue[1:]
		return item, true
	}

	// Then coalesced status events (any order is fine since they represent latest state).
	for key, item := range d.statusLatest {
		delete(d.statusLatest, key)
		return item, true
	}

	return eventItem{}, false
}

// deliver marshals and sends the event to the callback. Panics from the
// callback are recovered to avoid crashing the dispatch loop.
func (d *EventDispatcher) deliver(item eventItem) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[EVENT_DISPATCHER] Callback panic for event %q: %v", item.eventName, r)
		}
	}()

	if item.emittedAt.IsZero() {
		item.emittedAt = item.timestamp
	}
	if item.emittedAt.IsZero() {
		item.emittedAt = time.Now()
	}
	queueWaitMs := time.Since(item.emittedAt).Milliseconds()
	if queueWaitMs < 0 {
		queueWaitMs = 0
	}
	if item.data == nil {
		item.data = map[string]interface{}{}
	}
	item.data["queueWaitMs"] = queueWaitMs

	payload := map[string]interface{}{
		"event": item.eventName,
		"data":  item.data,
	}

	jsonBytes, err := json.Marshal(payload)
	if err != nil {
		log.Printf("[EVENT_DISPATCHER] Marshal error for event %q: %v", item.eventName, err)
		return
	}

	d.callback.OnEvent(string(jsonBytes))

	d.mu.Lock()
	d.delivered++
	d.mu.Unlock()
}
