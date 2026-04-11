# MessageContextOverlay Test Matrix Row Breakdown

## Recommended Plan Count

- Recommended plan count: 88
- Row-owned sessions: 88
- Shared prerequisite sessions added: 0
- Final closure-only session added: 0

## Decomposition Artifact

- Created from: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md
- Written to: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Decomposition date: 2026-04-10
- Decomposition mode: strict row-by-row, one source row = one session
- Duplicate rows detected: none
- Row-owned prerequisite-blocked sessions: none
- Disposition summary: covered_in_repo=12, needs_tests_only=52, needs_code_and_tests=24, blocked_by_prerequisite=0

## Overall Closure Bar

- Overall status: closed
- This breakdown closes only because every source row is now backed by exact repo-local proof or completed through its own row-owned plan and the source matrix has been updated with concrete evidence.
- The formerly prerequisite-blocked rows `DL-010`, `DL-020`, `SC-001`, and `SC-009` are now closed through the landed state-aware notification-open first-render harness in `integration_test/notification_open_ui_smoke_test.dart`.
- Do not treat broad chat-message happy-path coverage as sufficient closure for overlay-specific requirements such as quotedMessageId, editedAt, delete tombstones, reaction replacement, or delete-before-open startup rendering.
- Degraded local continuation mode is active for this rollout as of 2026-04-10 because fresh-child agent materialization is not available in this environment; the controller is persisting ledger and doc updates locally after each processed session per the user's continuation instruction.

## Source Of Truth

- Primary matrix: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md
- Adjacent breakdown artifact: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Shared blocked-row prerequisite plan: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_blocked_startup_deeplink_unblock_plan.md
- Repo evidence was kept conservative: a row is marked covered_in_repo only where an exact existing test already proves the journey.
- C4 feature notes in the same folder remain useful background, but current repo code/tests take precedence over stale prose when the two disagree.

## Matrix Row Inventory

| Source Row ID | Scenario | Priority | Source Section | Provisional Row Disposition | Intended Session ID | duplicate_of |
| --- | --- | --- | --- | --- | --- | --- |
| OG-001 | Long-press on a supported non-deleted message opens the overlay and backdrop dismiss is side-effect free | P0 | Overlay Lifecycle, Gating, and Host Consistency | needs_tests_only | OG-001 | - |
| OG-002 | Conversation host and feed direct-thread host stay behaviorally aligned | P1 | Overlay Lifecycle, Gating, and Host Consistency | needs_tests_only | OG-002 | - |
| OG-003 | Action order and stable keys remain correct when all optional actions are available | P0 | Overlay Lifecycle, Gating, and Host Consistency | needs_tests_only | OG-003 | - |
| OG-004 | Deleted or tombstoned rows cannot reopen a mutating overlay | P0 | Overlay Lifecycle, Gating, and Host Consistency | needs_tests_only | OG-004 | - |
| OG-005 | Media-only, whitespace-only, and system-message variants gate actions correctly | P0 | Overlay Lifecycle, Gating, and Host Consistency | needs_tests_only | OG-005 | - |
| OG-006 | Busy composer states suppress only Edit, not unrelated actions | P1 | Overlay Lifecycle, Gating, and Host Consistency | needs_tests_only | OG-006 | - |
| OG-007 | Delete uses overlay-pop then next-frame sheet sequencing | P0 | Overlay Lifecycle, Gating, and Host Consistency | needs_tests_only | OG-007 | - |
| OG-008 | Copy remains safe if the screen is disposed during the async clipboard call | P0 | Overlay Lifecycle, Gating, and Host Consistency | needs_tests_only | OG-008 | - |
| OG-009 | Rapid repeat long-presses and rapid action taps do not double-apply effects | P1 | Overlay Lifecycle, Gating, and Host Consistency | needs_code_and_tests | OG-009 | - |
| OG-010 | Localized, RTL, and long-content overlays stay readable and clamped to the viewport | P2 | Overlay Lifecycle, Gating, and Host Consistency | needs_tests_only | OG-010 | - |
| RX-001 | Add a preset reaction from the overlay happy path | P0 | Reactions | needs_tests_only | RX-001 | - |
| RX-002 | Tapping the same emoji toggles the reaction off | P0 | Reactions | needs_tests_only | RX-002 | - |
| RX-003 | Tapping a different emoji replaces the previous own reaction instead of creating duplicates | P0 | Reactions | needs_tests_only | RX-003 | - |
| RX-004 | Full picker non-preset emoji round-trips correctly | P1 | Reactions | needs_tests_only | RX-004 | - |
| RX-005 | Same-emoji reactions from A and B group into one chip with a count and own highlight | P1 | Reactions | needs_tests_only | RX-005 | - |
| RX-006 | Tapping an inline reaction chip uses the same toggle / replace semantics as the overlay bar | P1 | Reactions | needs_tests_only | RX-006 | - |
| RX-007 | Reaction from a blocked sender is ignored | P0 | Reactions | covered_in_repo | RX-007 | - |
| RX-008 | Plaintext, tampered, or undecryptable reactions are rejected without local mutation | P0 | Reactions | covered_in_repo | RX-008 | - |
| RX-009 | Duplicate add and duplicate remove deliveries are idempotent | P0 | Reactions | needs_tests_only | RX-009 | - |
| RX-010 | Out-of-order add/remove deliveries resolve by newest logical state | P1 | Reactions | needs_code_and_tests | RX-010 | - |
| RX-011 | `sendMessage=false` and `storeInInbox=false` must not look like success | P0 | Reactions | needs_code_and_tests | RX-011 | - |
| RX-012 | Reactions targeting an unknown or missing message do not create orphan rows | P0 | Reactions | covered_in_repo | RX-012 | - |
| RX-013 | Listener start/stop/dispose does not create duplicate reaction application | P1 | Reactions | covered_in_repo | RX-013 | - |
| CP-001 | Copy happy path in the conversation host | P0 | Copy | covered_in_repo | CP-001 | - |
| CP-002 | Copy happy path in the shared feed direct-thread host | P1 | Copy | covered_in_repo | CP-002 | - |
| CP-003 | Copy is hidden for deleted, media-only, and whitespace-only rows | P0 | Copy | covered_in_repo | CP-003 | - |
| CP-004 | Multiline, emoji, and RTL text are copied exactly | P1 | Copy | covered_in_repo | CP-004 | - |
| CP-005 | Rapid repeated copy hides the old snackbar before showing the new one | P2 | Copy | covered_in_repo | CP-005 | - |
| CP-006 | ConversationScreen copy remains safe if the widget is disposed after the clipboard await starts | P0 | Copy | covered_in_repo | CP-006 | - |
| CP-007 | FeedScreen copy remains safe after context changes because messenger and l10n are captured before await | P0 | Copy | covered_in_repo | CP-007 | - |
| CP-008 | Copy never touches repo, bridge, or P2P collaborators | P0 | Copy | needs_tests_only | CP-008 | - |
| RP-001 | Reply from the overlay enters quote mode and focuses the composer | P0 | Reply / Quote Reply | needs_tests_only | RP-001 | - |
| RP-002 | Swipe-to-reply is offered only for incoming non-deleted messages and joins the same quote flow | P1 | Reply / Quote Reply | needs_tests_only | RP-002 | - |
| RP-003 | Quote preview resolves text, media preview text, or unavailable state | P0 | Reply / Quote Reply | needs_tests_only | RP-003 | - |
| RP-004 | Clearing a quote removes the preview and the next send has no `quotedMessageId` | P0 | Reply / Quote Reply | needs_tests_only | RP-004 | - |
| RP-005 | Sending a reply preserves `quotedMessageId` locally and remotely | P0 | Reply / Quote Reply | covered_in_repo | RP-005 | - |
| RP-006 | Failed reply send restores the full composer snapshot | P0 | Reply / Quote Reply | needs_code_and_tests | RP-006 | - |
| RP-007 | Incoming reply remains readable even when the quoted source does not exist locally | P0 | Reply / Quote Reply | covered_in_repo | RP-007 | - |
| RP-008 | If the quoted source is later deleted, existing replies degrade gracefully to unavailable | P1 | Reply / Quote Reply | needs_tests_only | RP-008 | - |
| RP-009 | If the quoted source is later edited, reply rendering stays stable | P2 | Reply / Quote Reply | needs_code_and_tests | RP-009 | - |
| RP-010 | Offline / inbox delivery preserves `quotedMessageId` across restart | P1 | Reply / Quote Reply | needs_code_and_tests | RP-010 | - |
| RP-011 | Conversation and feed direct-thread hosts keep reply behavior aligned | P1 | Reply / Quote Reply | needs_tests_only | RP-011 | - |
| RP-012 | Starting a reply clears active edit mode so both modes cannot coexist | P1 | Reply / Quote Reply | needs_code_and_tests | RP-012 | - |
| ED-001 | Edit overlay visibility follows the full eight-condition gate | P0 | Edit | needs_tests_only | ED-001 | - |
| ED-002 | Latest-sent scanning skips deleted outgoing rows and ignores newer incoming rows | P0 | Edit | needs_tests_only | ED-002 | - |
| ED-003 | Tapping Edit enters edit mode, pre-fills text, clears quote mode, and shows the banner | P0 | Edit | needs_tests_only | ED-003 | - |
| ED-004 | Canceling edit clears the banner and edit state | P0 | Edit | needs_tests_only | ED-004 | - |
| ED-005 | Submitting unchanged text is a silent cancel | P0 | Edit | needs_tests_only | ED-005 | - |
| ED-006 | Successful edit reuses the original ID, preserves timestamp / createdAt, sets `editedAt`, and renders `(edited)` on both sides | P0 | Edit | needs_tests_only | ED-006 | - |
| ED-007 | Deleted messages suppress the edited indicator even if `editedAt` exists | P0 | Edit | needs_tests_only | ED-007 | - |
| ED-008 | Deleting the message currently being edited exits edit mode immediately | P0 | Edit | needs_code_and_tests | ED-008 | - |
| ED-009 | Incoming edit that arrives before the original does not create a phantom row and later converges correctly | P0 | Edit | needs_code_and_tests | ED-009 | - |
| ED-010 | Duplicate and stale edit deliveries are idempotent and newest edit wins | P0 | Edit | needs_code_and_tests | ED-010 | - |
| ED-011 | Unauthorized edit for someone else’s message is rejected | P0 | Edit | needs_code_and_tests | ED-011 | - |
| ED-012 | Offline / inbox edit delivery survives restart and applies correctly once drained | P1 | Edit | needs_code_and_tests | ED-012 | - |
| ED-013 | Late edit cannot resurrect text after delete | P0 | Edit | needs_code_and_tests | ED-013 | - |
| ED-014 | Conversation and feed direct-thread hosts keep edit behavior aligned | P1 | Edit | needs_tests_only | ED-014 | - |
| ED-015 | v2 preferred / v1 fallback preserves `action='edit'` and `editedAt` | P1 | Edit | needs_tests_only | ED-015 | - |
| DL-001 | Delete visibility in the overlay follows the local gate | P0 | Delete | needs_tests_only | DL-001 | - |
| DL-002 | “Delete for everyone” visibility in the confirmation sheet follows the second gate | P0 | Delete | needs_tests_only | DL-002 | - |
| DL-003 | Canceling or dismissing the delete sheet is a no-op | P1 | Delete | needs_tests_only | DL-003 | - |
| DL-004 | “Delete for me” hard-deletes the local row and cleans local artifacts only | P0 | Delete | covered_in_repo | DL-004 | - |
| DL-005 | Owned-path guard deletes only files belonging to the message | P0 | Delete | needs_tests_only | DL-005 | - |
| DL-006 | “Delete for everyone” happy path over live delivery converges on both sides | P0 | Delete | covered_in_repo | DL-006 | - |
| DL-007 | Live send without final ack keeps a visible retryable tombstone | P0 | Delete | needs_code_and_tests | DL-007 | - |
| DL-008 | Full delivery failure yields a visible failed tombstone and no false disappearance | P0 | Delete | needs_tests_only | DL-008 | - |
| DL-009 | Inbox success hides the sender row locally and later deletes on the receiver after drain | P0 | Delete | covered_in_repo | DL-009 | - |
| DL-010 | Critical regression: delete-for-everyone before the recipient opens the app | P0 | Delete | needs_tests_only | DL-010 | - |
| DL-011 | Delete arriving before the original due to transport reordering still prevents plaintext resurrection | P0 | Delete | needs_code_and_tests | DL-011 | - |
| DL-012 | Duplicate delete deliveries are idempotent | P0 | Delete | needs_tests_only | DL-012 | - |
| DL-013 | Unauthorized delete from a non-authorized sender is rejected | P0 | Delete | covered_in_repo | DL-013 | - |
| DL-014 | Undecryptable or key-missing v2 delete is rejected without mutation | P0 | Delete | needs_tests_only | DL-014 | - |
| DL-015 | Delete cleanup clears reactions, media, and local edit / quote state linked to the target row | P0 | Delete | needs_code_and_tests | DL-015 | - |
| DL-016 | Late reaction or late edit after delete cannot resurrect visible content | P0 | Delete | needs_code_and_tests | DL-016 | - |
| DL-017 | Sender restart after pending tombstone persistence still converges to the correct visibility state | P1 | Delete | needs_code_and_tests | DL-017 | - |
| DL-018 | Conversation and feed direct-thread hosts keep delete behavior aligned | P1 | Delete | needs_tests_only | DL-018 | - |
| DL-019 | Delete from a now-blocked sender still follows one explicit, tested policy for already-stored authored messages | P1 | Delete | needs_code_and_tests | DL-019 | - |
| DL-020 | Notification deep-link / cold-start open after delete never shows the original inside the app shell | P0 | Delete | needs_tests_only | DL-020 | - |
| SC-001 | App restart reconstructs quote, edit, delete, and reaction state from durable storage without stale UI | P0 | Security, Ordering, Recovery, and Cross-Feature Convergence | needs_tests_only | SC-001 | - |
| SC-002 | While the conversation is open or backgrounded, incoming reaction / edit / delete changes converge without manual refresh | P0 | Security, Ordering, Recovery, and Cross-Feature Convergence | needs_tests_only | SC-002 | - |
| SC-003 | Stream sender, top-level envelope sender, and decrypted payload sender must agree for mutating actions | P0 | Security, Ordering, Recovery, and Cross-Feature Convergence | needs_code_and_tests | SC-003 | - |
| SC-004 | Concurrent actions on the same message resolve to one deterministic winner state | P0 | Security, Ordering, Recovery, and Cross-Feature Convergence | needs_code_and_tests | SC-004 | - |
| SC-005 | Listener / subscription lifecycle never causes duplicate application or leaks | P0 | Security, Ordering, Recovery, and Cross-Feature Convergence | needs_tests_only | SC-005 | - |
| SC-006 | Schema migration / upgrade preserves old messages and loads new overlay state fields safely | P1 | Security, Ordering, Recovery, and Cross-Feature Convergence | needs_tests_only | SC-006 | - |
| SC-007 | Localization, mixed-script, and RTL content stay correct across quote bars, deleted placeholders, edited indicators, snackbars, and reaction chips | P2 | Security, Ordering, Recovery, and Cross-Feature Convergence | needs_tests_only | SC-007 | - |
| SC-008 | After restart, conversation and feed direct-thread surfaces reconstruct the same visible truth | P1 | Security, Ordering, Recovery, and Cross-Feature Convergence | needs_code_and_tests | SC-008 | - |
| SC-009 | In-app deep-link render after background edit or delete resolves to the latest state | P1 | Security, Ordering, Recovery, and Cross-Feature Convergence | needs_tests_only | SC-009 | - |
| SC-010 | Queued mutating actions converge after reconnect or remain explicitly retryable with a reason | P0 | Security, Ordering, Recovery, and Cross-Feature Convergence | needs_code_and_tests | SC-010 | - |

## Row Traceability Rule

- Every source row maps to exactly one session id in this artifact or one explicit duplicate_of relationship.
- Session ids preserve the original source row ids because every source id in this matrix is filename-safe.
- Later closure work must report final truth per source row, not only per subsystem or feature bucket.

