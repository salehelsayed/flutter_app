# Introduction Feature -- Test Inventory

**Date:** 2026-04-13
**Scope:** All automated tests covering the Introduction feature across unit, widget, integration, and regression categories.

---

## How to Run

**Fast intro regression** (gate script, host-side only):

```sh
./scripts/run_test_gates.sh intro
```

**Full host-side intro suite:**

```sh
flutter test --no-pub test/features/introduction
```

**Targeted copy/text verification** (shortest useful set):

```sh
flutter test --no-pub \
  test/features/introduction/application/introduction_copy_test.dart \
  test/features/introduction/integration/intro_wiring_smoke_test.dart
INTRO_E2E_SCENARIO=copy ./smoke_test_friends.sh
```

**Three-simulator E2E** (requires `reset_simulators.sh` via `smoke_test_friends.sh` -- notification popup bypass is automatic with `E2E_TEST_MODE=true`):

| Command | What it runs |
|---------|-------------|
| `INTRO_E2E_SCENARIO=happy ./smoke_test_friends.sh` | Happy path only |
| `INTRO_E2E_SCENARIO=pass ./smoke_test_friends.sh` | Pass flow |
| `INTRO_E2E_SCENARIO=refresh ./smoke_test_friends.sh` | Re-introduction / refresh |
| `INTRO_E2E_SCENARIO=repair ./smoke_test_friends.sh` | Repair flow |
| `INTRO_E2E_SCENARIO=copy ./smoke_test_friends.sh` | UI/copy verification |
| `INTRO_E2E_SCENARIO=partition ./smoke_test_friends.sh` | Partition-heal convergence |
| `INTRO_E2E_SCENARIO=offline-chat ./smoke_test_friends.sh` | Offline relay to first chat |
| `INTRO_E2E_SCENARIO=pass-fallback ./smoke_test_friends.sh` | Pass fallback inbox drain |
| `INTRO_E2E_SCENARIO=split-brain ./smoke_test_friends.sh` | Waiting-vs-connected recovery |
| `INTRO_E2E_SCENARIO=all ./smoke_test_friends.sh` | Full intro matrix |

Screenshots from device runs are saved under `build/intro_e2e/`.

---

## Summary

| Category | Files | Test Cases |
|----------|------:|-----------:|
| Domain (models, repo impl) | 2 | 13 |
| Data (DB migrations/helpers) | 3 | 12 |
| Application (use cases, listener, delivery) | 18 | 182 |
| Presentation (widgets, screens) | 10 | 72 |
| Integration (smoke, wiring, multi-node) | 4 | 63 |
| Regression | 1 | 22 |
| Cross-feature (feed, push, conversation, orbit) | 8 | 44 |
| **Total** | **46** | **408** |

QA checklist from the `c4-code.md` source-of-truth review:

- [ ] Section 15 still omits the introducer-side local intro row and later accept/pass update path, even though existing automated coverage proves that seam in `send_introduction_test.dart` and `introduction_multi_node_test.dart`.
- [ ] Section 2 still overstates "Every File in the Feature"; intro-related contact metadata, settings debug wiring, and share/startup routing seams exist outside that file map. Some of those seams are exercised in broader tests, but they are not enumerated in this inventory.
- [ ] Section 12 still omits intro-adjacent flow-event families for contact intro metadata persistence and intro retry orchestration; no dedicated test currently pins that event inventory.
- [ ] Section 13 still says `chatMessageStream` routes `type == 'chat'`; the live router uses `chat_message`, and no intro-scoped regression currently locks that contract.
- [x] Section 10.3 still says the mutual-accept CTA is `Send Message`; the live `IntroRow` label is `Message`, and `intro_row_test.dart` now asserts that exact copy.
- [x] `acceptIntroduction` / `passIntroduction` now reject non-party callers, and direct accept/pass regressions pin the no-mutation contract.

---

## 1. Domain Layer

