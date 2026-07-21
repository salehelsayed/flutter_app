# 267 - Group Invite Pre-Fanout H2 Owner Split

Status: evidence-gated owner follow-up; production execution is `not-ready`

## Source Evidence

Wave 0 run `1784655771513` selected H2. `pre_fanout` was the exclusive-largest
phase in all 30 samples. The selected `create|online-cold` cell recorded a
1443.289 ms median and 1659.114 ms maximum for pre-fanout work, while live send
recorded a 122.058 ms median and 158.465 ms maximum. The validated source
summary is:

`/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/invite_reliability_multi_device_WN6LXd/md004_1784655771513_invite_send_latency_host_summary.json`

Its SHA-256 is
`3f51d419178e3ce438ead7379df346c27a80123d571f49e45298cc8d075b1e5b`.
The disposition explicitly records `productionAuthorized=false`.

## Ownership And Scope

Owner: Groups application/repository and group-creation/add-member UI flow.

This follow-up owns evidence-splitting the current coarse `pre_fanout` phase
into the actual create/add awaits before choosing a design. It does not inherit
authorization for H1, dual transport, receiver dedup, native timeout changes,
or optimistic fire-and-forget navigation.

In scope for the next reviewed revision:

- Split create pre-fanout into group creation, local member/key persistence,
  native group configuration, and recipient preparation.
- Split add-member pre-fanout into group/member lookup, membership persistence,
  native configuration update, and recipient preparation.
- Measure the same six-cell, five-repetition matrix with the existing run ID,
  provenance, artifact, and host-custody guarantees.
- Obtain a product-approved absolute create/add caller-settlement threshold and
  tolerance before defining a production RED.
- If UI decoupling is still selected, define a crash-safe delivery job/outbox,
  truthful optimistic-copy semantics, durable failure/retry visibility, and
  navigation behavior that cannot lose the persisted invite attempt.

Hard stops:

- Do not move navigation ahead of truthful delivery-attempt persistence.
- Do not treat ACK, relay custody, or a local attempt row as recipient
  application delivery.
- Do not add a production timeout/race, mint a replacement invite ID after an
  unknown outcome, change Go/global timeouts, change the wire/schema, or enable
  sender dual delivery.
- Do not implement UI decoupling until crash/restart recovery and user-visible
  failure semantics have named causal tests.

## Required Replan Inputs

1. A reviewed subphase artifact contract and targeted instrumentation-only RED.
2. Product-approved caller threshold and tolerance for both create and add.
3. A crash/restart durability contract for any deferred delivery job.
4. Exact tests for attempt-row identity, one job per invite ID, retry/status
   truth, process relaunch, navigation settlement, and current parallel fanout.
5. A gate cadence scoped to the production surfaces ultimately selected.

Until those inputs are reviewed, the H2 owner split remains `not-ready` and
the production behavior from plan 267 remains unchanged.