## Session Ledger

| Session ID | Source Row ID | Priority | Source Section | Row Disposition | Session Classification | Dependency | Intended Plan File | Current status | Execution verdict | Matrix / closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| OG-001 | OG-001 | P0 | Overlay Lifecycle, Gating, and Host Consistency | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-OG-001-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun conversation-host overlay open and backdrop-dismiss evidence from `conversation_screen_test.dart`. |
| OG-003 | OG-003 | P0 | Overlay Lifecycle, Gating, and Host Consistency | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-OG-003-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun stable keyed overlay action-order evidence from `message_context_overlay_test.dart`. |
| OG-004 | OG-004 | P0 | Overlay Lifecycle, Gating, and Host Consistency | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-OG-004-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun deleted-row inertness evidence from `conversation_screen_test.dart` and `feed_screen_test.dart`. |
| OG-005 | OG-005 | P0 | Overlay Lifecycle, Gating, and Host Consistency | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-OG-005-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun media-only, whitespace-only, and system-row gating evidence from `conversation_screen_test.dart` and `feed_screen_test.dart`. |
| OG-007 | OG-007 | P0 | Overlay Lifecycle, Gating, and Host Consistency | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-OG-007-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Tightened `conversation_screen_test.dart` to prove delete callbacks stay single-fire, the sheet does not appear on the first post-tap frame, and a rapid second tap does not queue a duplicate delete sheet. |
| OG-008 | OG-008 | P0 | Overlay Lifecycle, Gating, and Host Consistency | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-OG-008-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun conversation and feed async clipboard safety evidence from `conversation_screen_test.dart` and `feed_screen_test.dart`. |
| RX-001 | RX-001 | P0 | Reactions | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-001-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun preset-reaction happy-path evidence from `send_reaction_use_case_test.dart` and `emoji_reaction_exchange_test.dart`. |
| RX-002 | RX-002 | P0 | Reactions | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-002-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun same-emoji toggle-off evidence from `remove_reaction_use_case_test.dart` and `emoji_reaction_exchange_test.dart`. |
| RX-003 | RX-003 | P0 | Reactions | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-003-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun replace/upsert evidence from `emoji_reaction_exchange_test.dart` and `016_message_reactions_test.dart`. |
| RX-007 | RX-007 | P0 | Reactions | covered_in_repo | stale/already-covered | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-007-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with exact listener evidence for blocked-sender rejection. |
| RX-008 | RX-008 | P0 | Reactions | covered_in_repo | stale/already-covered | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-008-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with exact v1/decrypt-failure rejection evidence. |
| RX-009 | RX-009 | P0 | Reactions | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-009-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun duplicate add/remove idempotency evidence from `handle_incoming_reaction_use_case_test.dart`. |
| RX-011 | RX-011 | P0 | Reactions | needs_code_and_tests | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-011-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun add/remove send-failure evidence from `send_reaction_use_case_test.dart` and `remove_reaction_use_case_test.dart`. |
| RX-012 | RX-012 | P0 | Reactions | covered_in_repo | stale/already-covered | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-012-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-012-plan.md | Landed target-message guards plus direct use-case and listener tests so missing or deleted targets do not create orphan reactions. |
| CP-001 | CP-001 | P0 | Copy | covered_in_repo | stale/already-covered | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-CP-001-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with the rerun conversation host copy proof. |
| CP-003 | CP-003 | P0 | Copy | covered_in_repo | stale/already-covered | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-CP-003-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with deleted, media-only, and whitespace-only copy gating evidence across conversation and feed hosts. |
| CP-006 | CP-006 | P0 | Copy | covered_in_repo | stale/already-covered | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-CP-006-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun conversation clipboard-dispose safety proof. |
| CP-007 | CP-007 | P0 | Copy | covered_in_repo | stale/already-covered | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-CP-007-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun feed host async clipboard safety proof. |
| CP-008 | CP-008 | P0 | Copy | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-CP-008-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun collaborator-isolation evidence from `conversation_wired_test.dart`. |
| RP-001 | RP-001 | P0 | Reply / Quote Reply | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RP-001-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun overlay-reply focus and quote-entry evidence from `conversation_wired_test.dart`. |
| RP-003 | RP-003 | P0 | Reply / Quote Reply | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RP-003-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with existing text, media-preview, and unavailable quote evidence from `conversation_screen_test.dart`. |
| RP-004 | RP-004 | P0 | Reply / Quote Reply | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RP-004-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun clear-quote and unquoted-send evidence from `conversation_wired_test.dart`. |
| RP-005 | RP-005 | P0 | Reply / Quote Reply | covered_in_repo | stale/already-covered | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RP-005-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun `quotedMessageId` end-to-end and payload-round-trip evidence from `quote_reply_thread_test.dart`. |
| RP-006 | RP-006 | P0 | Reply / Quote Reply | needs_code_and_tests | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RP-006-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun reply-send failure restore evidence from `conversation_wired_test.dart`. |
| RP-007 | RP-007 | P0 | Reply / Quote Reply | covered_in_repo | stale/already-covered | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RP-007-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun missing-quoted-source reply evidence from `quote_reply_thread_test.dart`. |
| ED-001 | ED-001 | P0 | Edit | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-001-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Tightened `conversation_screen_test.dart` to cover the disabled, unwired, missing-identity, incoming, foreign-owner, whitespace, deleted-skip, and latest-live-outgoing edit gates, then updated the matrix with the exact gate evidence. |
| ED-002 | ED-002 | P0 | Edit | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-002-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun last-sent scanning evidence from `conversation_screen_test.dart`. |
| ED-003 | ED-003 | P0 | Edit | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-003-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun edit-entry prefill and quote-clearing evidence from `conversation_wired_test.dart`. |
| ED-004 | ED-004 | P0 | Edit | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-004-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun cancel-edit banner/state cleanup evidence from `conversation_screen_test.dart` and `conversation_wired_test.dart`. |
| ED-005 | ED-005 | P0 | Edit | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-005-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun unchanged-edit no-op evidence from `conversation_wired_test.dart`. |
| ED-006 | ED-006 | P0 | Edit | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-006-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun sender edit-contract, same-id inbound edit, and edited-indicator render evidence from `send_chat_message_use_case_test.dart`, `conversation_wired_test.dart`, `handle_incoming_chat_message_use_case_test.dart`, `letter_card_test.dart`, and `message_bubble_test.dart`. |
| ED-007 | ED-007 | P0 | Edit | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-007-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with existing deleted-placeholder-over-edited-indicator evidence from `message_bubble_test.dart`. |
| ED-008 | ED-008 | P0 | Edit | needs_code_and_tests | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-008-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun delete-during-edit cleanup evidence from `conversation_wired_test.dart`. |
| ED-009 | ED-009 | P0 | Edit | needs_code_and_tests | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-009-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Landed hidden inbound edit placeholders plus listener and inbox regressions so edit-first delivery stays phantom-free and later materializes the newest edited row once the original arrives. |
| ED-010 | ED-010 | P0 | Edit | needs_code_and_tests | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-010-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Landed latest-wins edit guards and reran `handle_incoming_chat_message_use_case_test.dart` so duplicate or stale edits no longer overwrite a newer edit. |
| ED-011 | ED-011 | P0 | Edit | needs_code_and_tests | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-011-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Landed inbound edit authorization guards and direct tests for cross-author edit rejection without mutating the stored row. |
| ED-013 | ED-013 | P0 | Edit | needs_code_and_tests | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-013-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Landed deleted-target edit suppression and reran `handle_incoming_chat_message_use_case_test.dart` so late edits cannot resurrect deleted content. |
| DL-001 | DL-001 | P0 | Delete | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-001-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun local delete-gate evidence from `conversation_screen_test.dart`. |
| DL-002 | DL-002 | P0 | Delete | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-002-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun delete-for-everyone second-gate evidence from `conversation_wired_test.dart`, with deleted-row gating still proven by `conversation_screen_test.dart`. |
| DL-004 | DL-004 | P0 | Delete | covered_in_repo | stale/already-covered | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-004-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun delete-for-me cleanup evidence from `delete_message_use_case_test.dart`. |
| DL-005 | DL-005 | P0 | Delete | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-005-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun owned-path cleanup evidence from `delete_message_use_case_test.dart` and `handle_incoming_message_deletion_use_case_test.dart`. |
| DL-006 | DL-006 | P0 | Delete | covered_in_repo | stale/already-covered | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-006-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun live delete-for-everyone convergence evidence from `message_deletion_roundtrip_test.dart`. |
| DL-007 | DL-007 | P0 | Delete | needs_code_and_tests | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-007-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Added the exact unacked-live-delivery regression in `delete_message_use_case_test.dart` and confirmed the sender keeps a visible `sent` tombstone with `hiddenAt=null` when inbox fallback also fails. |
| DL-008 | DL-008 | P0 | Delete | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-008-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun failed-tombstone evidence from `delete_message_use_case_test.dart`. |
| DL-009 | DL-009 | P0 | Delete | covered_in_repo | stale/already-covered | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-009-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun inbox delete convergence evidence from `message_deletion_roundtrip_test.dart`. |
| DL-010 | DL-010 | P0 | Delete | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-010-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_blocked_startup_deeplink_unblock_plan.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Added a state-aware notification-open conversation harness in `integration_test/notification_open_ui_smoke_test.dart` and proved a cold remote open applies the stored delete before the first readable conversation frame, so recipient-first-open never surfaces plaintext. |
| DL-011 | DL-011 | P0 | Delete | needs_code_and_tests | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-011-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Landed delete-first tombstone placeholders plus no-resurrection coverage so transport reordering cannot expose plaintext when the original arrives after the delete. |
| DL-012 | DL-012 | P0 | Delete | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-012-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun duplicate-delete idempotency evidence from `handle_incoming_message_deletion_use_case_test.dart`. |
| DL-013 | DL-013 | P0 | Delete | covered_in_repo | stale/already-covered | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-013-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun unauthorized-delete rejection evidence from `handle_incoming_message_deletion_use_case_test.dart`. |
| DL-014 | DL-014 | P0 | Delete | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-014-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun v2 delete decryption-failure evidence from `handle_incoming_message_deletion_use_case_test.dart`. |
| DL-015 | DL-015 | P0 | Delete | needs_code_and_tests | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-015-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Reconciled existing reaction/media cleanup evidence with a new wired-screen regression so deleting a targeted row now clears both edit and quote local state without leaving stale UI. |
| DL-016 | DL-016 | P0 | Delete | needs_code_and_tests | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-016-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Combined deleted-target reaction suppression with deleted-target edit suppression and reran the reaction and chat inbound mutation suites so late stale traffic cannot resurrect visible content. |
| DL-020 | DL-020 | P0 | Delete | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-020-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_blocked_startup_deeplink_unblock_plan.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Extended the same harness with a warm local notification-open regression proving the app-shell conversation frame is already tombstoned when delete is stored before open. |
| SC-001 | SC-001 | P0 | Security, Ordering, Recovery, and Cross-Feature Convergence | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-SC-001-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_blocked_startup_deeplink_unblock_plan.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Extended the harness with a relaunch regression that reuses persisted stores so quote, edit, delete, and reaction state are all correct on the first readable frame after app recreate and reopen. |
| SC-002 | SC-002 | P0 | Security, Ordering, Recovery, and Cross-Feature Convergence | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-SC-002-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Tightened `conversation_wired_test.dart` so incoming reaction, edit, and delete mutations now refresh the open conversation and remain correct after a reopen without any manual refresh path. |
| SC-003 | SC-003 | P0 | Security, Ordering, Recovery, and Cross-Feature Convergence | needs_code_and_tests | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-SC-003-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Landed stream/envelope/payload sender-agreement guards for edit, reaction, and delete handling plus direct mismatch tests for plaintext and v2 encrypted paths. |
| SC-004 | SC-004 | P0 | Security, Ordering, Recovery, and Cross-Feature Convergence | needs_code_and_tests | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-SC-004-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Reconciled concurrent winner-state proof with a new async copy/delete race regression plus targeted late-edit, late-reaction, cleanup, and delete-sheet sequencing reruns so delete now has exact deterministic proof across the row-owned races. |
| SC-005 | SC-005 | P0 | Security, Ordering, Recovery, and Cross-Feature Convergence | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-SC-005-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun chat, reaction, and deletion listener lifecycle evidence. |
| SC-010 | SC-010 | P0 | Security, Ordering, Recovery, and Cross-Feature Convergence | needs_code_and_tests | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-SC-010-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Reconciled queued reaction, edit, and delete recovery with direct failure-path and send-then-lock reruns so reconnect now has exact proof of either explicit retryable failure or same-id convergence after resume. |
| OG-002 | OG-002 | P1 | Overlay Lifecycle, Gating, and Host Consistency | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-OG-002-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with paired conversation/feed screen reruns proving overlay open, action visibility, dismissal, copy, delete, and deleted-row inert behavior stay aligned across both hosts. |
| OG-006 | OG-006 | P1 | Overlay Lifecycle, Gating, and Host Consistency | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-OG-006-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Landed the missing busy-composer edit gate in `conversation_screen.dart` and added exact screen regressions proving attachment, upload, send, processing, and recording states hide only Edit while leaving Reply, Copy, and Delete available. |
| OG-009 | OG-009 | P1 | Overlay Lifecycle, Gating, and Host Consistency | needs_code_and_tests | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-OG-009-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Landed shared one-shot action handling in `message_context_overlay.dart` plus modal-route host guards in the conversation and feed hosts, then added exact overlay and screen regressions proving rapid long-press and rapid action taps no longer double-apply effects. |
| RX-004 | RX-004 | P1 | Reactions | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-004-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Added exact non-preset emoji picker proof across selection, persistence, inline render, and quick-bar reopen state so the custom-emoji path now has row-owned coverage without relying on preset-only reaction tests. |
| RX-005 | RX-005 | P1 | Reactions | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-005-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun grouped-chip count and own-highlight evidence from `reaction_display_test.dart` and `emoji_reaction_exchange_test.dart`. |
| RX-006 | RX-006 | P1 | Reactions | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-006-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun callback-parity proof from the overlay bar and inline chips plus existing two-user toggle/replace exchange evidence showing both entry paths feed the same downstream reaction state machine. |
| RX-010 | RX-010 | P1 | Reactions | needs_code_and_tests | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-010-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Confirmed the landed timestamp-order guard in `handle_incoming_reaction_use_case.dart` with direct stale-remove and stale-add regressions so older deliveries no longer erase or resurrect a newer stored reaction state. |
| RX-013 | RX-013 | P1 | Reactions | covered_in_repo | stale/already-covered | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-013-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with exact listener lifecycle evidence. |
| CP-002 | CP-002 | P1 | Copy | covered_in_repo | stale/already-covered | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-CP-002-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun feed host copy happy-path proof. |
| CP-004 | CP-004 | P1 | Copy | covered_in_repo | stale/already-covered | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-CP-004-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with exact multiline, emoji, and RTL copy proof. |
| RP-002 | RP-002 | P1 | Reply / Quote Reply | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RP-002-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun incoming/outgoing/deleted swipe gating evidence from `conversation_screen_test.dart` plus quote-flow proof from `conversation_wired_test.dart`. |
| RP-008 | RP-008 | P1 | Reply / Quote Reply | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RP-008-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun deleted-parent quote degradation evidence from `conversation_screen_test.dart`. |
| RP-010 | RP-010 | P1 | Reply / Quote Reply | needs_code_and_tests | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RP-010-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Added a restart-capable integration harness path that reuses Bob's local stores across recreate, then proved an inbox-delivered quoted reply drains after restart with the same `quotedMessageId`. |
| RP-011 | RP-011 | P1 | Reply / Quote Reply | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RP-011-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun conversation and feed host reply-behavior parity evidence from `conversation_wired_test.dart` and `feed_wired_test.dart`. |
| RP-012 | RP-012 | P1 | Reply / Quote Reply | needs_code_and_tests | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RP-012-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun reply-vs-edit mutual-exclusion evidence from `conversation_wired_test.dart`. |
| ED-012 | ED-012 | P1 | Edit | needs_code_and_tests | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-012-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Added receiver-restart inbox proof showing a queued same-id edit applies after recreate with preserved local stores, updates text and `editedAt`, and does not duplicate the row. |
| ED-014 | ED-014 | P1 | Edit | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-014-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun conversation/feed edit-host parity evidence from `conversation_wired_test.dart` and `feed_wired_test.dart`. |
| ED-015 | ED-015 | P1 | Edit | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-015-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with exact reruns proving the edit send path preserves `action='edit'` and `editedAt` in the v1 wire payload while `message_payload_test.dart` preserves the same metadata in the v2 inner JSON form. |
| DL-003 | DL-003 | P1 | Delete | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-003-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun delete-sheet cancel no-op evidence from `conversation_wired_test.dart`. |
| DL-017 | DL-017 | P1 | Delete | needs_code_and_tests | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-017-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Added a sender-side restart regression that recreates Alice from the persisted failed tombstone state and proves the original plaintext stays hidden until later transport reconciliation, complementing the existing pause/resume delivery proof. |
| DL-018 | DL-018 | P1 | Delete | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-018-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun conversation/feed delete-host parity evidence from `conversation_wired_test.dart` and `feed_wired_test.dart`. |
| DL-019 | DL-019 | P1 | Delete | needs_code_and_tests | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-019-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Moved blocked-sender handling into the delete use case so already-stored authored messages still tombstone after a later block, while missing blocked-target deletes stay ignored and do not stage new placeholders. |
| SC-006 | SC-006 | P1 | Security, Ordering, Recovery, and Cross-Feature Convergence | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-SC-006-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun migration-chain, DB-helper, and repository evidence proving overlay-state columns upgrade safely and load without hidden-row regressions. |
| SC-008 | SC-008 | P1 | Security, Ordering, Recovery, and Cross-Feature Convergence | needs_code_and_tests | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-SC-008-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Added exact conversation-host and feed-host restart regressions that dispose and rebuild from the same stored post-mutation truth, proving reply, edit, delete, and reaction state reload without stale pre-restart UI surviving on either surface. |
| SC-009 | SC-009 | P1 | Security, Ordering, Recovery, and Cross-Feature Convergence | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-SC-009-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_blocked_startup_deeplink_unblock_plan.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Extended the harness with a background-open regression proving warm remote route entry shows only the latest stored edit/delete state on first render rather than stale pre-sync UI. |
| OG-010 | OG-010 | P2 | Overlay Lifecycle, Gating, and Host Consistency | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-OG-010-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with rerun RTL localization and viewport-clamp evidence from `message_context_overlay_test.dart`. |
| CP-005 | CP-005 | P2 | Copy | covered_in_repo | stale/already-covered | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-CP-005-plan.md | stale/already-covered | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Matrix updated with exact repeated-copy snackbar replacement proof. |
| RP-009 | RP-009 | P2 | Reply / Quote Reply | needs_code_and_tests | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RP-009-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Added a direct conversation-screen regression that re-pumps an edited quoted parent and proves reply rendering stays stable while live-resolving the updated parent text. |
| SC-007 | SC-007 | P2 | Security, Ordering, Recovery, and Cross-Feature Convergence | needs_tests_only | implementation-ready | none | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-SC-007-plan.md | accepted | accepted | Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/test-inventory.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md | Closed with explicit Arabic snackbar proof plus reruns covering RTL quote bars, deleted placeholders, edited indicators, and inline reaction chips across the conversation/feed bubble widgets and overlay. |