### 1.1 IntroductionModel
**File:** `test/features/introduction/domain/models/introduction_model_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `deriveStatus` | returns mutualAccepted when both accepted | Status derivation -- happy path |
| | returns passed when recipient passed | Passed by recipient |
| | returns passed when introduced passed | Passed by introduced |
| | returns expired after 30 days | 30-day expiry window |
| | returns pending for fresh pending intro | Default pending state |
| `fromMap / toMap` | fromMap correctly deserializes all fields | DB round-trip |
| | toMap correctly serializes all fields | DB round-trip |
| `copyWith` | returns modified copy with updated fields | Immutable update |
| `equality` | two models with same id are equal | Value equality |
| | two models with different id are not equal | Value inequality |
| `toDbString extensions` | IntroductionStatus.toDbString works for all values | Enum → DB string |
| | IntroductionOverallStatus.toDbString works for all values | Enum → DB string |

### 1.2 IntroductionRepositoryImpl
**File:** `test/features/introduction/domain/repositories/introduction_repository_impl_test.dart`

| Test | What it covers |
|------|----------------|
| deleteIntroduction clears staged responses before deleting intro row | Cascading delete of pending responses |

---

## 2. Data Layer (DB Migrations / Helpers)

### 2.1 pending_introduction_responses table
**File:** `test/core/database/migrations/046_pending_introduction_responses_test.dart`

| Test | What it covers |
|------|----------------|
| creates pending_introduction_responses table | Migration creates table schema |
| is idempotent when rerun | Re-running migration is safe |

### 2.2 Intro persistence migrations
**File:** `test/core/database/migrations/intro_migrations_test.dart`

| Test | What it covers |
|------|----------------|
| creates the introductions table with expected indexes | Migration 019 base schema and indexes |
| is idempotent when rerun | Migration 019 rerun safety |
| add introduced and recipient key columns | Migrations 022 and 023 key-column additions |
| preserves existing key data and allows already_connected status | Migration 025 table rebuild plus status expansion |
| creates the outbox table with retry indexes | Migration 047 schema and indexes |
| is idempotent when rerun | Migration 047 rerun safety |

### 2.3 Intro DB helpers
**File:** `test/core/database/helpers/intro_db_helpers_test.dart`

| Test | What it covers |
|------|----------------|
| includes already_connected rows for visibility and orders newest first | Pending intro loader truth |
| counts only true pending rows across recipient and introduced roles | Pending badge count truth |
| orders replay rows by created_at then response_key | Deferred intro response replay ordering |
| returns only failed stale sending or sent and delivered via inbox rows in created order | Retryable intro outbox selection |

### Coverage Notes

- Direct migration coverage for `019`, `022`, `023`, `025`, and `047` is now
  covered on 2026-04-13 by `test/core/database/migrations/intro_migrations_test.dart`.
- Direct helper coverage for `introductions_db_helpers.dart`,
  `pending_introduction_responses_db_helpers.dart`, and
  `introduction_outbox_db_helpers.dart` is now covered on 2026-04-13 by
  `test/core/database/helpers/intro_db_helpers_test.dart`.
- Broader regression confirmation for the touched persistence seam was rerun on
  2026-04-13 with `flutter test --no-pub test/core/database`.

---

## 3. Application Layer

### 3.1 sendIntroductions
**File:** `test/features/introduction/application/send_introduction_test.dart`

| Test | What it covers |
|------|----------------|
| creates N introduction records for N selected friends | Batch creation |
| each record has correct introducerId | Field mapping |
| each record has correct recipientId and introducedId | Field mapping |
| each record initializes with pending statuses | Initial state |
| introsSentAt is set on the recipient contact | Banner suppression flag |
| payload sent to recipient via P2P | Outbound delivery to User-B |
| payload sent to introduced friend via P2P | Outbound delivery to User-C |
| v2 encryption used when target has ML-KEM key | E2E encryption path |
| v1 plaintext used when target lacks ML-KEM key | Fallback path |
| returns list of created IntroductionModels | Return value |
| records are persisted in introRepo | Persistence |
| re-sending the same pair replaces the older local intro row | Upsert / dedup |
| re-sending the same pair after expiry replaces the expired local row with a fresh pending intro | Post-expiry refresh |
| persists the sender local intro row before a later delivery-stage crash | Sender crash-window durability |
| caps active intro work at 10 and splits later friends into a second batch | Batch concurrency cap |
| continues across inbox fallback in the same and later batches | Cross-batch delivery resilience |
| returns results in input friend order instead of completion order | Stable ordering |
| sets introsSentAt once after all batches finish | Single flag write |
| reports truthful progress only when an intro chain settles | Progress callback accuracy |

### 3.2 acceptIntroduction
**File:** `test/features/introduction/application/accept_introduction_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| (top) | accept sets recipientStatus to accepted when user is recipient | Status update -- recipient side |
| | accept sets introducedStatus to accepted when user is introduced | Status update -- introduced side |
| | single-side accept does NOT change overall to mutualAccepted | Partial acceptance guard |
| | both sides accepting sets status to mutualAccepted | Full acceptance happy path |
| | accept returns null for non-existent introduction | Missing record guard |
| | non-party caller cannot accept and does not mutate intro state | Caller-membership guard |
| | accept sends notification to introducer | Outbound to User-A |
| | accept sends notification to other party | Outbound to stranger |
| | rejects intro/contact stranger ML-KEM mismatches before mutation | Stranger key mismatch rejection |
| `v2 encryption to stranger` | v2 encryption used for stranger when intro has ML-KEM key | Stranger encryption -- recipient side |
| | v2 encryption used for stranger from introduced side | Stranger encryption -- introduced side |
| | contact ML-KEM key is used for stranger when intro record omits it | Stranger contact-key fallback |
| | v1 fallback when intro record has null ML-KEM key for stranger | Fallback path |
| | v1 fallback when encryption fails for stranger | Error fallback |

### 3.3 passIntroduction
**File:** `test/features/introduction/application/pass_introduction_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| (top) | pass sets the passing user's status to passed | Status update |
| | pass changes overall status to passed | Derived status |
| | pass does NOT create a connection | No contact on pass |
| | non-party caller cannot pass and does not mutate intro state | Caller-membership guard |
| | pass sends notification to introducer and other party | Outbound delivery |
| | rejects intro/contact stranger ML-KEM mismatches before mutation | Stranger key mismatch rejection |
| `v2 encryption to stranger` | v2 encryption used for stranger on pass | Stranger encryption |
| | contact ML-KEM key is used for stranger on pass when intro record omits it | Stranger contact-key fallback |
| | v1 fallback on pass when no ML-KEM key | Fallback path |

### 3.4 handleIncomingIntroduction
**File:** `test/features/introduction/application/handle_incoming_introduction_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `alreadyConnected serialization` | alreadyConnected serializes to already_connected | Enum serialization |
| | already_connected parses to alreadyConnected | Enum deserialization |
| `send action` | creates new intro record | Happy path receive |
| | detects duplicate and returns alreadyExists | Dedup guard |
| | newer send for same pair replaces older row | Upsert semantics |
| | older send for same pair is ignored | Stale message rejection |
| | older same-pair send does not replace a passed intro with a new pending row | Terminal stale-send guard -- passed |
| | older same-pair send does not replace an expired intro with a new pending row | Terminal stale-send guard -- expired |
| | older same-pair send does not replace an alreadyConnected intro with a new pending row | Terminal stale-send guard -- alreadyConnected |
| `already connected detection` | incoming intro for existing contact gets alreadyConnected status | Already-friends guard |
| | incoming intro for non-contact stays pending | Normal pending path |
| | alreadyConnected intro appears in getPendingIntroductionsForUser | UI visibility |
| | alreadyConnected intro does NOT inflate pending badge count | Badge accuracy |
| `accept/pass actions` | accept updates recipient status when responder is recipient | Recipient accept |
| | accept updates introduced status when responder is introduced | Introduced accept |
| | both accept derives mutualAccepted overall status | Full acceptance |
| | pass action derives passed overall status | Pass derivation |
| | accept before send is deferred and replayed | Out-of-order handling |
| | pass before send is deferred and replayed | Out-of-order handling |

