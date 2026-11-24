package node

import (
	"context"
	"time"

	"github.com/mknoon/go-mknoon/activitycalendar"
)

type weeklyReporterAttemptKey struct {
	relay string
	kind  weeklyReportKind
}

type weeklyReporterAttempt struct {
	key        weeklyReporterAttemptKey
	week       string
	generation uint64
	mask       uint8
	next       time.Time
	inFlight   bool
}

func (r *activeIdentityReporter) hasWeeklyReportLocked(week string) bool {
	return r.disk.Weekly != nil && r.disk.Weekly.Week == week ||
		r.disk.FeatureUse != nil && r.disk.FeatureUse.Week == week
}

func (r *activeIdentityReporter) queueWeekly(f ActiveIdentityReporterFence) {
	r.stateMu.Lock()
	defer r.stateMu.Unlock()
	if !r.armedLocked(f) || r.deps.transportSnapshot == nil || !r.hasWeeklyReportLocked(activitycalendar.Week(r.deps.now())) {
		return
	}
	if r.weeklyWake == nil {
		r.weeklyWake = make(chan struct{}, 1)
		go r.drainWeekly(r.ctx, f, r.weeklyWake)
	}
	select {
	case r.weeklyWake <- struct{}{}:
	default:
	}
}

func (r *activeIdentityReporter) drainWeekly(ctx context.Context, f ActiveIdentityReporterFence, wake <-chan struct{}) {
	for {
		select {
		case <-ctx.Done():
			return
		case <-wake:
		}
		for delay := r.flushWeekly(f); delay > 0; delay = r.flushWeekly(f) {
			timer := time.NewTimer(delay)
			select {
			case <-ctx.Done():
				timer.Stop()
				return
			case <-wake:
				timer.Stop()
			case <-timer.C:
			}
		}
	}
}

func (r *activeIdentityReporter) flushWeekly(f ActiveIdentityReporterFence) time.Duration {
	r.stateMu.Lock()
	pending := r.armedLocked(f) && r.hasWeeklyReportLocked(activitycalendar.Week(r.deps.now()))
	ownerContext := r.ctx
	r.stateMu.Unlock()
	if !pending || r.deps.transportSnapshot == nil {
		return 0
	}
	transport, ok := r.deps.transportSnapshot()
	if !ok || transport.ctx == nil || transport.current == nil || transport.exchange == nil || !transport.current() {
		return activeIdentityReporterRetryDelay
	}
	relays, _ := activeIdentityReporterRelays(transport.relayAddresses)
	if len(relays) > activeIdentityReporterWeeklyRelays {
		relays = relays[:activeIdentityReporterWeeklyRelays]
	}
	type reportJob struct {
		relay   RelayInfo
		attempt *weeklyReporterAttempt
	}
	var retry time.Duration
	schedule := func(delay time.Duration) {
		if delay > 0 && (retry == 0 || delay < retry) {
			retry = delay
		}
	}
	jobs := make([]reportJob, 0, 2*len(relays))
	r.stateMu.Lock()
	if !r.armedLocked(f) {
		r.stateMu.Unlock()
		return 0
	}
	now := r.deps.now()
	week := activitycalendar.Week(now)
	root := r.config.RootPrivateKeyBase64
	for key, attempt := range r.weeklyAttempts {
		if attempt.week < week || attempt.generation < transport.generation {
			delete(r.weeklyAttempts, key)
		}
	}
	for _, kind := range []weeklyReportKind{engagementWeeklyReport, featureUseWeeklyReport} {
		report := r.disk.weeklyReport(kind)
		if report == nil || report.Week != week {
			continue
		}
		for _, relay := range relays {
			id := relay.ID.String()
			mask := report.Kinds
			for _, ack := range report.Acknowledged {
				if ack.RelayPeerID == id {
					mask &^= ack.Kinds
					break
				}
			}
			if mask == 0 {
				continue
			}
			if kind == engagementWeeklyReport {
				mask |= activeIdentityWeeklyActive
			}
			key := weeklyReporterAttemptKey{relay: id, kind: kind}
			if attempt := r.weeklyAttempts[key]; attempt != nil {
				if attempt.generation > transport.generation || attempt.week > week || attempt.inFlight {
					schedule(activeIdentityReporterRetryDelay)
					continue
				}
				if now.Before(attempt.next) {
					schedule(attempt.next.Sub(now))
					continue
				}
			}
			attempt := &weeklyReporterAttempt{key: key, week: week, generation: transport.generation, mask: mask, inFlight: true}
			r.weeklyAttempts[key] = attempt
			jobs = append(jobs, reportJob{relay: relay, attempt: attempt})
		}
	}
	r.stateMu.Unlock()
	if len(jobs) == 0 {
		return retry
	}

	ctx, cancel := context.WithTimeout(ownerContext, activeIdentityReporterFlushBudget)
	defer cancel()
	stop := context.AfterFunc(transport.ctx, cancel)
	defer stop()
	finished := make(chan time.Duration, len(jobs))
	for _, job := range jobs {
		go func() {
			finished <- r.sendWeekly(ctx, f, transport, job.relay, job.attempt, root)
		}()
	}
	for range jobs {
		select {
		case delay := <-finished:
			schedule(delay)
		case <-ctx.Done():
			schedule(activeIdentityReporterRetryDelay)
			return retry
		}
	}
	return retry
}

func (r *activeIdentityReporter) sendWeekly(ctx context.Context, f ActiveIdentityReporterFence, transport activeIdentityReporterTransport, relay RelayInfo, attempt *weeklyReporterAttempt, root string) (delay time.Duration) {
	delay = activeIdentityReporterRetryDelay
	defer func() {
		r.stateMu.Lock()
		defer r.stateMu.Unlock()
		if r.weeklyAttempts[attempt.key] == attempt {
			attempt.inFlight = false
			attempt.next = r.deps.now().Add(delay)
		}
	}()
	transportCurrent := func() bool {
		return ctx.Err() == nil && transport.current()
	}
	current := func() bool {
		if !transportCurrent() {
			return false
		}
		r.stateMu.Lock()
		defer r.stateMu.Unlock()
		return r.armedLocked(f) && activitycalendar.Week(r.deps.now()) == attempt.week &&
			r.weeklyAttempts[attempt.key] == attempt
	}
	if !current() {
		return
	}
	var request []byte
	var err error
	if attempt.key.kind == featureUseWeeklyReport {
		request, err = buildWeeklyActivityRequest(featureUseProtocolAction, attempt.week, featureUseWireKinds(attempt.mask), f.AccountPeerID, transport.peerID, root)
	} else {
		request, err = buildActiveEngagementRequest(attempt.week, activeIdentityReporterWeeklyKinds(attempt.mask), f.AccountPeerID, transport.peerID, root)
	}
	if err != nil || !current() {
		return
	}
	response, err := transport.exchange(ctx, relay, request)
	if err != nil || !current() {
		return
	}
	var result activeEngagementProtocolResult
	if attempt.key.kind == featureUseWeeklyReport {
		result, err = parseWeeklyActivityResponse(response, featureUseProtocolAction, "FEATURE_USE")
	} else {
		result, err = parseActiveEngagementResponse(response)
	}
	if err != nil {
		return
	}
	switch result {
	case activeEngagementUnsupported:
		delay = activeIdentityReporterUnsupported
	case activeEngagementAcknowledged:
		if r.ackWeeklyReport(f, attempt.week, attempt.key.kind, attempt.key.relay, attempt.mask, transportCurrent) == nil {
			delay = 0
		}
	}
	return
}