## Downstream Execution Path

- For each row-owned session, reuse or tighten the doc-scoped plan file with implementation-plan-orchestrator before execution.
- Execute the session with implementation-execution-qa-orchestrator and keep code/test work scoped to the owning row unless current repo evidence proves the row is already covered.
- Close the session with implementation-closure-audit-orchestrator, then update this ledger and the source matrix only when the row is truthfully Covered or Closed with exact file-and-test evidence.
- After the last runnable session, persist one final program acceptance review in this breakdown with an allowed final program verdict.
- Every spawned downstream agent in this rollout must explicitly request model gpt-5.4 with reasoning effort xhigh.
## Ordered Session Breakdown

### Session OG-001
- Source row id: OG-001
- Scenario title: Long-press on a supported non-deleted message opens the overlay and backdrop dismiss is side-effect free
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-OG-001-plan.md
- Exact scope: Close source row OG-001 for "Long-press on a supported non-deleted message opens the overlay and backdrop dismiss is side-effect free" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/widgets/message_context_overlay.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/presentation/widgets/letter_card.dart; lib/features/feed/presentation/widgets/message_bubble.dart
- Likely direct tests or regressions: test/features/conversation/presentation/widgets/message_context_overlay_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart
- Likely named gates: overlay_open_gate; overlay_action_order; host_parity_overlay; deleted_row_overlay_guard
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/widgets/message_context_overlay.dart and lib/features/conversation/presentation/screens/conversation_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/presentation/widgets/message_context_overlay_test.dart and test/features/conversation/presentation/screens/conversation_screen_test.dart.

### Session OG-003
- Source row id: OG-003
- Scenario title: Action order and stable keys remain correct when all optional actions are available
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-OG-003-plan.md
- Exact scope: Close source row OG-003 for "Action order and stable keys remain correct when all optional actions are available" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/widgets/message_context_overlay.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/presentation/widgets/letter_card.dart; lib/features/feed/presentation/widgets/message_bubble.dart; lib/features/conversation/presentation/widgets/message_context_overlay.dart
- Likely direct tests or regressions: test/features/conversation/presentation/widgets/message_context_overlay_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart
- Likely named gates: overlay_open_gate; overlay_action_order; host_parity_overlay; deleted_row_overlay_guard
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/widgets/message_context_overlay.dart and lib/features/conversation/presentation/screens/conversation_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/presentation/widgets/message_context_overlay_test.dart and test/features/conversation/presentation/screens/conversation_screen_test.dart.

### Session OG-004
- Source row id: OG-004
- Scenario title: Deleted or tombstoned rows cannot reopen a mutating overlay
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-OG-004-plan.md
- Exact scope: Close source row OG-004 for "Deleted or tombstoned rows cannot reopen a mutating overlay" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/widgets/message_context_overlay.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/presentation/widgets/letter_card.dart; lib/features/feed/presentation/widgets/message_bubble.dart
- Likely direct tests or regressions: test/features/conversation/presentation/widgets/message_context_overlay_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart
- Likely named gates: overlay_open_gate; overlay_action_order; host_parity_overlay; deleted_row_overlay_guard
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/widgets/message_context_overlay.dart and lib/features/conversation/presentation/screens/conversation_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/presentation/widgets/message_context_overlay_test.dart and test/features/conversation/presentation/screens/conversation_screen_test.dart.

### Session OG-005
- Source row id: OG-005
- Scenario title: Media-only, whitespace-only, and system-message variants gate actions correctly
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-OG-005-plan.md
- Exact scope: Close source row OG-005 for "Media-only, whitespace-only, and system-message variants gate actions correctly" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/widgets/message_context_overlay.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/presentation/widgets/letter_card.dart; lib/features/feed/presentation/widgets/message_bubble.dart
- Likely direct tests or regressions: test/features/conversation/presentation/widgets/message_context_overlay_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart
- Likely named gates: overlay_open_gate; overlay_action_order; host_parity_overlay; deleted_row_overlay_guard
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/widgets/message_context_overlay.dart and lib/features/conversation/presentation/screens/conversation_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/presentation/widgets/message_context_overlay_test.dart and test/features/conversation/presentation/screens/conversation_screen_test.dart.

### Session OG-007
- Source row id: OG-007
- Scenario title: Delete uses overlay-pop then next-frame sheet sequencing
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-OG-007-plan.md
- Exact scope: Close source row OG-007 for "Delete uses overlay-pop then next-frame sheet sequencing" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/widgets/message_context_overlay.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/presentation/widgets/letter_card.dart; lib/features/feed/presentation/widgets/message_bubble.dart
- Likely direct tests or regressions: test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart
- Likely named gates: overlay_pop_then_delete_sheet; single_sheet_presentation
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/widgets/message_context_overlay.dart and lib/features/conversation/presentation/screens/conversation_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/presentation/screens/conversation_screen_test.dart and test/features/feed/presentation/screens/feed_screen_test.dart.

### Session OG-008
- Source row id: OG-008
- Scenario title: Copy remains safe if the screen is disposed during the async clipboard call
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-OG-008-plan.md
- Exact scope: Close source row OG-008 for "Copy remains safe if the screen is disposed during the async clipboard call" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/widgets/message_context_overlay.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/presentation/widgets/letter_card.dart; lib/features/feed/presentation/widgets/message_bubble.dart
- Likely direct tests or regressions: test/features/conversation/presentation/screens/conversation_screen_test.dart
- Likely named gates: copy_async_mounted_guard
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/widgets/message_context_overlay.dart and lib/features/conversation/presentation/screens/conversation_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/presentation/screens/conversation_screen_test.dart.

### Session RX-001
- Source row id: RX-001
- Scenario title: Add a preset reaction from the overlay happy path
- Row disposition: covered_in_repo
- Session classification: stale/already-covered
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-001-plan.md
- Exact scope: Close source row RX-001 for "Add a preset reaction from the overlay happy path" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: no execution because already covered
- Likely code-entry files: lib/features/conversation/presentation/widgets/reaction_bar.dart; lib/features/conversation/presentation/widgets/reaction_display.dart; lib/features/conversation/application/send_reaction_use_case.dart; lib/features/conversation/application/remove_reaction_use_case.dart; lib/features/conversation/application/handle_incoming_reaction_use_case.dart; lib/features/conversation/application/reaction_listener.dart; lib/features/conversation/domain/repositories/reaction_repository_impl.dart; lib/core/database/helpers/reactions_db_helpers.dart
- Likely direct tests or regressions: test/features/conversation/application/send_reaction_use_case_test.dart:86; test/features/conversation/integration/emoji_reaction_exchange_test.dart:58
- Likely named gates: reaction_non_deleted_gate; reaction_toggle_replace; reaction_sender_auth; reaction_decrypt_gate; reaction_listener_lifecycle
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Exact repo proof exists for optimistic send plus receiver-side reaction persistence on the happy path.

### Session RX-002
- Source row id: RX-002
- Scenario title: Tapping the same emoji toggles the reaction off
- Row disposition: covered_in_repo
- Session classification: stale/already-covered
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-002-plan.md
- Exact scope: Close source row RX-002 for "Tapping the same emoji toggles the reaction off" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: no execution because already covered
- Likely code-entry files: lib/features/conversation/presentation/widgets/reaction_bar.dart; lib/features/conversation/presentation/widgets/reaction_display.dart; lib/features/conversation/application/send_reaction_use_case.dart; lib/features/conversation/application/remove_reaction_use_case.dart; lib/features/conversation/application/handle_incoming_reaction_use_case.dart; lib/features/conversation/application/reaction_listener.dart; lib/features/conversation/domain/repositories/reaction_repository_impl.dart; lib/core/database/helpers/reactions_db_helpers.dart
- Likely direct tests or regressions: test/features/conversation/application/remove_reaction_use_case_test.dart:67; test/features/conversation/integration/emoji_reaction_exchange_test.dart:114
- Likely named gates: reaction_non_deleted_gate; reaction_toggle_replace; reaction_sender_auth; reaction_decrypt_gate; reaction_listener_lifecycle
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Exact repo proof exists for add-then-remove toggle semantics locally and across the receiver path.

### Session RX-003
- Source row id: RX-003
- Scenario title: Tapping a different emoji replaces the previous own reaction instead of creating duplicates
- Row disposition: covered_in_repo
- Session classification: stale/already-covered
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-003-plan.md
- Exact scope: Close source row RX-003 for "Tapping a different emoji replaces the previous own reaction instead of creating duplicates" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: no execution because already covered
- Likely code-entry files: lib/features/conversation/presentation/widgets/reaction_bar.dart; lib/features/conversation/presentation/widgets/reaction_display.dart; lib/features/conversation/application/send_reaction_use_case.dart; lib/features/conversation/application/remove_reaction_use_case.dart; lib/features/conversation/application/handle_incoming_reaction_use_case.dart; lib/features/conversation/application/reaction_listener.dart; lib/features/conversation/domain/repositories/reaction_repository_impl.dart; lib/core/database/helpers/reactions_db_helpers.dart
- Likely direct tests or regressions: test/features/conversation/integration/emoji_reaction_exchange_test.dart:164; test/core/database/migrations/016_message_reactions_test.dart:52
- Likely named gates: reaction_non_deleted_gate; reaction_toggle_replace; reaction_sender_auth; reaction_decrypt_gate; reaction_listener_lifecycle
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Exact repo proof exists for replace/upsert semantics and the UNIQUE(message_id, sender_peer_id) constraint.

### Session RX-007
- Source row id: RX-007
- Scenario title: Reaction from a blocked sender is ignored
- Row disposition: covered_in_repo
- Session classification: stale/already-covered
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-007-plan.md
- Exact scope: Close source row RX-007 for "Reaction from a blocked sender is ignored" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: no execution because already covered
- Likely code-entry files: lib/features/conversation/presentation/widgets/reaction_bar.dart; lib/features/conversation/presentation/widgets/reaction_display.dart; lib/features/conversation/application/send_reaction_use_case.dart; lib/features/conversation/application/remove_reaction_use_case.dart; lib/features/conversation/application/handle_incoming_reaction_use_case.dart; lib/features/conversation/application/reaction_listener.dart; lib/features/conversation/domain/repositories/reaction_repository_impl.dart; lib/core/database/helpers/reactions_db_helpers.dart
- Likely direct tests or regressions: test/features/conversation/application/reaction_listener_test.dart:180
- Likely named gates: reaction_non_deleted_gate; reaction_toggle_replace; reaction_sender_auth; reaction_decrypt_gate; reaction_listener_lifecycle
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Exact repo proof exists for blocked-sender rejection in the inbound reaction listener.

### Session RX-008
- Source row id: RX-008
- Scenario title: Plaintext, tampered, or undecryptable reactions are rejected without local mutation
- Row disposition: covered_in_repo
- Session classification: stale/already-covered
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-008-plan.md
- Exact scope: Close source row RX-008 for "Plaintext, tampered, or undecryptable reactions are rejected without local mutation" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: no execution because already covered
- Likely code-entry files: lib/features/conversation/presentation/widgets/reaction_bar.dart; lib/features/conversation/presentation/widgets/reaction_display.dart; lib/features/conversation/application/send_reaction_use_case.dart; lib/features/conversation/application/remove_reaction_use_case.dart; lib/features/conversation/application/handle_incoming_reaction_use_case.dart; lib/features/conversation/application/reaction_listener.dart; lib/features/conversation/domain/repositories/reaction_repository_impl.dart; lib/core/database/helpers/reactions_db_helpers.dart
- Likely direct tests or regressions: test/features/conversation/application/handle_incoming_reaction_use_case_test.dart:77; test/features/conversation/application/handle_incoming_reaction_use_case_test.dart:98; test/features/conversation/application/handle_incoming_reaction_use_case_test.dart:117
- Likely named gates: reaction_non_deleted_gate; reaction_toggle_replace; reaction_sender_auth; reaction_decrypt_gate; reaction_listener_lifecycle
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Exact repo proof exists for rejecting plaintext and undecryptable reaction envelopes without applying local mutation.