### 3.5 handleMutualAcceptance
**File:** `test/features/introduction/application/create_connection_on_mutual_acceptance_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `handleMutualAcceptance` | mutual_accepted triggers contactRepo.addContact() | Contact creation |
| | new contact has correct peerId and username | Field mapping |
| | new contact has introducedBy set to introducer username | Metadata |
| | contact NOT created if already exists (idempotency) | Idempotency |
| | contact NOT created if status != mutual_accepted | Guard condition |
| | recipient gets contact for introduced party | Direction -- B gets C |
| | introduced party gets contact for recipient | Direction -- C gets B |
| | new contact has mlKemPublicKey from introduction | Key exchange |
| | stores a meaningful system message in the new conversation | System message |
| | avatar retry failure does not roll back the created contact or system message | Avatar failure durability |
| | existing mutual-acceptance contact without avatar retries settlement without duplicating system message | Later avatar settlement idempotence |
| `ConnectionFeedItem.fromContact` | populates introducedBy from contact field | Feed item mapping |

### 3.6 Mutual Acceptance (combined flow)
**File:** `test/features/introduction/application/mutual_acceptance_test.dart`

| Test | What it covers |
|------|----------------|
| mutual_accepted triggers after both accept | End-to-end acceptance |
| single-side accept does NOT trigger mutualAccepted | Partial guard |
| pass after other accepted results in passed overall | Pass overrides |
| order independence: C accepts first then B | Order doesn't matter |
| concurrent acceptance: only one status update (idempotency) | Race condition |
| accept sends notification to introducer | Outbound to A |
| accept sends notification to other party | Outbound to stranger |
| deriveStatus with both accepted returns mutualAccepted | Status derivation |
| deriveStatus with one accepted one pending returns pending | Status derivation |
| deriveStatus with one passed returns passed regardless of other | Status derivation |
| multiple intros: only matching pair reaches mutualAccepted | Cross-intro isolation |
| handleIncoming defers response for non-existent intro | Out-of-order |
| pass use case sets overall status to passed | Pass flow |
| pass sends notifications to both parties | Outbound on pass |
| accept after pass still results in passed | Pass is terminal |
| expired intro derives expired status | Expiry |
| accept returns null for non-existent introduction | Missing record guard |

### 3.7 shouldShowIntroBanner
**File:** `test/features/introduction/application/check_intro_banner_test.dart`

| Test | What it covers |
|------|----------------|
| returns true when all conditions met | Happy path |
| returns false when contact is blocked | Block gate |
| returns false when contact is archived | Archive gate |
| returns false when banner already dismissed | Dismiss gate |
| returns false when intros already sent | Sent gate |
| returns false when messageCount >= 3 | Message count gate |
| returns false when no other active contacts exist | Friends gate |

**File:** `test/features/introduction/application/check_intro_banner_extended_test.dart`

| Test | What it covers |
|------|----------------|
| returns true with messageCount 0 and multiple friends | Boundary -- zero messages |
| returns false at exactly messageCount 3 | Boundary -- threshold |
| returns true at messageCount 2 | Boundary -- below threshold |
| returns false when only other contact is blocked | Blocked friend excluded |
| returns false when only other contact is archived | Archived friend excluded |

### 3.8 Dismiss Banner
**File:** `test/features/introduction/application/dismiss_banner_test.dart`

| Test | What it covers |
|------|----------------|
| dismissIntroBanner sets introsBannerDismissed to true | Flag persistence |
| banner does not show after dismissal | Integration with shouldShow |
| setIntrosSentAt records timestamp | Sent-at flag |
| introsSentAt causes banner to hide | Sent suppresses banner |
| introsBannerDismissed defaults to false on new contact | Default state |
| introsSentAt defaults to null on new contact | Default state |
| dismissIntroBanner is idempotent | Idempotency |
| setIntrosSentAt can be updated | Overwrite allowed |

### 3.9 Edge Cases
**File:** `test/features/introduction/application/edge_cases_test.dart`

| Test | What it covers |
|------|----------------|
| 0 friends shouldShowIntroBanner returns false | Empty friends list |
| blocked contact hides banner | Block check |
| deriveStatus returns expired after 30 days | Expiry |
| deriveStatus returns pending within 30 days | Non-expired |
| deriveStatus returns mutualAccepted when both accept | Happy path |
| deriveStatus returns passed when recipient passes | Recipient pass |
| deriveStatus returns passed when introduced passes | Introduced pass |
| deriveStatus returns passed when one passes after other accepts | Mixed states |
| getPendingIntroductionsForUser filters by status | Query filtering |

### 3.10 loadIntroductionsForUser
**File:** `test/features/introduction/application/load_introductions_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `loadIntroductionsForUser` | returns only pending intros for user | Query correctness |
| | returns intros where user is introduced party | Both-role coverage |
| | returns empty list when no intros exist | Empty state |
| `groupByIntroducer` | groups correctly by introducer ID | Grouping logic |
| | empty list returns empty map | Empty input |

### 3.11 IntroductionPayload Serialization
**File:** `test/features/introduction/application/introduction_payload_test.dart`

| Test | What it covers |
|------|----------------|
| toInnerJson serializes send action correctly | Serialize send |
| fromInnerJson parses send action correctly | Deserialize send |
| toInnerJson serializes accept action correctly | Serialize accept |
| fromInnerJson parses accept action correctly | Deserialize accept |
| toJson wraps in v1 envelope | v1 envelope construction |
| fromJson parses v1 envelope | v1 envelope parsing |
| buildEncryptedEnvelope creates v2 envelope | v2 envelope construction |
| buildEnvelopeMessageId scopes retries to action and sender | Action-scoped dedupe key |
| ensureEnvelopeMessageId replaces intro-only ids so send and accept do not collide | Intro-only id normalization |
| ensureEnvelopeMessageId patches missing messageId and preserves legacy id envelopes | Legacy envelope compatibility |
| parseEncryptedEnvelope rejects non-introduction types | Type guard |

**File:** `test/features/introduction/application/introduction_payload_extended_test.dart`

| Test | What it covers |
|------|----------------|
| parseEncryptedEnvelope returns null for v1 envelope | v1 not parsed as v2 |
| parseEncryptedEnvelope returns null for missing encrypted block | Missing block guard |
| fromJson returns null for non-introduction type | Type guard |

