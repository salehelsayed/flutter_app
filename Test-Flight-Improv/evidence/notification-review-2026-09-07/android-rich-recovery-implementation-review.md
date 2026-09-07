# Android encrypted-message provider recovery

Status: source and focused tests complete; full module/race/vet and Linux candidate identity recorded separately. This change has not been deployed by this worker.

## Causal defect and bounded fix

The original direct/group rich-route regression exhausted all three provider sends, retained ordinary message custody and the current token, then never attempted the failed notification again. A new independent message could send successfully on the recovered provider. This is a demonstrated server recovery gap, not attribution of the externally reported Android incident.

The new Android-only mode retains the existing filtered encrypted-message data and a SHA-bound wake obligation in the same Redis transaction as direct, protected direct/strict-group, or group-topic custody. It excludes reactions, opaque routes, iOS routes, plaintext notification previews and provider tokens. Ordinary text/media remain indistinguishable inside their encrypted envelope.

Initial dispatch claims the same existing due job immediately. The existing coordinator retries transient failures automatically with its existing backoff and a five-second provider deadline. A fresh provider route is resolved on every retry, so token rotation is respected. Message acknowledgement does not remove the independent ciphertext snapshot. Provider acceptance, permanent current-token rejection, receiver completion before a provider claim, or a platform change outside Android terminate the obligation. Existing rich provider-size rescue is preserved.

Terminal markers are separate exact fixed-value keys, bounded by the original custody expiry, at most seven days. They therefore do not consume the existing512 per-recipient active obligation limit. Marker count is proportional to accepted traffic within that bounded horizon, not capped at512. Active-capacity fallback retains the incumbent immediate-send contract; admission still requires a valid currently registered Android rich route and the Redis backend (bootstrap enables admission automatically; there is no separate wake-outcome environment flag).

Only newly admitted custody receives these recovery snapshots. Existing stored inbox rows are not backfilled. Live activation can be verified by an aggregate count increase in `<configured Redis prefix>android-rich-completed:*` after a newly accepted Android rich message. Pending ciphertext keys use `android-rich-material:*`; successful jobs normally remove those immediately, so their absence alone does not mean recovery is disabled. Existing shared due keys use `wake-outcome:due`.

## Preservation and limits

- Existing opaque capability/authentication gates and intentional iOS ambiguous-provider group admission remain unchanged. A current opaque route never receives retained rich data.
- Snapshot TTL is independent of inbox ACK/deletion and never extends past the original custody horizon.
- A known accepted provider result produces an exact completion marker and removes retained material/active state. The provider acceptance and Redis settlement are separate systems: loss of the settlement after provider acceptance can still cause a later at-least-once resend. Existing client notification deduplication remains relevant. Provider acceptance does not prove handset presentation.
- Expired, missing, malformed, cross-recipient, digest-mismatched or unsupported snapshot data cannot reach the provider.
- The five-second provider deadline assumes the Firebase sender honors its context, as the production SDK does. Tests exercise a sender blocked on cancellation and subsequent durable recovery.

## Rollback compatibility

No destructive migration is performed. Existing token/custody keys and opaque-job schemas are preserved; added material and completion key families have bounded original expiry.

The old live decoder ignores the new `android_rich_digest` field. Its claim/settlement or same-peer hash rewrite can drop that field. The old coordinator does not read ciphertext snapshots and a current rich route fails its opaque eligibility check, preserving privacy; however new pending rich recovery progress can be stranded across rollback and re-upgrade. Do not claim that rollback preserves progress for these new obligations. Rolling back does not delete message custody or provider registrations. Independent material keys expire at their original deadline even if the old binary cannot finish their new lifecycle.

## Focused evidence

- `text-provider-retry-counterexample-red.log`: original production defect, direct and group, with recovered-route positive control.
- `android-rich-focused-initial.log`: first new implementation run; only two protected-direct test fixtures rejected for missing required envelope identity. Other new causal cases passed.
- `android-rich-focused-green.log`: corrected public-store integration across legacy/encrypted registration and direct/protected/group/strict routes; capacity, current-token/permanent-CAS rotation, privacy, atomic rejection, terminal cleanup, expiry, timeout/cancellation and concurrent claim checks.
- `android-rich-size-fallback-red.log` and `android-rich-size-fallback-green.log`: exact preservation counterexample and repair for the existing one-shot provider-size rescue, with all eight automatic recovery integration cases rerun.
- `android-rich-source-manifest.json`: source/test/module file SHA256 values used for the final broad checks and candidate.