### Session RX-009
- Source row id: RX-009
- Scenario title: Duplicate add and duplicate remove deliveries are idempotent
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-009-plan.md
- Exact scope: Close source row RX-009 for "Duplicate add and duplicate remove deliveries are idempotent" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/widgets/reaction_bar.dart; lib/features/conversation/presentation/widgets/reaction_display.dart; lib/features/conversation/application/send_reaction_use_case.dart; lib/features/conversation/application/remove_reaction_use_case.dart; lib/features/conversation/application/handle_incoming_reaction_use_case.dart; lib/features/conversation/application/reaction_listener.dart; lib/features/conversation/domain/repositories/reaction_repository_impl.dart; lib/core/database/helpers/reactions_db_helpers.dart
- Likely direct tests or regressions: test/features/conversation/application/send_reaction_use_case_test.dart; test/features/conversation/application/remove_reaction_use_case_test.dart; test/features/conversation/application/handle_incoming_reaction_use_case_test.dart; test/features/conversation/application/reaction_listener_test.dart; test/features/conversation/integration/emoji_reaction_exchange_test.dart; test/core/database/migrations/016_message_reactions_test.dart
- Likely named gates: reaction_non_deleted_gate; reaction_toggle_replace; reaction_sender_auth; reaction_decrypt_gate; reaction_listener_lifecycle
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/widgets/reaction_bar.dart and lib/features/conversation/presentation/widgets/reaction_display.dart, but exact row-level proof is not yet explicit in test/features/conversation/application/send_reaction_use_case_test.dart and test/features/conversation/application/remove_reaction_use_case_test.dart.

### Session RX-011
- Source row id: RX-011
- Scenario title: `sendMessage=false` and `storeInInbox=false` must not look like success
- Row disposition: needs_code_and_tests
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-011-plan.md
- Exact scope: Close source row RX-011 for "`sendMessage=false` and `storeInInbox=false` must not look like success" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: code changes
- Likely code-entry files: lib/features/conversation/presentation/widgets/reaction_bar.dart; lib/features/conversation/presentation/widgets/reaction_display.dart; lib/features/conversation/application/send_reaction_use_case.dart; lib/features/conversation/application/remove_reaction_use_case.dart; lib/features/conversation/application/handle_incoming_reaction_use_case.dart; lib/features/conversation/application/reaction_listener.dart; lib/features/conversation/domain/repositories/reaction_repository_impl.dart; lib/core/database/helpers/reactions_db_helpers.dart
- Likely direct tests or regressions: test/features/conversation/application/send_reaction_use_case_test.dart; test/features/conversation/application/remove_reaction_use_case_test.dart; test/features/conversation/application/handle_incoming_reaction_use_case_test.dart; test/features/conversation/application/reaction_listener_test.dart; test/features/conversation/integration/emoji_reaction_exchange_test.dart; test/core/database/migrations/016_message_reactions_test.dart
- Likely named gates: reaction_non_deleted_gate; reaction_toggle_replace; reaction_sender_auth; reaction_decrypt_gate; reaction_listener_lifecycle
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Current repo evidence does not prove the full row contract; the risk profile and missing exact tests suggest a likely behavior gap across lib/features/conversation/presentation/widgets/reaction_bar.dart and lib/features/conversation/presentation/widgets/reaction_display.dart.

### Session RX-012
- Source row id: RX-012
- Scenario title: Reactions targeting an unknown or missing message do not create orphan rows
- Row disposition: needs_code_and_tests
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-012-plan.md
- Exact scope: Close source row RX-012 for "Reactions targeting an unknown or missing message do not create orphan rows" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: code changes
- Likely code-entry files: lib/features/conversation/presentation/widgets/reaction_bar.dart; lib/features/conversation/presentation/widgets/reaction_display.dart; lib/features/conversation/application/send_reaction_use_case.dart; lib/features/conversation/application/remove_reaction_use_case.dart; lib/features/conversation/application/handle_incoming_reaction_use_case.dart; lib/features/conversation/application/reaction_listener.dart; lib/features/conversation/domain/repositories/reaction_repository_impl.dart; lib/core/database/helpers/reactions_db_helpers.dart
- Likely direct tests or regressions: test/features/conversation/application/send_reaction_use_case_test.dart; test/features/conversation/application/remove_reaction_use_case_test.dart; test/features/conversation/application/handle_incoming_reaction_use_case_test.dart; test/features/conversation/application/reaction_listener_test.dart; test/features/conversation/integration/emoji_reaction_exchange_test.dart; test/core/database/migrations/016_message_reactions_test.dart
- Likely named gates: reaction_non_deleted_gate; reaction_toggle_replace; reaction_sender_auth; reaction_decrypt_gate; reaction_listener_lifecycle
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Current repo evidence does not prove the full row contract; the risk profile and missing exact tests suggest a likely behavior gap across lib/features/conversation/presentation/widgets/reaction_bar.dart and lib/features/conversation/presentation/widgets/reaction_display.dart.

### Session CP-001
- Source row id: CP-001
- Scenario title: Copy happy path in the conversation host
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-CP-001-plan.md
- Exact scope: Close source row CP-001 for "Copy happy path in the conversation host" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/widgets/message_context_overlay.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart
- Likely direct tests or regressions: test/features/conversation/presentation/widgets/message_context_overlay_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart
- Likely named gates: copy_text_present_gate; copy_local_only_invariant; copy_host_parity
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/widgets/message_context_overlay.dart and lib/features/conversation/presentation/screens/conversation_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/presentation/widgets/message_context_overlay_test.dart and test/features/conversation/presentation/screens/conversation_screen_test.dart.

### Session CP-003
- Source row id: CP-003
- Scenario title: Copy is hidden for deleted, media-only, and whitespace-only rows
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-CP-003-plan.md
- Exact scope: Close source row CP-003 for "Copy is hidden for deleted, media-only, and whitespace-only rows" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/widgets/message_context_overlay.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart
- Likely direct tests or regressions: test/features/conversation/presentation/widgets/message_context_overlay_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart
- Likely named gates: copy_text_present_gate; copy_local_only_invariant; copy_host_parity
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/widgets/message_context_overlay.dart and lib/features/conversation/presentation/screens/conversation_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/presentation/widgets/message_context_overlay_test.dart and test/features/conversation/presentation/screens/conversation_screen_test.dart.

### Session CP-006
- Source row id: CP-006
- Scenario title: ConversationScreen copy remains safe if the widget is disposed after the clipboard await starts
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-CP-006-plan.md
- Exact scope: Close source row CP-006 for "ConversationScreen copy remains safe if the widget is disposed after the clipboard await starts" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/widgets/message_context_overlay.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart
- Likely direct tests or regressions: test/features/conversation/presentation/screens/conversation_screen_test.dart
- Likely named gates: copy_async_mounted_guard
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/widgets/message_context_overlay.dart and lib/features/conversation/presentation/screens/conversation_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/presentation/screens/conversation_screen_test.dart.

### Session CP-007
- Source row id: CP-007
- Scenario title: FeedScreen copy remains safe after context changes because messenger and l10n are captured before await
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-CP-007-plan.md
- Exact scope: Close source row CP-007 for "FeedScreen copy remains safe after context changes because messenger and l10n are captured before await" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/widgets/message_context_overlay.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart
- Likely direct tests or regressions: test/features/feed/presentation/screens/feed_screen_test.dart
- Likely named gates: feed_pre_await_context_capture
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/widgets/message_context_overlay.dart and lib/features/conversation/presentation/screens/conversation_screen.dart, but exact row-level proof is not yet explicit in test/features/feed/presentation/screens/feed_screen_test.dart.

### Session CP-008
- Source row id: CP-008
- Scenario title: Copy never touches repo, bridge, or P2P collaborators
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-CP-008-plan.md
- Exact scope: Close source row CP-008 for "Copy never touches repo, bridge, or P2P collaborators" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/widgets/message_context_overlay.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart
- Likely direct tests or regressions: test/features/conversation/presentation/widgets/message_context_overlay_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart
- Likely named gates: copy_text_present_gate; copy_local_only_invariant; copy_host_parity
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/widgets/message_context_overlay.dart and lib/features/conversation/presentation/screens/conversation_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/presentation/widgets/message_context_overlay_test.dart and test/features/conversation/presentation/screens/conversation_screen_test.dart.

### Session RP-001
- Source row id: RP-001
- Scenario title: Reply from the overlay enters quote mode and focuses the composer
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RP-001-plan.md
- Exact scope: Close source row RP-001 for "Reply from the overlay enters quote mode and focuses the composer" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/application/load_conversation_use_case.dart; lib/features/feed/presentation/widgets/message_bubble.dart; lib/features/feed/presentation/widgets/quote_preview_bar.dart
- Likely direct tests or regressions: test/features/conversation/integration/quote_reply_thread_test.dart; test/features/conversation/application/send_chat_message_use_case_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/core/database/migrations/009_quoted_message_id_test.dart
- Likely named gates: reply_entry_gate; quote_resolution_gate; quotedMessageId_preservation; reply_vs_edit_mutual_exclusion
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/integration/quote_reply_thread_test.dart and test/features/conversation/application/send_chat_message_use_case_test.dart.

### Session RP-003
- Source row id: RP-003
- Scenario title: Quote preview resolves text, media preview text, or unavailable state
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RP-003-plan.md
- Exact scope: Close source row RP-003 for "Quote preview resolves text, media preview text, or unavailable state" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/application/load_conversation_use_case.dart; lib/features/feed/presentation/widgets/message_bubble.dart; lib/features/feed/presentation/widgets/quote_preview_bar.dart; lib/features/feed/presentation/screens/feed_screen.dart
- Likely direct tests or regressions: test/features/conversation/integration/quote_reply_thread_test.dart; test/features/conversation/application/send_chat_message_use_case_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/core/database/migrations/009_quoted_message_id_test.dart
- Likely named gates: reply_entry_gate; quote_resolution_gate; quotedMessageId_preservation; reply_vs_edit_mutual_exclusion
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/integration/quote_reply_thread_test.dart and test/features/conversation/application/send_chat_message_use_case_test.dart.

### Session RP-004
- Source row id: RP-004
- Scenario title: Clearing a quote removes the preview and the next send has no `quotedMessageId`
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RP-004-plan.md
- Exact scope: Close source row RP-004 for "Clearing a quote removes the preview and the next send has no `quotedMessageId`" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/application/load_conversation_use_case.dart; lib/features/feed/presentation/widgets/message_bubble.dart; lib/features/feed/presentation/widgets/quote_preview_bar.dart
- Likely direct tests or regressions: test/features/conversation/integration/quote_reply_thread_test.dart; test/features/conversation/application/send_chat_message_use_case_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/core/database/migrations/009_quoted_message_id_test.dart
- Likely named gates: reply_entry_gate; quote_resolution_gate; quotedMessageId_preservation; reply_vs_edit_mutual_exclusion
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/integration/quote_reply_thread_test.dart and test/features/conversation/application/send_chat_message_use_case_test.dart.

### Session RP-005
- Source row id: RP-005
- Scenario title: Sending a reply preserves `quotedMessageId` locally and remotely
- Row disposition: covered_in_repo
- Session classification: stale/already-covered
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RP-005-plan.md
- Exact scope: Close source row RP-005 for "Sending a reply preserves `quotedMessageId` locally and remotely" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: no execution because already covered
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/application/load_conversation_use_case.dart; lib/features/feed/presentation/widgets/message_bubble.dart; lib/features/feed/presentation/widgets/quote_preview_bar.dart
- Likely direct tests or regressions: test/features/conversation/integration/quote_reply_thread_test.dart:48; test/features/conversation/integration/quote_reply_thread_test.dart:96
- Likely named gates: reply_entry_gate; quote_resolution_gate; quotedMessageId_preservation; reply_vs_edit_mutual_exclusion
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Exact repo proof exists for preserving quotedMessageId through payload serialization and end-to-end reply delivery.

### Session RP-006
- Source row id: RP-006
- Scenario title: Failed reply send restores the full composer snapshot
- Row disposition: needs_code_and_tests
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RP-006-plan.md
- Exact scope: Close source row RP-006 for "Failed reply send restores the full composer snapshot" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: code changes
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/application/load_conversation_use_case.dart; lib/features/feed/presentation/widgets/message_bubble.dart; lib/features/feed/presentation/widgets/quote_preview_bar.dart
- Likely direct tests or regressions: test/features/conversation/integration/quote_reply_thread_test.dart; test/features/conversation/application/send_chat_message_use_case_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/core/database/migrations/009_quoted_message_id_test.dart
- Likely named gates: reply_entry_gate; quote_resolution_gate; quotedMessageId_preservation; reply_vs_edit_mutual_exclusion
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Current repo evidence does not prove the full row contract; the risk profile and missing exact tests suggest a likely behavior gap across lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart.

### Session RP-007
- Source row id: RP-007
- Scenario title: Incoming reply remains readable even when the quoted source does not exist locally
- Row disposition: covered_in_repo
- Session classification: stale/already-covered
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RP-007-plan.md
- Exact scope: Close source row RP-007 for "Incoming reply remains readable even when the quoted source does not exist locally" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: no execution because already covered
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/application/load_conversation_use_case.dart; lib/features/feed/presentation/widgets/message_bubble.dart; lib/features/feed/presentation/widgets/quote_preview_bar.dart
- Likely direct tests or regressions: test/features/conversation/integration/quote_reply_thread_test.dart:203
- Likely named gates: reply_entry_gate; quote_resolution_gate; quotedMessageId_preservation; reply_vs_edit_mutual_exclusion
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Exact repo proof exists that replies persist and remain readable when the quoted source ID is absent locally.

### Session ED-001
- Source row id: ED-001
- Scenario title: Edit overlay visibility follows the full eight-condition gate
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-001-plan.md
- Exact scope: Close source row ED-001 for "Edit overlay visibility follows the full eight-condition gate" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/send_chat_message_use_case_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/features/conversation/application/load_conversation_use_case_test.dart
- Likely named gates: edit_eight_condition_gate; latest_sent_edit_gate; edit_same_id_contract; edit_sender_auth; delete_dominates_stale_edit
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/application/send_chat_message_use_case_test.dart and test/features/conversation/presentation/screens/conversation_screen_test.dart.

### Session ED-002
- Source row id: ED-002
- Scenario title: Latest-sent scanning skips deleted outgoing rows and ignores newer incoming rows
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-002-plan.md
- Exact scope: Close source row ED-002 for "Latest-sent scanning skips deleted outgoing rows and ignores newer incoming rows" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/send_chat_message_use_case_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/features/conversation/application/load_conversation_use_case_test.dart
- Likely named gates: edit_eight_condition_gate; latest_sent_edit_gate; edit_same_id_contract; edit_sender_auth; delete_dominates_stale_edit
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/application/send_chat_message_use_case_test.dart and test/features/conversation/presentation/screens/conversation_screen_test.dart.

### Session ED-003
- Source row id: ED-003
- Scenario title: Tapping Edit enters edit mode, pre-fills text, clears quote mode, and shows the banner
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-003-plan.md
- Exact scope: Close source row ED-003 for "Tapping Edit enters edit mode, pre-fills text, clears quote mode, and shows the banner" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/send_chat_message_use_case_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/features/conversation/application/load_conversation_use_case_test.dart
- Likely named gates: edit_eight_condition_gate; latest_sent_edit_gate; edit_same_id_contract; edit_sender_auth; delete_dominates_stale_edit
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/application/send_chat_message_use_case_test.dart and test/features/conversation/presentation/screens/conversation_screen_test.dart.

### Session ED-004
- Source row id: ED-004
- Scenario title: Canceling edit clears the banner and edit state
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-004-plan.md
- Exact scope: Close source row ED-004 for "Canceling edit clears the banner and edit state" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/send_chat_message_use_case_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/features/conversation/application/load_conversation_use_case_test.dart
- Likely named gates: edit_eight_condition_gate; latest_sent_edit_gate; edit_same_id_contract; edit_sender_auth; delete_dominates_stale_edit
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/application/send_chat_message_use_case_test.dart and test/features/conversation/presentation/screens/conversation_screen_test.dart.

### Session ED-005
- Source row id: ED-005
- Scenario title: Submitting unchanged text is a silent cancel
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-005-plan.md
- Exact scope: Close source row ED-005 for "Submitting unchanged text is a silent cancel" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/send_chat_message_use_case_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/features/conversation/application/load_conversation_use_case_test.dart
- Likely named gates: edit_eight_condition_gate; latest_sent_edit_gate; edit_same_id_contract; edit_sender_auth; delete_dominates_stale_edit
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/application/send_chat_message_use_case_test.dart and test/features/conversation/presentation/screens/conversation_screen_test.dart.