### 3.12 IntroductionCopy (text formatters)
**File:** `test/features/introduction/application/introduction_copy_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `formatIntroducerIntroductionSystemMessage` | uses the introduced username for a single introduction | Singular copy |
| | summarizes multiple introduced usernames | Plural copy |
| `formatIncomingIntroductionMessage` | formats the recipient-side message | Recipient perspective |
| | formats the introduced-side message | Introduced perspective |
| | includes the already connected suffix | Already-connected variant |
| (top) | formatMutualAcceptanceSystemMessage names the new contact clearly | Mutual acceptance copy |
| `introducer status feedback copy` | formats first-accept progress when the recipient accepts first | Introducer first-accept copy |
| | formats first-accept progress when the introduced party accepts first | Reverse-order introducer copy |
| | formats introducer mutual-accept thread copy | Introducer thread completion copy |
| | formats introducer mutual-accept notification copy | Introducer notification completion copy |

### 3.13 IntroductionListener
**File:** `test/features/introduction/application/introduction_listener_test.dart`

| Test | What it covers |
|------|----------------|
| rejects send messages from blocked senders | Block guard (send only) |
| allows accept from blocked sender to complete handshake | Block bypass for accept |
| dispatches new intros to introReceivedStream | Stream broadcasting |
| successful intro receipt emits flow events, stores system message, shows notification | Full receive side-effects |
| duplicate send replay keeps one row, one system message, and one notification | Duplicate send replay idempotency |
| dispatches status changes to introStatusChangedStream | Status stream |
| introduced-side receipt uses introduced perspective in system message and notification | Copy perspective |
| introducer-side first accept writes a recipient-thread progress message without a false connection notification | Introducer first-accept thread feedback |
| introducer-side mutual acceptance writes a recipient-thread connection message and a role-correct notification | Introducer completion feedback |
| participant-side mutual acceptance shows a local new-connection notification | Participant notification on connect |
| duplicate introducer mutual-accept replay does not duplicate recipient-thread messages or notifications | Introducer replay idempotency |
| duplicate accept replay after mutual acceptance does not duplicate contact side effects or notifications | Terminal accept replay idempotency |
| multiple incoming intros produce stacked local notifications | Notification stacking |
| defers out-of-order accept and confirms direct delivery positively | Out-of-order + ack |
| send after deferred accept replays staged response | Deferred replay |
| v2 key mismatch rejects intro, stores nothing, logs failure | Decryption failure |
| tampered v2 ciphertext rejects intro, stores nothing, and logs failure | Tampered v2 rejection |

### 3.14 Outbound Delivery
**File:** `test/features/introduction/application/introduction_outbound_delivery_test.dart`

| Test | What it covers |
|------|----------------|
| acked live send clears the staged outbox delivery | Direct success cleanup |
| unacked live send keeps a retryable sent outbox delivery | Unacked retry state |
| relay-probe fallback delivers after the direct path fails | Relay fallback after direct failure |
| inbox fallback success clears the outbox delivery | Inbox fallback cleanup |
| failed live send and inbox fallback keeps a failed outbox delivery | Double-failure state |
| retryPendingIntroductionDeliveries replays a sent row through inbox | Retry mechanism |
| retryPendingIntroductionDeliveries processes multiple stalled and failed rows and cleans delivered inbox rows | Multi-row retry cleanup |
| handleAppResumed replays a sent intro row through inbox-only retry | Resume-triggered inbox-only replay |

### 3.15 expireOldIntroductions
**File:** `test/features/introduction/application/expire_old_introductions_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| repairs stale pending mutual acceptance rows and recreates contact | Startup healing |
| repairs stale pending passed rows without creating a contact | Passed-state startup healing |
| repairs stale pending expired rows without creating a contact | Expired-state startup healing |
| leaves alreadyConnected rows untouched during startup repair | Guard for already-connected |
| later recovery settles avatar for an already-mutual-accepted contact without duplicating side effects | Intro-owned later avatar settlement |

### 3.16 resolveUnknownInboxSender
**File:** `test/features/introduction/application/resolve_unknown_inbox_sender_use_case_test.dart`

| Test | What it covers |
|------|----------------|
| rejects senders with no matching introduction | No intro found |
| rejects pending introductions when own side has not accepted | Pre-accept rejection |
| keeps the message retryable once own side accepted the intro | Post-accept hold |
| recreates a mutually accepted contact and marks recoverable | Contact recovery |
| does not retry passed or expired introductions | Terminal status guard |
| treats already-connected intros without a local row as retryable | Edge case |
| reports already-connected intros as recovered when contact exists | Edge case |

---

## 4. Presentation Layer

### 4.1 IntroBanner
**File:** `test/features/introduction/presentation/widgets/intro_banner_test.dart`

| Test | What it covers |
|------|----------------|
| renders banner with contact username | Rendering |
| "Make introductions" button triggers callback | CTA action |
| "Maybe later" triggers callback | Dismiss action |

### 4.2 IntroRow
**File:** `test/features/introduction/presentation/widgets/intro_row_test.dart`

| Test | What it covers |
|------|----------------|
| pending state shows Accept and Pass buttons | Pending UI |
| accepted state shows Connected label | Accepted UI |
| mutualAccepted state shows Message CTA and invokes callback | Exact mutual-accept CTA copy and action |
| accepted own pending intro shows waiting label | One-sided accept UI |
| passed state shows Passed label | Passed UI |
| alreadyConnected state shows status only and no actions | Already-connected UI |
| shows introducer attribution | Attribution rendering |
| displayUsername uses RTL for Arabic-first mixed text | RTL text direction |
| displayUsername uses LTR for English-first mixed text | LTR text direction |
| introducer attribution keeps Arabic-first username explicit | RTL attribution |
| introducer attribution keeps English-first username explicit | LTR attribution |

### 4.3 IntrosTab
**File:** `test/features/introduction/presentation/widgets/intros_tab_test.dart`

| Test | What it covers |
|------|----------------|
| shows empty state when no introductions | Empty state |
| shows pending introductions grouped by sender | Grouping rendering |
| group header shows "From [username]" | Header text |
| each intro row shows introduced username | Row content |
| each intro row shows introducer attribution | Attribution in row |
| accept button visible for pending intros | Accept CTA visibility |
| pass button visible for pending intros | Pass CTA visibility |
| accept callback triggered on tap | Accept wiring |
| pass callback triggered on tap | Pass wiring |
| status label shown for responded intros | Post-response UI |

**File:** `test/features/introduction/presentation/widgets/intros_tab_extended_test.dart`