### Session ED-006
- Source row id: ED-006
- Scenario title: Successful edit reuses the original ID, preserves timestamp / createdAt, sets `editedAt`, and renders `(edited)` on both sides
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-006-plan.md
- Exact scope: Close source row ED-006 for "Successful edit reuses the original ID, preserves timestamp / createdAt, sets `editedAt`, and renders `(edited)` on both sides" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/send_chat_message_use_case_test.dart:651; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart
- Likely named gates: edit_eight_condition_gate; latest_sent_edit_gate; edit_same_id_contract; edit_sender_auth; delete_dominates_stale_edit
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/application/send_chat_message_use_case_test.dart:651 and test/features/conversation/presentation/screens/conversation_screen_test.dart.

### Session ED-007
- Source row id: ED-007
- Scenario title: Deleted messages suppress the edited indicator even if `editedAt` exists
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-007-plan.md
- Exact scope: Close source row ED-007 for "Deleted messages suppress the edited indicator even if `editedAt` exists" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/send_chat_message_use_case_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/features/conversation/application/load_conversation_use_case_test.dart
- Likely named gates: edit_eight_condition_gate; latest_sent_edit_gate; edit_same_id_contract; edit_sender_auth; delete_dominates_stale_edit
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/application/send_chat_message_use_case_test.dart and test/features/conversation/presentation/screens/conversation_screen_test.dart.

### Session ED-008
- Source row id: ED-008
- Scenario title: Deleting the message currently being edited exits edit mode immediately
- Row disposition: needs_code_and_tests
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-008-plan.md
- Exact scope: Close source row ED-008 for "Deleting the message currently being edited exits edit mode immediately" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: code changes
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/send_chat_message_use_case_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/features/conversation/application/load_conversation_use_case_test.dart
- Likely named gates: edit_eight_condition_gate; latest_sent_edit_gate; edit_same_id_contract; edit_sender_auth; delete_dominates_stale_edit
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Current repo evidence does not prove the full row contract; the risk profile and missing exact tests suggest a likely behavior gap across lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart.

### Session ED-009
- Source row id: ED-009
- Scenario title: Incoming edit that arrives before the original does not create a phantom row and later converges correctly
- Row disposition: needs_code_and_tests
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-009-plan.md
- Exact scope: Close source row ED-009 for "Incoming edit that arrives before the original does not create a phantom row and later converges correctly" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: code changes
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/send_chat_message_use_case_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/features/conversation/application/load_conversation_use_case_test.dart
- Likely named gates: edit_eight_condition_gate; latest_sent_edit_gate; edit_same_id_contract; edit_sender_auth; delete_dominates_stale_edit
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Current repo evidence does not prove the full row contract; the risk profile and missing exact tests suggest a likely behavior gap across lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart.

### Session ED-010
- Source row id: ED-010
- Scenario title: Duplicate and stale edit deliveries are idempotent and newest edit wins
- Row disposition: needs_code_and_tests
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-010-plan.md
- Exact scope: Close source row ED-010 for "Duplicate and stale edit deliveries are idempotent and newest edit wins" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: code changes
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/send_chat_message_use_case_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/features/conversation/application/load_conversation_use_case_test.dart
- Likely named gates: edit_eight_condition_gate; latest_sent_edit_gate; edit_same_id_contract; edit_sender_auth; delete_dominates_stale_edit
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Current repo evidence does not prove the full row contract; the risk profile and missing exact tests suggest a likely behavior gap across lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart.

### Session ED-011
- Source row id: ED-011
- Scenario title: Unauthorized edit for someone else’s message is rejected
- Row disposition: needs_code_and_tests
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-011-plan.md
- Exact scope: Close source row ED-011 for "Unauthorized edit for someone else’s message is rejected" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: code changes
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/send_chat_message_use_case_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/features/conversation/application/load_conversation_use_case_test.dart
- Likely named gates: edit_eight_condition_gate; latest_sent_edit_gate; edit_same_id_contract; edit_sender_auth; delete_dominates_stale_edit
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Current repo evidence does not prove the full row contract; the risk profile and missing exact tests suggest a likely behavior gap across lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart.

### Session ED-013
- Source row id: ED-013
- Scenario title: Late edit cannot resurrect text after delete
- Row disposition: needs_code_and_tests
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-013-plan.md
- Exact scope: Close source row ED-013 for "Late edit cannot resurrect text after delete" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: code changes
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/send_chat_message_use_case_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/features/conversation/application/load_conversation_use_case_test.dart
- Likely named gates: edit_eight_condition_gate; latest_sent_edit_gate; edit_same_id_contract; edit_sender_auth; delete_dominates_stale_edit
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Current repo evidence does not prove the full row contract; the risk profile and missing exact tests suggest a likely behavior gap across lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart.

### Session DL-001
- Source row id: DL-001
- Scenario title: Delete visibility in the overlay follows the local gate
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-001-plan.md
- Exact scope: Close source row DL-001 for "Delete visibility in the overlay follows the local gate" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/application/delete_message_tombstone_visibility.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/delete_message_use_case_test.dart; test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart; test/features/conversation/integration/message_deletion_roundtrip_test.dart; test/features/conversation/integration/offline_inbox_roundtrip_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/core/database/migrations/044_messages_deleted_state_test.dart
- Likely named gates: delete_overlay_gate; delete_for_everyone_gate; owned_path_cleanup_guard; outgoing_tombstone_visibility; startup_delete_before_render
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/application/delete_message_use_case_test.dart and test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart.

### Session DL-002
- Source row id: DL-002
- Scenario title: “Delete for everyone” visibility in the confirmation sheet follows the second gate
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-002-plan.md
- Exact scope: Close source row DL-002 for "“Delete for everyone” visibility in the confirmation sheet follows the second gate" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/application/delete_message_tombstone_visibility.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/delete_message_use_case_test.dart; test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart; test/features/conversation/integration/message_deletion_roundtrip_test.dart; test/features/conversation/integration/offline_inbox_roundtrip_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/core/database/migrations/044_messages_deleted_state_test.dart
- Likely named gates: delete_overlay_gate; delete_for_everyone_gate; owned_path_cleanup_guard; outgoing_tombstone_visibility; startup_delete_before_render
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/application/delete_message_use_case_test.dart and test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart.

### Session DL-004
- Source row id: DL-004
- Scenario title: “Delete for me” hard-deletes the local row and cleans local artifacts only
- Row disposition: covered_in_repo
- Session classification: stale/already-covered
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-004-plan.md
- Exact scope: Close source row DL-004 for "“Delete for me” hard-deletes the local row and cleans local artifacts only" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: no execution because already covered
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/application/delete_message_tombstone_visibility.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/delete_message_use_case_test.dart:67
- Likely named gates: delete_overlay_gate; delete_for_everyone_gate; owned_path_cleanup_guard; outgoing_tombstone_visibility; startup_delete_before_render
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Exact repo proof exists for local hard-delete plus reactions/attachments/owned-file cleanup on delete-for-me.

### Session DL-005
- Source row id: DL-005
- Scenario title: Owned-path guard deletes only files belonging to the message
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-005-plan.md
- Exact scope: Close source row DL-005 for "Owned-path guard deletes only files belonging to the message" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/application/delete_message_tombstone_visibility.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/delete_message_use_case_test.dart; test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart; test/features/conversation/integration/message_deletion_roundtrip_test.dart; test/features/conversation/integration/offline_inbox_roundtrip_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/core/database/migrations/044_messages_deleted_state_test.dart
- Likely named gates: delete_overlay_gate; delete_for_everyone_gate; owned_path_cleanup_guard; outgoing_tombstone_visibility; startup_delete_before_render
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/application/delete_message_use_case_test.dart and test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart.

### Session DL-006
- Source row id: DL-006
- Scenario title: “Delete for everyone” happy path over live delivery converges on both sides
- Row disposition: covered_in_repo
- Session classification: stale/already-covered
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-006-plan.md
- Exact scope: Close source row DL-006 for "“Delete for everyone” happy path over live delivery converges on both sides" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: no execution because already covered
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/application/delete_message_tombstone_visibility.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/integration/message_deletion_roundtrip_test.dart:42
- Likely named gates: delete_overlay_gate; delete_for_everyone_gate; owned_path_cleanup_guard; outgoing_tombstone_visibility; startup_delete_before_render
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Exact repo proof exists for online delete-for-everyone sender hide plus receiver-side tombstone convergence.

### Session DL-007
- Source row id: DL-007
- Scenario title: Live send without final ack keeps a visible retryable tombstone
- Row disposition: needs_code_and_tests
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-007-plan.md
- Exact scope: Close source row DL-007 for "Live send without final ack keeps a visible retryable tombstone" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: code changes
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/application/delete_message_tombstone_visibility.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/delete_message_use_case_test.dart; test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart; test/features/conversation/integration/message_deletion_roundtrip_test.dart; test/features/conversation/integration/offline_inbox_roundtrip_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/core/database/migrations/044_messages_deleted_state_test.dart
- Likely named gates: delete_overlay_gate; delete_for_everyone_gate; owned_path_cleanup_guard; outgoing_tombstone_visibility; startup_delete_before_render
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Current repo evidence does not prove the full row contract; the risk profile and missing exact tests suggest a likely behavior gap across lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart.

### Session DL-008
- Source row id: DL-008
- Scenario title: Full delivery failure yields a visible failed tombstone and no false disappearance
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-008-plan.md
- Exact scope: Close source row DL-008 for "Full delivery failure yields a visible failed tombstone and no false disappearance" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/application/delete_message_tombstone_visibility.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/delete_message_use_case_test.dart; test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart; test/features/conversation/integration/message_deletion_roundtrip_test.dart; test/features/conversation/integration/offline_inbox_roundtrip_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/core/database/migrations/044_messages_deleted_state_test.dart
- Likely named gates: delete_overlay_gate; delete_for_everyone_gate; owned_path_cleanup_guard; outgoing_tombstone_visibility; startup_delete_before_render
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/application/delete_message_use_case_test.dart and test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart.

### Session DL-009
- Source row id: DL-009
- Scenario title: Inbox success hides the sender row locally and later deletes on the receiver after drain
- Row disposition: covered_in_repo
- Session classification: stale/already-covered
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-009-plan.md
- Exact scope: Close source row DL-009 for "Inbox success hides the sender row locally and later deletes on the receiver after drain" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: no execution because already covered
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/application/delete_message_tombstone_visibility.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/integration/message_deletion_roundtrip_test.dart:73
- Likely named gates: delete_overlay_gate; delete_for_everyone_gate; owned_path_cleanup_guard; outgoing_tombstone_visibility; startup_delete_before_render
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Exact repo proof exists for offline inbox ordering converging to a tombstoned receiver row after drain.

### Session DL-010
- Source row id: DL-010
- Scenario title: Critical regression: delete-for-everyone before the recipient opens the app
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-010-plan.md
- Exact scope: Close source row DL-010 for "Critical regression: delete-for-everyone before the recipient opens the app" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/application/delete_message_tombstone_visibility.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart; lib/features/conversation/application/load_conversation_use_case.dart
- Likely direct tests or regressions: integration_test/notification_open_ui_smoke_test.dart:950; test/features/conversation/integration/message_deletion_roundtrip_test.dart; test/features/conversation/integration/offline_inbox_roundtrip_test.dart
- Likely named gates: startup_delete_before_render; deep_link_latest_state
- Dependency on earlier sessions: none; the shared startup/deep-link first-render prerequisite is now satisfied by the landed notification-open harness
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Exact repo proof now exists in `integration_test/notification_open_ui_smoke_test.dart` for the recipient-first-open tombstone contract after a stored pre-open delete.

### Session DL-011
- Source row id: DL-011
- Scenario title: Delete arriving before the original due to transport reordering still prevents plaintext resurrection
- Row disposition: needs_code_and_tests
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-011-plan.md
- Exact scope: Close source row DL-011 for "Delete arriving before the original due to transport reordering still prevents plaintext resurrection" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: code changes
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/application/delete_message_tombstone_visibility.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/delete_message_use_case_test.dart; test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart; test/features/conversation/integration/message_deletion_roundtrip_test.dart; test/features/conversation/integration/offline_inbox_roundtrip_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/core/database/migrations/044_messages_deleted_state_test.dart
- Likely named gates: delete_overlay_gate; delete_for_everyone_gate; owned_path_cleanup_guard; outgoing_tombstone_visibility; startup_delete_before_render
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Current repo evidence does not prove the full row contract; the risk profile and missing exact tests suggest a likely behavior gap across lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart.

### Session DL-012
- Source row id: DL-012
- Scenario title: Duplicate delete deliveries are idempotent
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-012-plan.md
- Exact scope: Close source row DL-012 for "Duplicate delete deliveries are idempotent" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/application/delete_message_tombstone_visibility.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/delete_message_use_case_test.dart; test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart; test/features/conversation/integration/message_deletion_roundtrip_test.dart; test/features/conversation/integration/offline_inbox_roundtrip_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/core/database/migrations/044_messages_deleted_state_test.dart
- Likely named gates: delete_overlay_gate; delete_for_everyone_gate; owned_path_cleanup_guard; outgoing_tombstone_visibility; startup_delete_before_render
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/application/delete_message_use_case_test.dart and test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart.

### Session DL-013
- Source row id: DL-013
- Scenario title: Unauthorized delete from a non-authorized sender is rejected
- Row disposition: covered_in_repo
- Session classification: stale/already-covered
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-013-plan.md
- Exact scope: Close source row DL-013 for "Unauthorized delete from a non-authorized sender is rejected" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: no execution because already covered
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/application/delete_message_tombstone_visibility.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart:174
- Likely named gates: delete_overlay_gate; delete_for_everyone_gate; owned_path_cleanup_guard; outgoing_tombstone_visibility; startup_delete_before_render
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Exact repo proof exists for rejecting unauthorized delete payloads against a stored message.

### Session DL-014
- Source row id: DL-014
- Scenario title: Undecryptable or key-missing v2 delete is rejected without mutation
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-014-plan.md
- Exact scope: Close source row DL-014 for "Undecryptable or key-missing v2 delete is rejected without mutation" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/application/delete_message_tombstone_visibility.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/delete_message_use_case_test.dart; test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart; test/features/conversation/integration/message_deletion_roundtrip_test.dart; test/features/conversation/integration/offline_inbox_roundtrip_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/core/database/migrations/044_messages_deleted_state_test.dart
- Likely named gates: delete_overlay_gate; delete_for_everyone_gate; owned_path_cleanup_guard; outgoing_tombstone_visibility; startup_delete_before_render
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/application/delete_message_use_case_test.dart and test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart.

### Session DL-015
- Source row id: DL-015
- Scenario title: Delete cleanup clears reactions, media, and local edit / quote state linked to the target row
- Row disposition: needs_code_and_tests
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-015-plan.md
- Exact scope: Close source row DL-015 for "Delete cleanup clears reactions, media, and local edit / quote state linked to the target row" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: code changes
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/application/delete_message_tombstone_visibility.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/delete_message_use_case_test.dart; test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart; test/features/conversation/integration/message_deletion_roundtrip_test.dart; test/features/conversation/integration/offline_inbox_roundtrip_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/core/database/migrations/044_messages_deleted_state_test.dart
- Likely named gates: delete_overlay_gate; delete_for_everyone_gate; owned_path_cleanup_guard; outgoing_tombstone_visibility; startup_delete_before_render
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Current repo evidence does not prove the full row contract; the risk profile and missing exact tests suggest a likely behavior gap across lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart.

### Session DL-016
- Source row id: DL-016
- Scenario title: Late reaction or late edit after delete cannot resurrect visible content
- Row disposition: needs_code_and_tests
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-016-plan.md
- Exact scope: Close source row DL-016 for "Late reaction or late edit after delete cannot resurrect visible content" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: code changes
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/application/delete_message_tombstone_visibility.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/delete_message_use_case_test.dart; test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart; test/features/conversation/integration/message_deletion_roundtrip_test.dart; test/features/conversation/integration/offline_inbox_roundtrip_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/core/database/migrations/044_messages_deleted_state_test.dart
- Likely named gates: delete_overlay_gate; delete_for_everyone_gate; owned_path_cleanup_guard; outgoing_tombstone_visibility; startup_delete_before_render
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Current repo evidence does not prove the full row contract; the risk profile and missing exact tests suggest a likely behavior gap across lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart.

### Session DL-020
- Source row id: DL-020
- Scenario title: Notification deep-link / cold-start open after delete never shows the original inside the app shell
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-020-plan.md
- Exact scope: Close source row DL-020 for "Notification deep-link / cold-start open after delete never shows the original inside the app shell" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/application/delete_message_tombstone_visibility.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart; lib/features/conversation/application/load_conversation_use_case.dart
- Likely direct tests or regressions: integration_test/notification_open_ui_smoke_test.dart:991; test/features/conversation/integration/message_deletion_roundtrip_test.dart; test/features/conversation/integration/offline_inbox_roundtrip_test.dart
- Likely named gates: startup_delete_before_render; deep_link_latest_state
- Dependency on earlier sessions: none; the shared startup/deep-link first-render prerequisite is now satisfied by the landed notification-open harness
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Exact repo proof now exists in `integration_test/notification_open_ui_smoke_test.dart` for the warm local app-shell open contract after a stored delete.

### Session SC-001
- Source row id: SC-001
- Scenario title: App restart reconstructs quote, edit, delete, and reaction state from durable storage without stale UI
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-SC-001-plan.md
- Exact scope: Close source row SC-001 for "App restart reconstructs quote, edit, delete, and reaction state from durable storage without stale UI" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/application/load_conversation_use_case.dart; lib/features/conversation/application/chat_message_listener.dart; lib/features/conversation/application/reaction_listener.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/load_conversation_use_case.dart
- Likely direct tests or regressions: integration_test/notification_open_ui_smoke_test.dart:1081; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart
- Likely named gates: durable_state_rebuild; stream_convergence; sender_identity_alignment; delete_wins_conflict_resolution; schema_overlay_state_migration
- Dependency on earlier sessions: none; the shared startup/deep-link first-render prerequisite is now satisfied by the landed notification-open harness
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: `SC-008` is now complemented by exact repo proof in `integration_test/notification_open_ui_smoke_test.dart` that a full app relaunch and reopen shows the latest durable quote, edit, delete, and reaction state on the first readable frame.

### Session SC-002
- Source row id: SC-002
- Scenario title: While the conversation is open or backgrounded, incoming reaction / edit / delete changes converge without manual refresh
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-SC-002-plan.md
- Exact scope: Close source row SC-002 for "While the conversation is open or backgrounded, incoming reaction / edit / delete changes converge without manual refresh" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/application/load_conversation_use_case.dart; lib/features/conversation/application/chat_message_listener.dart; lib/features/conversation/application/reaction_listener.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart
- Likely direct tests or regressions: test/features/conversation/application/load_conversation_use_case_test.dart; test/features/conversation/application/reaction_listener_test.dart; test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart; test/features/conversation/integration/offline_inbox_roundtrip_test.dart; test/features/conversation/integration/message_deletion_roundtrip_test.dart; test/features/conversation/integration/emoji_reaction_exchange_test.dart; test/features/conversation/integration/quote_reply_thread_test.dart
- Likely named gates: durable_state_rebuild; stream_convergence; sender_identity_alignment; delete_wins_conflict_resolution; schema_overlay_state_migration
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/application/load_conversation_use_case.dart and lib/features/conversation/application/chat_message_listener.dart, but exact row-level proof is not yet explicit in test/features/conversation/application/load_conversation_use_case_test.dart and test/features/conversation/application/reaction_listener_test.dart.

### Session SC-003
- Source row id: SC-003
- Scenario title: Stream sender, top-level envelope sender, and decrypted payload sender must agree for mutating actions
- Row disposition: needs_code_and_tests
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-SC-003-plan.md
- Exact scope: Close source row SC-003 for "Stream sender, top-level envelope sender, and decrypted payload sender must agree for mutating actions" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: code changes
- Likely code-entry files: lib/features/conversation/application/load_conversation_use_case.dart; lib/features/conversation/application/chat_message_listener.dart; lib/features/conversation/application/reaction_listener.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart
- Likely direct tests or regressions: test/features/conversation/application/load_conversation_use_case_test.dart; test/features/conversation/application/reaction_listener_test.dart; test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart; test/features/conversation/integration/offline_inbox_roundtrip_test.dart; test/features/conversation/integration/message_deletion_roundtrip_test.dart; test/features/conversation/integration/emoji_reaction_exchange_test.dart; test/features/conversation/integration/quote_reply_thread_test.dart
- Likely named gates: sender_identity_alignment
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Current repo evidence does not prove the full row contract; the risk profile and missing exact tests suggest a likely behavior gap across lib/features/conversation/application/load_conversation_use_case.dart and lib/features/conversation/application/chat_message_listener.dart.

### Session SC-004
- Source row id: SC-004
- Scenario title: Concurrent actions on the same message resolve to one deterministic winner state
- Row disposition: needs_code_and_tests
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-SC-004-plan.md
- Exact scope: Close source row SC-004 for "Concurrent actions on the same message resolve to one deterministic winner state" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: code changes
- Likely code-entry files: lib/features/conversation/application/load_conversation_use_case.dart; lib/features/conversation/application/chat_message_listener.dart; lib/features/conversation/application/reaction_listener.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart
- Likely direct tests or regressions: test/features/conversation/application/load_conversation_use_case_test.dart; test/features/conversation/application/reaction_listener_test.dart; test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart; test/features/conversation/integration/offline_inbox_roundtrip_test.dart; test/features/conversation/integration/message_deletion_roundtrip_test.dart; test/features/conversation/integration/emoji_reaction_exchange_test.dart; test/features/conversation/integration/quote_reply_thread_test.dart
- Likely named gates: durable_state_rebuild; stream_convergence; sender_identity_alignment; delete_wins_conflict_resolution; schema_overlay_state_migration
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Current repo evidence does not prove the full row contract; the risk profile and missing exact tests suggest a likely behavior gap across lib/features/conversation/application/load_conversation_use_case.dart and lib/features/conversation/application/chat_message_listener.dart.

### Session SC-005
- Source row id: SC-005
- Scenario title: Listener / subscription lifecycle never causes duplicate application or leaks
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-SC-005-plan.md
- Exact scope: Close source row SC-005 for "Listener / subscription lifecycle never causes duplicate application or leaks" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/application/load_conversation_use_case.dart; lib/features/conversation/application/chat_message_listener.dart; lib/features/conversation/application/reaction_listener.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart
- Likely direct tests or regressions: test/features/conversation/application/load_conversation_use_case_test.dart; test/features/conversation/application/reaction_listener_test.dart; test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart; test/features/conversation/integration/offline_inbox_roundtrip_test.dart; test/features/conversation/integration/message_deletion_roundtrip_test.dart; test/features/conversation/integration/emoji_reaction_exchange_test.dart; test/features/conversation/integration/quote_reply_thread_test.dart
- Likely named gates: durable_state_rebuild; stream_convergence; sender_identity_alignment; delete_wins_conflict_resolution; schema_overlay_state_migration
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/application/load_conversation_use_case.dart and lib/features/conversation/application/chat_message_listener.dart, but exact row-level proof is not yet explicit in test/features/conversation/application/load_conversation_use_case_test.dart and test/features/conversation/application/reaction_listener_test.dart.

### Session SC-010
- Source row id: SC-010
- Scenario title: Queued mutating actions converge after reconnect or remain explicitly retryable with a reason
- Row disposition: needs_code_and_tests
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-SC-010-plan.md
- Exact scope: Close source row SC-010 for "Queued mutating actions converge after reconnect or remain explicitly retryable with a reason" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: code changes
- Likely code-entry files: lib/features/conversation/application/load_conversation_use_case.dart; lib/features/conversation/application/chat_message_listener.dart; lib/features/conversation/application/reaction_listener.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart
- Likely direct tests or regressions: test/features/conversation/application/load_conversation_use_case_test.dart; test/features/conversation/application/reaction_listener_test.dart; test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart; test/features/conversation/integration/offline_inbox_roundtrip_test.dart; test/features/conversation/integration/message_deletion_roundtrip_test.dart; test/features/conversation/integration/emoji_reaction_exchange_test.dart; test/features/conversation/integration/quote_reply_thread_test.dart
- Likely named gates: durable_state_rebuild; stream_convergence; sender_identity_alignment; delete_wins_conflict_resolution; schema_overlay_state_migration
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Current repo evidence does not prove the full row contract; the risk profile and missing exact tests suggest a likely behavior gap across lib/features/conversation/application/load_conversation_use_case.dart and lib/features/conversation/application/chat_message_listener.dart.

### Session OG-002
- Source row id: OG-002
- Scenario title: Conversation host and feed direct-thread host stay behaviorally aligned
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-OG-002-plan.md
- Exact scope: Close source row OG-002 for "Conversation host and feed direct-thread host stay behaviorally aligned" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/widgets/message_context_overlay.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/presentation/widgets/letter_card.dart; lib/features/feed/presentation/widgets/message_bubble.dart
- Likely direct tests or regressions: test/features/conversation/presentation/widgets/message_context_overlay_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart
- Likely named gates: overlay_open_gate; overlay_action_order; host_parity_overlay; deleted_row_overlay_guard
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/widgets/message_context_overlay.dart and lib/features/conversation/presentation/screens/conversation_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/presentation/widgets/message_context_overlay_test.dart and test/features/conversation/presentation/screens/conversation_screen_test.dart.

### Session OG-006
- Source row id: OG-006
- Scenario title: Busy composer states suppress only Edit, not unrelated actions
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-OG-006-plan.md
- Exact scope: Close source row OG-006 for "Busy composer states suppress only Edit, not unrelated actions" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/widgets/message_context_overlay.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/presentation/widgets/letter_card.dart; lib/features/feed/presentation/widgets/message_bubble.dart
- Likely direct tests or regressions: test/features/conversation/presentation/widgets/message_context_overlay_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart
- Likely named gates: overlay_open_gate; overlay_action_order; host_parity_overlay; deleted_row_overlay_guard
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/widgets/message_context_overlay.dart and lib/features/conversation/presentation/screens/conversation_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/presentation/widgets/message_context_overlay_test.dart and test/features/conversation/presentation/screens/conversation_screen_test.dart.

### Session OG-009
- Source row id: OG-009
- Scenario title: Rapid repeat long-presses and rapid action taps do not double-apply effects
- Row disposition: needs_code_and_tests
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-OG-009-plan.md
- Exact scope: Close source row OG-009 for "Rapid repeat long-presses and rapid action taps do not double-apply effects" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: code changes
- Likely code-entry files: lib/features/conversation/presentation/widgets/message_context_overlay.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/presentation/widgets/letter_card.dart; lib/features/feed/presentation/widgets/message_bubble.dart
- Likely direct tests or regressions: test/features/conversation/presentation/widgets/message_context_overlay_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart
- Likely named gates: overlay_open_gate; overlay_action_order; host_parity_overlay; deleted_row_overlay_guard
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Current repo evidence does not prove the full row contract; the risk profile and missing exact tests suggest a likely behavior gap across lib/features/conversation/presentation/widgets/message_context_overlay.dart and lib/features/conversation/presentation/screens/conversation_screen.dart.

### Session RX-004
- Source row id: RX-004
- Scenario title: Full picker non-preset emoji round-trips correctly
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-004-plan.md
- Exact scope: Close source row RX-004 for "Full picker non-preset emoji round-trips correctly" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/widgets/reaction_bar.dart; lib/features/conversation/presentation/widgets/reaction_display.dart; lib/features/conversation/application/send_reaction_use_case.dart; lib/features/conversation/application/remove_reaction_use_case.dart; lib/features/conversation/application/handle_incoming_reaction_use_case.dart; lib/features/conversation/application/reaction_listener.dart; lib/features/conversation/domain/repositories/reaction_repository_impl.dart; lib/core/database/helpers/reactions_db_helpers.dart
- Likely direct tests or regressions: test/features/conversation/application/send_reaction_use_case_test.dart; test/features/conversation/application/remove_reaction_use_case_test.dart; test/features/conversation/application/handle_incoming_reaction_use_case_test.dart; test/features/conversation/application/reaction_listener_test.dart; test/features/conversation/integration/emoji_reaction_exchange_test.dart; test/core/database/migrations/016_message_reactions_test.dart
- Likely named gates: reaction_non_deleted_gate; reaction_toggle_replace; reaction_sender_auth; reaction_decrypt_gate; reaction_listener_lifecycle
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/widgets/reaction_bar.dart and lib/features/conversation/presentation/widgets/reaction_display.dart, but exact row-level proof is not yet explicit in test/features/conversation/application/send_reaction_use_case_test.dart and test/features/conversation/application/remove_reaction_use_case_test.dart.

### Session RX-005
- Source row id: RX-005
- Scenario title: Same-emoji reactions from A and B group into one chip with a count and own highlight
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-005-plan.md
- Exact scope: Close source row RX-005 for "Same-emoji reactions from A and B group into one chip with a count and own highlight" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/widgets/reaction_bar.dart; lib/features/conversation/presentation/widgets/reaction_display.dart; lib/features/conversation/application/send_reaction_use_case.dart; lib/features/conversation/application/remove_reaction_use_case.dart; lib/features/conversation/application/handle_incoming_reaction_use_case.dart; lib/features/conversation/application/reaction_listener.dart; lib/features/conversation/domain/repositories/reaction_repository_impl.dart; lib/core/database/helpers/reactions_db_helpers.dart
- Likely direct tests or regressions: test/features/conversation/application/send_reaction_use_case_test.dart; test/features/conversation/application/remove_reaction_use_case_test.dart; test/features/conversation/application/handle_incoming_reaction_use_case_test.dart; test/features/conversation/application/reaction_listener_test.dart; test/features/conversation/integration/emoji_reaction_exchange_test.dart; test/core/database/migrations/016_message_reactions_test.dart
- Likely named gates: reaction_non_deleted_gate; reaction_toggle_replace; reaction_sender_auth; reaction_decrypt_gate; reaction_listener_lifecycle
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/widgets/reaction_bar.dart and lib/features/conversation/presentation/widgets/reaction_display.dart, but exact row-level proof is not yet explicit in test/features/conversation/application/send_reaction_use_case_test.dart and test/features/conversation/application/remove_reaction_use_case_test.dart.

### Session RX-006
- Source row id: RX-006
- Scenario title: Tapping an inline reaction chip uses the same toggle / replace semantics as the overlay bar
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-006-plan.md
- Exact scope: Close source row RX-006 for "Tapping an inline reaction chip uses the same toggle / replace semantics as the overlay bar" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/widgets/reaction_bar.dart; lib/features/conversation/presentation/widgets/reaction_display.dart; lib/features/conversation/application/send_reaction_use_case.dart; lib/features/conversation/application/remove_reaction_use_case.dart; lib/features/conversation/application/handle_incoming_reaction_use_case.dart; lib/features/conversation/application/reaction_listener.dart; lib/features/conversation/domain/repositories/reaction_repository_impl.dart; lib/core/database/helpers/reactions_db_helpers.dart
- Likely direct tests or regressions: test/features/conversation/application/send_reaction_use_case_test.dart; test/features/conversation/application/remove_reaction_use_case_test.dart; test/features/conversation/application/handle_incoming_reaction_use_case_test.dart; test/features/conversation/application/reaction_listener_test.dart; test/features/conversation/integration/emoji_reaction_exchange_test.dart; test/core/database/migrations/016_message_reactions_test.dart
- Likely named gates: reaction_non_deleted_gate; reaction_toggle_replace; reaction_sender_auth; reaction_decrypt_gate; reaction_listener_lifecycle
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/widgets/reaction_bar.dart and lib/features/conversation/presentation/widgets/reaction_display.dart, but exact row-level proof is not yet explicit in test/features/conversation/application/send_reaction_use_case_test.dart and test/features/conversation/application/remove_reaction_use_case_test.dart.