| Test | What it covers |
|------|----------------|
| multiple introducers render multiple group headers | Multi-group |
| expired status shows non-pending UI | Expired state |
| empty state shows placeholder text | Placeholder copy |
| blank or null usernames fall back to peer ids | Fallback display name |
| very long usernames still render with actions intact | Overflow handling |

### 4.4 IntroGroupHeader
**File:** `test/features/introduction/presentation/widgets/intro_group_header_test.dart`

| Test | What it covers |
|------|----------------|
| renders mixed-script introducer usernames | Unicode / i18n |
| renders plain English usernames | Basic rendering |
| dynamic Arabic-first username stays explicit inside header | RTL text direction |
| dynamic English-first username stays explicit inside header | LTR text direction |

### 4.5 IntroSystemMessage
**File:** `test/features/introduction/presentation/widgets/intro_system_message_test.dart`

| Test | What it covers |
|------|----------------|
| renders "You introduced N people" text | Introducer copy |
| renders "[User-A] introduced N people to you" | Recipient copy |
| renders "You and [name] are now connected" | Mutual acceptance copy |
| renders with correct count | Count accuracy |
| renders with correct names | Name accuracy |
| renders centered | Layout |
| renders with muted style | Styling |
| text is centered alignment | Alignment |
| does not have interactive actions | Non-interactive |
| multiple system messages render in sequence | List rendering |
| Arabic system text drives RTL direction | RTL rendering |
| Arabic-first mixed system text drives RTL direction | RTL mixed text |
| English-first mixed system text stays LTR direction | LTR mixed text |

### 4.6 SentConfirmationScreen
**File:** `test/features/introduction/presentation/screens/sent_confirmation_test.dart`

| Test | What it covers |
|------|----------------|
| correct count displayed in title | Count display |
| singular form for count of 1 | Copy grammar |
| avatar row renders friend names with overflow | Overflow handling |
| "Back to conversation" button triggers callback | Navigation callback |

### 4.7 FriendPickerScreen
**File:** `test/features/introduction/presentation/screens/friend_picker_test.dart`

| Test | What it covers |
|------|----------------|
| header shows "Introduce to [username]" | Title text |
| displays all available friends | List rendering |
| search filters list by name | Search functionality |
| empty state shown when no friends match search | Search empty state |
| empty state when no available friends | No friends state |
| selecting a friend shows check icon | Selection UI |
| deselecting shows empty circle | Deselection UI |
| "Introduce (N)" button shows correct count | Button count label |
| button shows "Introduce" when 0 selected | Zero-selection label |
| button is disabled when 0 selected | Zero-selection guard |
| button is enabled when friends selected | Selection enables CTA |
| sending progress is shown while send is in flight | Loading state |
| button stays disabled while sending | Send-in-progress guard |
| tapping friend row triggers onToggleFriend | Row tap callback |
| onSend callback triggered | Send callback |
| close button triggers onClose | Close callback |
| multiple friends can be selected simultaneously | Multi-select |

### 4.8 FriendPickerWired
**File:** `test/features/introduction/presentation/screens/friend_picker_wired_test.dart`

| Test | What it covers |
|------|----------------|
| filters recipient, self, blocked, and archived contacts while keeping eligible friends selectable | Wired contact filtering |
| intro history no longer hides other eligible contacts in the picker | Re-introduction allowed |
| existing same-pair intro stays selectable so the pair can be reintroduced | Re-introduction selection |
| loads, searches, selects, sends with progress, and returns introductions to the parent callback | Full wired picker flow |

### 4.9 SentConfirmationWired
**File:** `test/features/introduction/presentation/screens/sent_confirmation_wired_test.dart`

| Test | What it covers |
|------|----------------|
| passes the sent result set through and forwards the back callback | Wired confirmation pass-through and route callback |

---

## 5. Integration Tests

### 5.1 Introduction Smoke
**File:** `test/features/introduction/integration/introduction_smoke_test.dart`

| Test | What it covers |
|------|----------------|
| happy path: A sends -> B receives -> both accept -> connected | Full lifecycle |
| dismiss + re-entry via overflow menu path | Banner re-entry |
| no friends: banner not shown | Empty friends guard |
| block during flow: banner stays dismissed after unblock | Block/unblock state |
| local/direct race converges to one intro row and one system message on the receiver | Delivery-tier race convergence |
| re-introducing the same pair refreshes instead of duplicating | Upsert via P2P |
| expired intro can be reintroduced as a fresh pending flow | Post-expiry refresh via P2P |
| B passes all intros -> no connections | Full pass path |
| expired intros: 31-day-old not in pending | Expiry filtering |
| one-sided accept then complete | Partial then full accept |
| mutual acceptance surfaces correctly on both nodes | Cross-node convergence |
| accept happy path encrypts notification to stranger via v2 | v2 on accept |
| pass notification to stranger uses v2 encryption | v2 on pass |
| full cross-step chain: send -> accept -> verify | Chained flow |

### 5.2 Intro Wiring Smoke
**File:** `test/features/introduction/integration/intro_wiring_smoke_test.dart`

| Test | What it covers |
|------|----------------|
| banner shows when all deps wired | DI wiring |
| tapping "Make introductions" opens FriendPickerScreen | Navigation |
| picker excludes recipient from list | Friend filtering |
| select friend -> tap Introduce -> record saved | Full send wiring |
| tap does nothing when introductionRepository is null | Null-safety guard |
| "Maybe later" dismisses and persists | Dismiss persistence |
| banner hidden when 0 other friends | Empty guard |
| picker keeps already-introduced friends available for re-send | Re-introduction |

### 5.3 Multi-Node
**File:** `test/features/introduction/integration/introduction_multi_node_test.dart`