### Session RX-010
- Source row id: RX-010
- Scenario title: Out-of-order add/remove deliveries resolve by newest logical state
- Row disposition: needs_code_and_tests
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-010-plan.md
- Exact scope: Close source row RX-010 for "Out-of-order add/remove deliveries resolve by newest logical state" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: code changes
- Likely code-entry files: lib/features/conversation/presentation/widgets/reaction_bar.dart; lib/features/conversation/presentation/widgets/reaction_display.dart; lib/features/conversation/application/send_reaction_use_case.dart; lib/features/conversation/application/remove_reaction_use_case.dart; lib/features/conversation/application/handle_incoming_reaction_use_case.dart; lib/features/conversation/application/reaction_listener.dart; lib/features/conversation/domain/repositories/reaction_repository_impl.dart; lib/core/database/helpers/reactions_db_helpers.dart
- Likely direct tests or regressions: test/features/conversation/application/send_reaction_use_case_test.dart; test/features/conversation/application/remove_reaction_use_case_test.dart; test/features/conversation/application/handle_incoming_reaction_use_case_test.dart; test/features/conversation/application/reaction_listener_test.dart; test/features/conversation/integration/emoji_reaction_exchange_test.dart; test/core/database/migrations/016_message_reactions_test.dart
- Likely named gates: reaction_non_deleted_gate; reaction_toggle_replace; reaction_sender_auth; reaction_decrypt_gate; reaction_listener_lifecycle
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Current repo evidence does not prove the full row contract; the risk profile and missing exact tests suggest a likely behavior gap across lib/features/conversation/presentation/widgets/reaction_bar.dart and lib/features/conversation/presentation/widgets/reaction_display.dart.

### Session RX-013
- Source row id: RX-013
- Scenario title: Listener start/stop/dispose does not create duplicate reaction application
- Row disposition: covered_in_repo
- Session classification: stale/already-covered
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RX-013-plan.md
- Exact scope: Close source row RX-013 for "Listener start/stop/dispose does not create duplicate reaction application" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: no execution because already covered
- Likely code-entry files: lib/features/conversation/presentation/widgets/reaction_bar.dart; lib/features/conversation/presentation/widgets/reaction_display.dart; lib/features/conversation/application/send_reaction_use_case.dart; lib/features/conversation/application/remove_reaction_use_case.dart; lib/features/conversation/application/handle_incoming_reaction_use_case.dart; lib/features/conversation/application/reaction_listener.dart; lib/features/conversation/domain/repositories/reaction_repository_impl.dart; lib/core/database/helpers/reactions_db_helpers.dart
- Likely direct tests or regressions: test/features/conversation/application/reaction_listener_test.dart:244; test/features/conversation/application/reaction_listener_test.dart:249; test/features/conversation/application/reaction_listener_test.dart:261
- Likely named gates: reaction_non_deleted_gate; reaction_toggle_replace; reaction_sender_auth; reaction_decrypt_gate; reaction_listener_lifecycle
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Exact repo proof exists for start/stop/dispose lifecycle behavior and duplicate-start safety.

### Session CP-002
- Source row id: CP-002
- Scenario title: Copy happy path in the shared feed direct-thread host
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-CP-002-plan.md
- Exact scope: Close source row CP-002 for "Copy happy path in the shared feed direct-thread host" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/widgets/message_context_overlay.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart
- Likely direct tests or regressions: test/features/conversation/presentation/widgets/message_context_overlay_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart
- Likely named gates: copy_text_present_gate; copy_local_only_invariant; copy_host_parity
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/widgets/message_context_overlay.dart and lib/features/conversation/presentation/screens/conversation_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/presentation/widgets/message_context_overlay_test.dart and test/features/conversation/presentation/screens/conversation_screen_test.dart.

### Session CP-004
- Source row id: CP-004
- Scenario title: Multiline, emoji, and RTL text are copied exactly
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-CP-004-plan.md
- Exact scope: Close source row CP-004 for "Multiline, emoji, and RTL text are copied exactly" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/widgets/message_context_overlay.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart
- Likely direct tests or regressions: test/features/conversation/presentation/widgets/message_context_overlay_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart
- Likely named gates: copy_text_present_gate; copy_local_only_invariant; copy_host_parity
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/widgets/message_context_overlay.dart and lib/features/conversation/presentation/screens/conversation_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/presentation/widgets/message_context_overlay_test.dart and test/features/conversation/presentation/screens/conversation_screen_test.dart.

### Session RP-002
- Source row id: RP-002
- Scenario title: Swipe-to-reply is offered only for incoming non-deleted messages and joins the same quote flow
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RP-002-plan.md
- Exact scope: Close source row RP-002 for "Swipe-to-reply is offered only for incoming non-deleted messages and joins the same quote flow" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/application/load_conversation_use_case.dart; lib/features/feed/presentation/widgets/message_bubble.dart; lib/features/feed/presentation/widgets/quote_preview_bar.dart
- Likely direct tests or regressions: test/features/conversation/integration/quote_reply_thread_test.dart; test/features/conversation/application/send_chat_message_use_case_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/core/database/migrations/009_quoted_message_id_test.dart
- Likely named gates: reply_entry_gate; quote_resolution_gate; quotedMessageId_preservation; reply_vs_edit_mutual_exclusion
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/integration/quote_reply_thread_test.dart and test/features/conversation/application/send_chat_message_use_case_test.dart.

### Session RP-008
- Source row id: RP-008
- Scenario title: If the quoted source is later deleted, existing replies degrade gracefully to unavailable
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RP-008-plan.md
- Exact scope: Close source row RP-008 for "If the quoted source is later deleted, existing replies degrade gracefully to unavailable" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/application/load_conversation_use_case.dart; lib/features/feed/presentation/widgets/message_bubble.dart; lib/features/feed/presentation/widgets/quote_preview_bar.dart; lib/features/feed/presentation/screens/feed_screen.dart
- Likely direct tests or regressions: test/features/conversation/integration/quote_reply_thread_test.dart; test/features/conversation/application/send_chat_message_use_case_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/core/database/migrations/009_quoted_message_id_test.dart
- Likely named gates: reply_entry_gate; quote_resolution_gate; quotedMessageId_preservation; reply_vs_edit_mutual_exclusion
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/integration/quote_reply_thread_test.dart and test/features/conversation/application/send_chat_message_use_case_test.dart.

### Session RP-010
- Source row id: RP-010
- Scenario title: Offline / inbox delivery preserves `quotedMessageId` across restart
- Row disposition: needs_code_and_tests
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RP-010-plan.md
- Exact scope: Close source row RP-010 for "Offline / inbox delivery preserves `quotedMessageId` across restart" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: code changes
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/application/load_conversation_use_case.dart; lib/features/feed/presentation/widgets/message_bubble.dart; lib/features/feed/presentation/widgets/quote_preview_bar.dart
- Likely direct tests or regressions: test/features/conversation/integration/offline_inbox_roundtrip_test.dart; test/features/conversation/integration/quote_reply_thread_test.dart
- Likely named gates: reply_entry_gate; quote_resolution_gate; quotedMessageId_preservation; reply_vs_edit_mutual_exclusion
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Current repo evidence does not prove the full row contract; the risk profile and missing exact tests suggest a likely behavior gap across lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart.

### Session RP-011
- Source row id: RP-011
- Scenario title: Conversation and feed direct-thread hosts keep reply behavior aligned
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RP-011-plan.md
- Exact scope: Close source row RP-011 for "Conversation and feed direct-thread hosts keep reply behavior aligned" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/application/load_conversation_use_case.dart; lib/features/feed/presentation/widgets/message_bubble.dart; lib/features/feed/presentation/widgets/quote_preview_bar.dart
- Likely direct tests or regressions: test/features/conversation/integration/quote_reply_thread_test.dart; test/features/conversation/application/send_chat_message_use_case_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/core/database/migrations/009_quoted_message_id_test.dart
- Likely named gates: reply_entry_gate; quote_resolution_gate; quotedMessageId_preservation; reply_vs_edit_mutual_exclusion
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/integration/quote_reply_thread_test.dart and test/features/conversation/application/send_chat_message_use_case_test.dart.

### Session RP-012
- Source row id: RP-012
- Scenario title: Starting a reply clears active edit mode so both modes cannot coexist
- Row disposition: needs_code_and_tests
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RP-012-plan.md
- Exact scope: Close source row RP-012 for "Starting a reply clears active edit mode so both modes cannot coexist" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: code changes
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/application/load_conversation_use_case.dart; lib/features/feed/presentation/widgets/message_bubble.dart; lib/features/feed/presentation/widgets/quote_preview_bar.dart
- Likely direct tests or regressions: test/features/conversation/integration/quote_reply_thread_test.dart; test/features/conversation/application/send_chat_message_use_case_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/core/database/migrations/009_quoted_message_id_test.dart
- Likely named gates: reply_entry_gate; quote_resolution_gate; quotedMessageId_preservation; reply_vs_edit_mutual_exclusion
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Current repo evidence does not prove the full row contract; the risk profile and missing exact tests suggest a likely behavior gap across lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart.

### Session ED-012
- Source row id: ED-012
- Scenario title: Offline / inbox edit delivery survives restart and applies correctly once drained
- Row disposition: needs_code_and_tests
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-012-plan.md
- Exact scope: Close source row ED-012 for "Offline / inbox edit delivery survives restart and applies correctly once drained" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: code changes
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/send_chat_message_use_case_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/features/conversation/application/load_conversation_use_case_test.dart
- Likely named gates: edit_eight_condition_gate; latest_sent_edit_gate; edit_same_id_contract; edit_sender_auth; delete_dominates_stale_edit
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Current repo evidence does not prove the full row contract; the risk profile and missing exact tests suggest a likely behavior gap across lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart.

### Session ED-014
- Source row id: ED-014
- Scenario title: Conversation and feed direct-thread hosts keep edit behavior aligned
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-014-plan.md
- Exact scope: Close source row ED-014 for "Conversation and feed direct-thread hosts keep edit behavior aligned" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/send_chat_message_use_case_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/features/conversation/application/load_conversation_use_case_test.dart
- Likely named gates: edit_eight_condition_gate; latest_sent_edit_gate; edit_same_id_contract; edit_sender_auth; delete_dominates_stale_edit
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/application/send_chat_message_use_case_test.dart and test/features/conversation/presentation/screens/conversation_screen_test.dart.

### Session ED-015
- Source row id: ED-015
- Scenario title: v2 preferred / v1 fallback preserves `action='edit'` and `editedAt`
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-ED-015-plan.md
- Exact scope: Close source row ED-015 for "v2 preferred / v1 fallback preserves `action='edit'` and `editedAt`" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/send_chat_message_use_case_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/features/conversation/application/load_conversation_use_case_test.dart
- Likely named gates: edit_eight_condition_gate; latest_sent_edit_gate; edit_same_id_contract; edit_sender_auth; delete_dominates_stale_edit
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/application/send_chat_message_use_case_test.dart and test/features/conversation/presentation/screens/conversation_screen_test.dart.

### Session DL-003
- Source row id: DL-003
- Scenario title: Canceling or dismissing the delete sheet is a no-op
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-003-plan.md
- Exact scope: Close source row DL-003 for "Canceling or dismissing the delete sheet is a no-op" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/application/delete_message_tombstone_visibility.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/delete_message_use_case_test.dart; test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart; test/features/conversation/integration/message_deletion_roundtrip_test.dart; test/features/conversation/integration/offline_inbox_roundtrip_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/core/database/migrations/044_messages_deleted_state_test.dart
- Likely named gates: delete_overlay_gate; delete_for_everyone_gate; owned_path_cleanup_guard; outgoing_tombstone_visibility; startup_delete_before_render
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/application/delete_message_use_case_test.dart and test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart.

### Session DL-017
- Source row id: DL-017
- Scenario title: Sender restart after pending tombstone persistence still converges to the correct visibility state
- Row disposition: needs_code_and_tests
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-017-plan.md
- Exact scope: Close source row DL-017 for "Sender restart after pending tombstone persistence still converges to the correct visibility state" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: code changes
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/application/delete_message_tombstone_visibility.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/delete_message_use_case_test.dart; test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart; test/features/conversation/integration/message_deletion_roundtrip_test.dart; test/features/conversation/integration/offline_inbox_roundtrip_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/core/database/migrations/044_messages_deleted_state_test.dart
- Likely named gates: delete_overlay_gate; delete_for_everyone_gate; owned_path_cleanup_guard; outgoing_tombstone_visibility; startup_delete_before_render
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Current repo evidence does not prove the full row contract; the risk profile and missing exact tests suggest a likely behavior gap across lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart.

### Session DL-018
- Source row id: DL-018
- Scenario title: Conversation and feed direct-thread hosts keep delete behavior aligned
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-018-plan.md
- Exact scope: Close source row DL-018 for "Conversation and feed direct-thread hosts keep delete behavior aligned" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/application/delete_message_tombstone_visibility.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/delete_message_use_case_test.dart; test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart; test/features/conversation/integration/message_deletion_roundtrip_test.dart; test/features/conversation/integration/offline_inbox_roundtrip_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/core/database/migrations/044_messages_deleted_state_test.dart
- Likely named gates: delete_overlay_gate; delete_for_everyone_gate; owned_path_cleanup_guard; outgoing_tombstone_visibility; startup_delete_before_render
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/application/delete_message_use_case_test.dart and test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart.

### Session DL-019
- Source row id: DL-019
- Scenario title: Delete from a now-blocked sender still follows one explicit, tested policy for already-stored authored messages
- Row disposition: needs_code_and_tests
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-DL-019-plan.md
- Exact scope: Close source row DL-019 for "Delete from a now-blocked sender still follows one explicit, tested policy for already-stored authored messages" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: code changes
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/application/delete_message_tombstone_visibility.dart; lib/features/conversation/domain/models/conversation_message.dart; lib/features/conversation/domain/repositories/message_repository_impl.dart
- Likely direct tests or regressions: test/features/conversation/application/delete_message_use_case_test.dart; test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart; test/features/conversation/integration/message_deletion_roundtrip_test.dart; test/features/conversation/integration/offline_inbox_roundtrip_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/core/database/migrations/044_messages_deleted_state_test.dart
- Likely named gates: delete_overlay_gate; delete_for_everyone_gate; owned_path_cleanup_guard; outgoing_tombstone_visibility; startup_delete_before_render
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Current repo evidence does not prove the full row contract; the risk profile and missing exact tests suggest a likely behavior gap across lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart.

### Session SC-006
- Source row id: SC-006
- Scenario title: Schema migration / upgrade preserves old messages and loads new overlay state fields safely
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-SC-006-plan.md
- Exact scope: Close source row SC-006 for "Schema migration / upgrade preserves old messages and loads new overlay state fields safely" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/application/load_conversation_use_case.dart; lib/features/conversation/application/chat_message_listener.dart; lib/features/conversation/application/reaction_listener.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart
- Likely direct tests or regressions: test/features/conversation/application/load_conversation_use_case_test.dart; test/features/conversation/application/reaction_listener_test.dart; test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart; test/features/conversation/integration/offline_inbox_roundtrip_test.dart; test/features/conversation/integration/message_deletion_roundtrip_test.dart; test/features/conversation/integration/emoji_reaction_exchange_test.dart; test/features/conversation/integration/quote_reply_thread_test.dart
- Likely named gates: durable_state_rebuild; stream_convergence; sender_identity_alignment; delete_wins_conflict_resolution; schema_overlay_state_migration
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/application/load_conversation_use_case.dart and lib/features/conversation/application/chat_message_listener.dart, but exact row-level proof is not yet explicit in test/features/conversation/application/load_conversation_use_case_test.dart and test/features/conversation/application/reaction_listener_test.dart.