| Test | What it covers |
|------|----------------|
| A sends intros -> B receives via listener stream | Send → receive (B) |
| A sends intros -> C receives via listener stream | Send → receive (C) |
| B accepts -> C view reflects recipient acceptance while overall stays pending | Partial acceptance visibility |
| B accepts, C passes -> no mutualAccepted | Pass overrides |
| B accepts, C accepts -> mutual acceptance | Full acceptance |
| mutual acceptance data correct on both nodes | Cross-node data integrity |
| mutual acceptance -> both appear in each other's contact repo | Contact creation both sides |
| mutual acceptance -> contacts have correct introducedBy field | introducedBy metadata |
| full cross-step chain -> contacts created after mutual acceptance | Step-by-step lifecycle |
| notifications sent to all parties on accept | Outbound delivery count |
| order independence: C accepts first then B | Accept order |
| concurrent acceptance: both nodes reach mutualAccepted | Race convergence |
| mutual acceptance with v2 encrypted notifications end-to-end | E2E encryption flow |
| A has correct intro record locally | Introducer-side persistence |
| introducer converges to mutualAccepted without duplicate B/C contacts | Introducer convergence without duplicate contacts |
| shouldShowIntroBanner returns false after intros sent | Banner suppression |
| live accept delivery converges for recipient-first order without manual helper injection | Live delivery (B first) |
| live accept delivery converges for introduced-first order without manual helper injection | Live delivery (C first) |
| intro between existing contacts gets alreadyConnected status | Already-connected guard |
| expired intro filtered from pending | Expiry filtering |
| offline relay intro delivery converges to mutual acceptance and first encrypted chat | Offline → inbox → accept → chat |
| dual deferred accept responses replay when the intro arrives and still converge to contacts | Out-of-order replay |
| accept notifications fall back to inbox while peers are unreachable and converge after drain | Inbox fallback convergence |
| pass notifications fall back to inbox while peers are unreachable and converge after drain | Symmetric pass fallback convergence |
| introducer heals after partitioned accept deliveries and converges with B and C | Partition-heal convergence |
| split-brain mutual acceptance heals after reconnect | Waiting-vs-connected recovery after relaunch |
| simultaneous intro chains stay isolated when one passes and the other reaches mutual acceptance | Concurrent chain isolation |
| reintroducing the same pair repairs a missed side and ignores stale older delivery | Re-introduction repair |
| same pair with a different introducer reopens as alreadyConnected without duplicate contacts | Cross-introducer dedup |
| chain and circular introductions create the next edge without regressions | Multi-hop chain (A→B↔C, B→C↔D, C→D↔A) |

### 5.4 Orbit Intros Wiring
**File:** `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`

| Test | What it covers |
|------|----------------|
| pending count > 0 when introductions exist | Badge count |
| pending count is 0 when no introductions | Badge zero state |
| loadIntroductionsForUser returns correct grouped data | Data loading |
| accept callback calls acceptIntroduction use case | Accept wiring |
| pass callback calls passIntroduction use case | Pass wiring |
| intro count refreshes after accept action | Reactive update |
| intro count refreshes after pass action | Reactive update |
| intro count and grouped data refresh after delete action | Reactive update |
| introReceivedStream triggers data availability | Stream wiring |
| introStatusChangedStream triggers on accept notification | Stream wiring |
| IntrosTab built with correct grouped data | Widget data binding |

---

## 6. Regression Tests

**File:** `test/features/introduction/regression/introduction_regression_test.dart`

| Area | Test | What it covers |
|------|------|----------------|
| 1: Pass status | introduced party passes -> statuses correct | Pass state integrity |
| 2: Unknown responderId | unknown responderId -> rejected, no mutation | Invalid responder guard |
| 3: Expired exclusion | expired intro excluded from pending count | Count accuracy |
| 4: Block/unblock banner | block hides banner, unblock restores it | Banner state recovery |
| 5: Concurrent idempotency | handleMutualAcceptance x2 -> 1 contact | Race condition guard |
| 6: One-sided no contact | recipient accepts alone -> no contact | Premature contact guard |
| 7a: Key direction | recipient gets introduced party's keys | Key exchange direction |
| 7b: Key direction | introduced party gets recipient's keys | Key exchange direction |
| 8: Duplicate accept delivery | same accept twice -> no duplicate contacts | Idempotent accept |
| 8b: Duplicate pass delivery | same pass twice -> passed stays terminal with one row | Idempotent pass |
| 9a: Picker exclusion | recipient excluded from friend list | Filtering |
| 9b: Picker exclusion | blocked contacts excluded | Filtering |
| 9c: Picker exclusion | already-introduced contacts stay available | Re-introduction |
| 10: Banner full matrix | all 6 gates -> true; flip each -> false | Exhaustive gate test |
| 11: Encryption fallback | encrypt returns ok=false -> v1 sent | Fallback |
| 12a: Listener resilience | malformed JSON -> silently dropped | Error handling |
| 12b: Listener resilience | missing required fields -> dropped | Error handling |
| 12c: Listener resilience | unknown action -> no emissions | Unknown action |
| 13: v1 fallback | v1 fallback when intro lacks ML-KEM key | Pre-ML-KEM compat |
| 14a: Block + accept | Bob blocks Carol, Carol accept arrives -> completes | Block bypass for handshake |
| 14b: Block + accept | duplicate accept after block -> no crash | Robustness |
| 15: Introducer data path | send + listener -> no unrelated introducer rows | State isolation |

---

## 7. Cross-Feature Tests

### 7.1 IntroductionConnectionCard (Feed)
**File:** `test/features/feed/presentation/widgets/introduction_connection_card_test.dart`

| Test | What it covers |
|------|----------------|
| renders both usernames | Feed card rendering |
| renders "Introduced by X" text | Introducer attribution |
| renders "Send Message" button | CTA rendering |
| calls onSendMessage on button tap | CTA action |
| shows blocked overlay when isBlocked is true | Blocked state |
| disables Send Message button when blocked | Blocked CTA guard |
| does not render Connected text or green check icon | Negative UI check |

### 7.2 Push Notification Routing
**File:** `test/features/push/application/intro_notification_orbit_route_test.dart`

| Test | What it covers |
|------|----------------|
| intro notification route shows persistent nav with orbit active and feed return restores shell | Deep-link navigation from push |
| closing intro notification orbit while still on orbit restores the prior shell tab | Shell tab restoration |

### 7.3 Conversation Overflow Menu
**File:** `test/features/conversation/presentation/screens/conversation_overflow_intro_test.dart`

| Test | What it covers |
|------|----------------|
| "Introduce" visible when >= 1 other friend and not blocked | Menu visibility |
| "Introduce" hidden when 0 other friends | Guard |
| "Introduce" hidden when contact is blocked | Block guard |
| tapping triggers introduce callback | Action wiring |
| still works after introsSentAt is set | Post-send state |