### Session SC-008
- Source row id: SC-008
- Scenario title: After restart, conversation and feed direct-thread surfaces reconstruct the same visible truth
- Row disposition: needs_code_and_tests
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-SC-008-plan.md
- Exact scope: Close source row SC-008 for "After restart, conversation and feed direct-thread surfaces reconstruct the same visible truth" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: code changes
- Likely code-entry files: lib/features/conversation/application/load_conversation_use_case.dart; lib/features/conversation/application/chat_message_listener.dart; lib/features/conversation/application/reaction_listener.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart
- Likely direct tests or regressions: test/features/conversation/application/load_conversation_use_case_test.dart; test/features/conversation/application/reaction_listener_test.dart; test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart; test/features/conversation/integration/offline_inbox_roundtrip_test.dart; test/features/conversation/integration/message_deletion_roundtrip_test.dart; test/features/conversation/integration/emoji_reaction_exchange_test.dart; test/features/conversation/integration/quote_reply_thread_test.dart
- Likely named gates: durable_state_rebuild; stream_convergence; sender_identity_alignment; delete_wins_conflict_resolution; schema_overlay_state_migration
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Current repo evidence does not prove the full row contract; the risk profile and missing exact tests suggest a likely behavior gap across lib/features/conversation/application/load_conversation_use_case.dart and lib/features/conversation/application/chat_message_listener.dart.

### Session SC-009
- Source row id: SC-009
- Scenario title: In-app deep-link render after background edit or delete resolves to the latest state
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-SC-009-plan.md
- Exact scope: Close source row SC-009 for "In-app deep-link render after background edit or delete resolves to the latest state" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/application/load_conversation_use_case.dart; lib/features/conversation/application/chat_message_listener.dart; lib/features/conversation/application/reaction_listener.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/load_conversation_use_case.dart
- Likely direct tests or regressions: integration_test/notification_open_ui_smoke_test.dart:1032; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart
- Likely named gates: durable_state_rebuild; stream_convergence; sender_identity_alignment; delete_wins_conflict_resolution; schema_overlay_state_migration
- Dependency on earlier sessions: none; the shared startup/deep-link first-render prerequisite is now satisfied by the landed notification-open harness
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Exact repo proof now exists in `integration_test/notification_open_ui_smoke_test.dart` that the warm remote background-open route-entry frame already reflects the latest stored edit/delete truth.

### Session OG-010
- Source row id: OG-010
- Scenario title: Localized, RTL, and long-content overlays stay readable and clamped to the viewport
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-OG-010-plan.md
- Exact scope: Close source row OG-010 for "Localized, RTL, and long-content overlays stay readable and clamped to the viewport" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/widgets/message_context_overlay.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/presentation/widgets/letter_card.dart; lib/features/feed/presentation/widgets/message_bubble.dart
- Likely direct tests or regressions: test/features/conversation/presentation/widgets/message_context_overlay_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart
- Likely named gates: overlay_open_gate; overlay_action_order; host_parity_overlay; deleted_row_overlay_guard
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/widgets/message_context_overlay.dart and lib/features/conversation/presentation/screens/conversation_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/presentation/widgets/message_context_overlay_test.dart and test/features/conversation/presentation/screens/conversation_screen_test.dart.

### Session CP-005
- Source row id: CP-005
- Scenario title: Rapid repeated copy hides the old snackbar before showing the new one
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-CP-005-plan.md
- Exact scope: Close source row CP-005 for "Rapid repeated copy hides the old snackbar before showing the new one" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/presentation/widgets/message_context_overlay.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart
- Likely direct tests or regressions: test/features/conversation/presentation/widgets/message_context_overlay_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart
- Likely named gates: copy_text_present_gate; copy_local_only_invariant; copy_host_parity
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/presentation/widgets/message_context_overlay.dart and lib/features/conversation/presentation/screens/conversation_screen.dart, but exact row-level proof is not yet explicit in test/features/conversation/presentation/widgets/message_context_overlay_test.dart and test/features/conversation/presentation/screens/conversation_screen_test.dart.

### Session RP-009
- Source row id: RP-009
- Scenario title: If the quoted source is later edited, reply rendering stays stable
- Row disposition: needs_code_and_tests
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-RP-009-plan.md
- Exact scope: Close source row RP-009 for "If the quoted source is later edited, reply rendering stays stable" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: code changes
- Likely code-entry files: lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/application/load_conversation_use_case.dart; lib/features/feed/presentation/widgets/message_bubble.dart; lib/features/feed/presentation/widgets/quote_preview_bar.dart; lib/features/feed/presentation/screens/feed_screen.dart
- Likely direct tests or regressions: test/features/conversation/integration/quote_reply_thread_test.dart; test/features/conversation/application/send_chat_message_use_case_test.dart; test/features/conversation/presentation/screens/conversation_screen_test.dart; test/features/feed/presentation/screens/feed_screen_test.dart; test/core/database/migrations/009_quoted_message_id_test.dart
- Likely named gates: reply_entry_gate; quote_resolution_gate; quotedMessageId_preservation; reply_vs_edit_mutual_exclusion
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Current repo evidence does not prove the full row contract; the risk profile and missing exact tests suggest a likely behavior gap across lib/features/conversation/presentation/screens/conversation_screen.dart and lib/features/feed/presentation/screens/feed_screen.dart.

### Session SC-007
- Source row id: SC-007
- Scenario title: Localization, mixed-script, and RTL content stay correct across quote bars, deleted placeholders, edited indicators, snackbars, and reaction chips
- Row disposition: needs_tests_only
- Session classification: implementation-ready
- Intended plan file: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-SC-007-plan.md
- Exact scope: Close source row SC-007 for "Localization, mixed-script, and RTL content stay correct across quote bars, deleted placeholders, edited indicators, snackbars, and reaction chips" without merging it into adjacent rows; prove the row contract across the stated hosts, persistence, and transport semantics that the matrix requires.
- Execution ownership: tests only
- Likely code-entry files: lib/features/conversation/application/load_conversation_use_case.dart; lib/features/conversation/application/chat_message_listener.dart; lib/features/conversation/application/reaction_listener.dart; lib/features/conversation/application/send_chat_message_use_case.dart; lib/features/conversation/application/delete_message_use_case.dart; lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart; lib/features/conversation/presentation/screens/conversation_screen.dart; lib/features/feed/presentation/screens/feed_screen.dart
- Likely direct tests or regressions: test/features/conversation/application/load_conversation_use_case_test.dart; test/features/conversation/application/reaction_listener_test.dart; test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart; test/features/conversation/integration/offline_inbox_roundtrip_test.dart; test/features/conversation/integration/message_deletion_roundtrip_test.dart; test/features/conversation/integration/emoji_reaction_exchange_test.dart; test/features/conversation/integration/quote_reply_thread_test.dart
- Likely named gates: durable_state_rebuild; stream_convergence; sender_identity_alignment; delete_wins_conflict_resolution; schema_overlay_state_migration
- Dependency on earlier sessions: none
- Matrix or closure docs to update when done: Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules.md; Test-Flight-Improv/Message-Bubble-List-Feature/message_context_overlay_test_matrix_full_with_rules-session-breakdown.md
- Evidence note: Repo code for this journey appears present in lib/features/conversation/application/load_conversation_use_case.dart and lib/features/conversation/application/chat_message_listener.dart, but exact row-level proof is not yet explicit in test/features/conversation/application/load_conversation_use_case_test.dart and test/features/conversation/application/reaction_listener_test.dart.

## Final Program Verdict

- Verdict date: 2026-04-10
- Final program verdict: closed
- Continuation mode: degraded_local_continuation
- Controller note: fresh-child continuation no-progressed in this environment, so the controller completed conservative repo-local continuation and persisted all ledger and matrix truth directly in this thread.
- Rows newly accepted during degraded local continuation: CP-008, DL-001, DL-002, DL-007, DL-010, DL-011, DL-015, DL-016, DL-017, DL-019, DL-020, ED-001, ED-002, ED-006, ED-007, ED-009, ED-010, ED-011, ED-012, ED-013, ED-015, OG-002, OG-004, OG-005, OG-006, OG-007, OG-009, RP-002, RP-003, RP-009, RP-010, RX-004, RX-006, RX-010, SC-001, SC-002, SC-003, SC-004, SC-005, SC-006, SC-007, SC-008, SC-009, SC-010
- Rows with tightened covered evidence during degraded local continuation: none beyond the accepted rows listed above
- Concrete reruns backing the accepted or tightened rows:
  - `flutter test --no-pub integration_test/notification_open_ui_smoke_test.dart -d macos`
  - `flutter test --no-pub test/core/notifications/app_root_notification_open_test.dart`
  - `flutter test --no-pub test/features/push/application/chat_and_group_push_open_flow_test.dart`
  - `flutter test --no-pub test/features/identity/presentation/screens/startup_router_notification_open_test.dart`
  - `flutter test --no-pub test/integration/notification_deeplink_integration_test.dart`
  - `flutter test --no-pub test/integration/notification_tap_smoke_test.dart`
  - `flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart test/features/feed/presentation/screens/feed_screen_test.dart test/core/database/migrations/044_messages_deleted_state_test.dart test/core/database/helpers/messages_db_helpers_test.dart test/features/conversation/domain/repositories/message_repository_impl_test.dart test/core/database/integration/full_migration_chain_test.dart`
  - `flutter test --no-pub test/features/conversation/application/send_chat_message_use_case_test.dart test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart test/features/conversation/presentation/widgets/letter_card_test.dart test/features/feed/presentation/widgets/message_bubble_test.dart`
  - `flutter test --no-pub test/features/conversation/application/reaction_listener_test.dart test/features/conversation/application/chat_message_listener_test.dart test/features/conversation/application/message_deletion_listener_test.dart`
  - `flutter test --no-pub test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
  - `flutter test --no-pub test/features/conversation/application/handle_incoming_reaction_use_case_test.dart`
  - `flutter test --no-pub test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart`
  - `flutter test --no-pub test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart test/features/conversation/application/chat_message_listener_test.dart test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart test/features/conversation/integration/offline_inbox_roundtrip_test.dart test/features/conversation/integration/message_deletion_roundtrip_test.dart`
  - `flutter test --no-pub test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name "incoming reactions refresh the open Orbit conversation and stay correct after reopen"`
  - `flutter test --no-pub test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name "incoming edited messages refresh the open Orbit conversation and stay correct after reopen"`
  - `flutter test --no-pub test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name "incoming deleted tombstones refresh into the Orbit placeholder and stay correct after reopen"`
  - `flutter test --no-pub test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name "copy remains local-only when delete wins during the async clipboard path"`
  - `flutter test --no-pub test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name "deleting the message currently being edited exits edit mode immediately"`
  - `flutter test --no-pub test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart --plain-name "ignores late edits for messages that are already deleted"`
  - `flutter test --no-pub test/features/conversation/application/handle_incoming_reaction_use_case_test.dart --plain-name "ignores add action when the target message is deleted"`
  - `flutter test --no-pub test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart --plain-name "applies an authorized tombstone and cleans up local artifacts"`
  - `flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart --plain-name "delete taps dismiss the overlay before opening one next-frame sheet even under a rapid double tap"`
  - `flutter test --no-pub test/features/conversation/application/send_reaction_use_case_test.dart --plain-name "returns sendFailed and does not persist when direct send and inbox store both fail"`
  - `flutter test --no-pub test/features/conversation/application/remove_reaction_use_case_test.dart --plain-name "returns sendFailed and does not delete locally when direct send and inbox store both fail"`
  - `flutter test --no-pub test/features/conversation/integration/send_then_lock_delivery_test.dart --plain-name "7b. failed send during transport loss survives lock and recovers on resume exactly once"`
  - `flutter test --no-pub test/features/conversation/integration/send_then_lock_delivery_test.dart --plain-name "7bb. failed edit survives lock and recovers on resume with same-id edited state"`
  - `flutter test --no-pub test/features/conversation/integration/send_then_lock_delivery_test.dart --plain-name "7c. failed delete-for-everyone stays visible through pause and hides only after resume delivery"`
  - `flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart test/features/feed/presentation/screens/feed_screen_test.dart`
  - `flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart --plain-name "pending attachments keep reply copy and delete available while edit stays hidden"`
  - `flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart --plain-name "uploading attachments keep reply copy and delete available while edit stays hidden"`
  - `flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart --plain-name "sending keeps reply copy and delete available while edit stays hidden"`
  - `flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart --plain-name "processing keeps reply copy and delete available while edit stays hidden"`
  - `flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart --plain-name "recording keeps reply copy and delete available while edit stays hidden"`
  - `flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart --plain-name "edit action appears for the last sent text row even when a newer incoming row exists"`
  - `flutter test --no-pub test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
  - `flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart --plain-name "rapid repeat long-press keeps a single overlay active"`
  - `flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart --plain-name "delete taps dismiss the overlay before opening one next-frame sheet even under a rapid double tap"`
  - `flutter test --no-pub test/features/feed/presentation/screens/feed_screen_test.dart --plain-name "incoming long-press opens shared overlay and routes reply through feed callback"`
  - `flutter test --no-pub test/features/conversation/presentation/widgets/full_emoji_picker_test.dart --plain-name "fires onSelected on tap"`
  - `flutter test --no-pub test/features/conversation/application/send_reaction_use_case_test.dart --plain-name "persists non-preset emoji payloads from the picker path"`
  - `flutter test --no-pub test/features/conversation/presentation/widgets/reaction_bar_test.dart --plain-name "non-preset currentEmoji does not falsely highlight any preset chip"`
  - `flutter test --no-pub test/features/conversation/presentation/widgets/reaction_display_test.dart --plain-name "renders non-preset emoji chips inline without fallback"`
  - `flutter test --no-pub test/features/conversation/presentation/widgets/reaction_bar_test.dart --plain-name "fires onReactionSelected with correct emoji"`
  - `flutter test --no-pub test/features/conversation/presentation/widgets/letter_card_test.dart --plain-name "fires onReactionTap when chip tapped"`
  - `flutter test --no-pub test/features/feed/presentation/widgets/message_bubble_test.dart --plain-name "onReactionTap fires with emoji when chip tapped"`
  - `flutter test --no-pub test/features/conversation/integration/emoji_reaction_exchange_test.dart --plain-name "Toggle reaction: add then remove"`
  - `flutter test --no-pub test/features/conversation/integration/emoji_reaction_exchange_test.dart --plain-name "Replace reaction: 👍 → ❤️"`
  - `flutter test --no-pub test/features/conversation/integration/quote_reply_thread_test.dart`
  - `flutter test --no-pub test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
  - `flutter test --no-pub test/features/conversation/application/send_chat_message_use_case_test.dart --plain-name "editChatMessage preserves the original row contract"`
  - `flutter test --no-pub test/features/conversation/domain/models/message_payload_test.dart --plain-name "round-trips edit metadata when present"`
  - `flutter test --no-pub test/features/conversation/domain/models/message_payload_test.dart --plain-name "includes edit metadata for edit payloads"`
  - `flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart --plain-name "quoted replies live-resolve updated parent text after the source is edited"`
  - `flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart --plain-name "copy action localizes the snackbar in Arabic while preserving mixed-script clipboard text"`
  - `flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart --plain-name "after restart, conversation screen rebuilds stored reply edit delete and reaction state without stale pre-restart UI"`
  - `flutter test --no-pub test/features/feed/presentation/screens/feed_screen_test.dart --plain-name "after restart, feed direct-thread screen rebuilds stored reply edit delete and reaction state without stale pre-restart UI"`
  - `flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart`
  - `flutter test --no-pub test/features/feed/presentation/screens/feed_screen_test.dart`
  - `flutter test --no-pub test/features/conversation/presentation/widgets/message_context_overlay_test.dart`
  - `flutter test --no-pub test/features/conversation/presentation/widgets/letter_card_test.dart`
  - `flutter test --no-pub test/features/feed/presentation/widgets/message_bubble_test.dart`
- Runnable but unfinished rows (0): none
- Truly blocked rows (0): none
- Blocking truth: none; the shared startup/deep-link first-render prerequisite landed in `integration_test/notification_open_ui_smoke_test.dart` and the four formerly blocked rows now have exact row-owned proof.
- Closure truth: every source row, including the former blocked rows `DL-010`, `DL-020`, `SC-001`, and `SC-009`, is now resolved with exact repo-local evidence, so the truthful final program verdict is `closed`.