### 7.4 Conversation Banner
**File:** `test/features/conversation/presentation/screens/conversation_banner_test.dart`

| Group | Test | What it covers |
|-------|------|----------------|
| `ConversationScreen banner` | banner shown when showIntroBanner is true and no messages | Visibility gate |
| | banner NOT shown when showIntroBanner is false | Hidden gate |
| | "Make introductions" callback triggers | CTA action |
| | "Maybe later" callback triggers | Dismiss action |
| | banner text shows contact username | Username rendering |
| | banner renders IntroBanner widget | Widget type check |
| `shouldShowIntroBanner use case` | returns false when all contacts blocked (no eligible friends) | Blocked friends gate |
| | returns false after dismiss | Dismiss gate |
| | returns false after intros sent | Sent gate |
| | auto-dismiss: returns false after 3 messages | Message count gate |
| | banner state refreshes when contact is blocked | Reactive block state |

### 7.5 Push Open Flow
**File:** `test/features/push/application/chat_and_group_push_open_flow_test.dart`

| Test | What it covers |
|------|----------------|
| intros push opens only after inbox preparation | Push deep-link sequencing for intros type |

### 7.6 Background Push Fallback
**File:** `test/features/push/application/background_push_notification_fallback_test.dart`

| Test | What it covers |
|------|----------------|
| shows fallback for intros type | Background push displays notification for intro events |
| preserves provided copy for a new-introduction intros fallback | Push-backed new-intro notification copy |
| preserves provided role-correct copy for an introducer mutual-accept intros fallback | Push-backed introducer mutual-accept notification copy |
| shows fallback for group_invite type and routes to intros | Group invite push routes to intros tab |

### 7.7 Orbit Wired (intro-related subset)
**File:** `test/features/orbit/presentation/screens/orbit_wired_test.dart`

| Test | What it covers |
|------|----------------|
| startup repairs a stale persisted mutual acceptance row | Lifecycle reconciliation on boot |
| live intro delete confirmation removes the row, clears the badge, and marks route-return refresh | Delete confirmation flow |
| canceling live intro delete keeps the row and badge count | Delete cancellation guard |
| pending group invites are visible from the Intros tab and counted in the Orbit badge | Group invite in intros UI |
| accepting a pending group invite from Intros joins the group | Group join from intros tab |

### 7.8 Orbit Screen (intro review widget subset)
**File:** `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`

| Test | What it covers |
|------|----------------|
| shows archived groups in archived tab even when no archived friends | Archived groups remain visible without archived friends |
| shows empty state when no archived friends and no groups | Archived empty state |
| shows groups in all tab | Group rendering in default view |
| renders intros in the sliver list without nested ListView | Orbit intro review sliver rendering |
| intros tab renders grouped intros and carries the correct pending count | Orbit intro grouping plus `Intros` count truth |
| hides the intro banner when there are no pending review items | Orbit intro banner hidden state for zero pending intros |
| shows singular intro banner copy for one pending intro | Orbit intro banner singular pending-count copy |
| shows plural intro banner copy for multiple pending intros | Orbit intro banner plural pending-count copy |
| live intro row reveals delete on swipe | Orbit intro row swipe affordance |

---

## 8. Coverage Gaps

Areas of the introduction feature with remaining gaps, or recently closed seams
that used to lack direct coverage:

### 8.1 Data Layer
- **DB helper functions**: Covered on 2026-04-13 by `intro_db_helpers_test.dart`,
  which directly exercises pending intro visibility, pending count truth,
  deferred-response replay ordering, and retryable outbox selection, plus a
  green rerun of `flutter test --no-pub test/core/database`.
- **Migrations 019, 022, 023, 025, 047**: Covered on 2026-04-13 by
  `intro_migrations_test.dart`, which directly verifies intro table creation,
  key-column additions, `already_connected` rebuild behavior, and intro outbox
  schema/index creation, plus a green rerun of `flutter test --no-pub test/core/database`.

### 8.2 Application Layer
- **Delivery cascade tiers**: The local/direct race is now covered on 2026-04-09 by `local/direct race converges to one intro row and one system message on the receiver` in `test/features/introduction/integration/introduction_smoke_test.dart`, and relay probe is covered by `relay-probe fallback delivers after the direct path fails` in `test/features/introduction/application/introduction_outbound_delivery_test.dart`; the already-connected fast path still is not tested in isolation.
- **retryPendingIntroductionDeliveries on app resume**: Covered on 2026-04-09 by `retryPendingIntroductionDeliveries processes multiple stalled and failed rows and cleans delivered inbox rows` in `test/features/introduction/application/introduction_outbound_delivery_test.dart` plus the existing intro-retry ordering proof in `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart`.
- **insertIntroSystemMessage**: No dedicated tests (covered indirectly by `create_connection_on_mutual_acceptance_test` and listener tests).
- **Avatar download on mutual acceptance**: Covered on 2026-04-13 by the no-rollback regression plus `existing mutual-acceptance contact without avatar retries settlement without duplicating system message` in `test/features/introduction/application/create_connection_on_mutual_acceptance_test.dart`, `later recovery settles avatar for an already-mutual-accepted contact without duplicating side effects` in `test/features/introduction/application/expire_old_introductions_use_case_test.dart`, and green reruns of `flutter test --no-pub test/features/introduction/application`, `./scripts/run_test_gates.sh intro`, and `./scripts/run_test_gates.sh baseline`.
- **Batch progress callback edge cases**: Partial batch failure mid-stream, network drop during batch.
- **Flow-event contract inventory**: No dedicated tests pin intro-specific event family names, including contact intro banner/sent-at persistence events and intro retry orchestration events.

### 8.3 Presentation Layer
- **OrbitScreen intro review grouping and count**: Covered on 2026-04-09 by `renders intros in the sliver list without nested ListView` and `intros tab renders grouped intros and carries the correct pending count` in `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`, plus the existing wiring checks in `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`.
- **Orbit intro banner variant**: Covered on 2026-04-09 by `hides the intro banner when there are no pending review items`, `shows singular intro banner copy for one pending intro`, and `shows plural intro banner copy for multiple pending intros` in `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`.
- **IntroRow exact copy**: Covered on 2026-04-09 by `mutualAccepted state shows Message CTA and invokes callback` in `test/features/introduction/presentation/widgets/intro_row_test.dart`, while `alreadyConnected state shows status only and no actions` already pinned the `Already connected` label.
- **FriendPickerWired error states**: Happy-path filtering and the full load/search/select/send/progress/callback flow are now covered on 2026-04-09 in `friend_picker_wired_test.dart`; identity-missing and send-failure paths still lack dedicated tests.
- **SentConfirmationWired extra variants**: Happy-path pass-through is now covered on 2026-04-09 in `sent_confirmation_wired_test.dart`; only richer stateful variants remain unneeded because the wrapper is still a pure pass-through.

### 8.4 Integration / E2E
- **True multi-device simulation**: Host-side multi-node coverage still uses in-memory fakes, but targeted three-simulator proof now exists for visible copy, partial fan-out recovery, sender-side repair, partition-heal intro convergence, split-brain waiting-vs-connected recovery, offline-relay-to-first-chat recovery, and symmetric pass-fallback drain. Several later matrix rows still lack their own transport-level proof.
- **Partial intro fan-out delivery**: Covered on 2026-04-08 by `INTRO_E2E_SCENARIO=partial ./smoke_test_friends.sh`, the delayed same-intro recovery regression in `test/features/introduction/integration/introduction_multi_node_test.dart`, and green intro/transport gates; later regressions should keep using the same `partial` path rather than weaker resend-only repair coverage.
- **Partition-heal intro convergence**: Covered on 2026-04-09 by `INTRO_E2E_SCENARIO=partition ./smoke_test_friends.sh`, the partition-heal regression in `test/features/introduction/integration/introduction_multi_node_test.dart`, and a green rerun of `./scripts/run_test_gates.sh intro`.
- **Split-brain mutual acceptance recovery**: Covered on 2026-04-09 by `INTRO_E2E_SCENARIO=split-brain ./smoke_test_friends.sh`, the split-brain recovery regression in `test/features/introduction/integration/introduction_multi_node_test.dart`, and a green rerun of `./scripts/run_test_gates.sh intro`.
- **Concurrent intro-chain isolation**: Covered on 2026-04-09 by the concurrent-chain isolation regression in `test/features/introduction/integration/introduction_multi_node_test.dart` and a green rerun of `./scripts/run_test_gates.sh intro`.
- **Offline relay intro to first chat**: Covered on 2026-04-09 by `INTRO_E2E_SCENARIO=offline-chat ./smoke_test_friends.sh`, the offline-relay-to-first-chat regression in `test/features/introduction/integration/introduction_multi_node_test.dart`, and a green rerun of `./scripts/run_test_gates.sh intro`.
- **Pass fallback after unreachable peers**: Covered on 2026-04-09 by `INTRO_E2E_SCENARIO=pass-fallback ./smoke_test_friends.sh`, the pass-fallback inbox regression in `test/features/introduction/integration/introduction_multi_node_test.dart`, and a green rerun of `./scripts/run_test_gates.sh intro`.
- **Push notification trigger path**: Exact intro title/body content is now covered on 2026-04-13 across the introducer- and participant-role listener regressions in `introduction_listener_test.dart`, the introducer copy helpers in `introduction_copy_test.dart`, the role-correct intro fallback copy regression in `background_push_notification_fallback_test.dart`, and green reruns of `./scripts/run_test_gates.sh intro` plus `./scripts/run_test_gates.sh baseline`; end-to-end FCM/APNs trigger delivery still is not exercised beyond routing.
- **Post-expiry re-introduction**: Covered on 2026-04-09 by the expired-refresh regressions in `test/features/introduction/application/send_introduction_test.dart` and `test/features/introduction/integration/introduction_smoke_test.dart`, plus a green rerun of `./scripts/run_test_gates.sh intro`.
- **Sender-side persistence window**: Covered on 2026-04-09 by the `send_introduction_test.dart` crash-window regression, `INTRO_E2E_SCENARIO=repair ./smoke_test_friends.sh`, and green intro/transport gates; future regressions should keep using the same repair path.

### 8.5 Security
- **Replay attack**: Covered on 2026-04-09 by the duplicate-send and duplicate-accept listener regressions in `test/features/introduction/application/introduction_listener_test.dart`, the late-delivery replay regression in `test/features/introduction/integration/introduction_multi_node_test.dart`, the blocked duplicate-accept idempotency regression in `test/features/introduction/regression/introduction_regression_test.dart`, and a green rerun of `./scripts/run_test_gates.sh intro`.
- **Tampered payload**: Covered on 2026-04-09 by `tampered v2 ciphertext rejects intro, stores nothing, and logs failure` in `test/features/introduction/application/introduction_listener_test.dart` and a green rerun of `./scripts/run_test_gates.sh intro`.
- **Key mismatch escalation**: Covered on 2026-04-09 by `rejects intro/contact stranger ML-KEM mismatches before mutation` in both `test/features/introduction/application/accept_introduction_test.dart` and `test/features/introduction/application/pass_introduction_test.dart`, plus a green rerun of `./scripts/run_test_gates.sh intro`.
- **Envelope messageId normalization**: Covered on 2026-04-09 by the `introduction_payload_test.dart` regressions that scope retry IDs per action/sender and patch missing `messageId` values without breaking legacy top-level `id` envelopes, plus a green rerun of `./scripts/run_test_gates.sh intro`.
- **Relay inbox action-split dedupe**: Covered on 2026-04-13 by `TestInboxStoreDedup_IntroductionPlaintextDifferentActionMessageIDs` and `TestInboxStoreDedup_IntroductionEncryptedDifferentActionMessageIDs` in `go-relay-server/inbox_dedup_test.go`, plus green reruns of `cd go-relay-server && go test ./... -run 'TestInboxStoreDedup_Introduction'` and `cd go-relay-server && go test ./...`; this directly proves relay storage keeps `send` and later `accept` intro envelopes for the same `introductionId` separate when their top-level action-scoped `messageId` values differ, while exact duplicate retries still dedupe.
- **Terminal stale delivery**: Covered on 2026-04-09 by the `handle_incoming_introduction_test.dart` regressions that keep `passed`, `expired`, and `alreadyConnected` rows from being replaced by stale pending sends, plus a green rerun of `./scripts/run_test_gates.sh intro`.
