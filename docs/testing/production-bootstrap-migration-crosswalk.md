# Production bootstrap migration crosswalk

Canonical supporting record for [the migration plan](production-bootstrap-migration-plan.md). Executable ownership remains in `tool/testing/selection.json` and `tool/sims/critical_features.json`; this document does not change selection.

## Baseline and preservation

Baseline: `cbb13e8f555516fadaca08a3cb73dec9f9305be2` plus the preserved local candidate. The original local patch and 8,276-file hash inventory are retained in `.codex-test-logs/production-bootstrap-migration-20260927/`. The isolated candidate was created without committing or resetting user changes.

Discovery: 40 top-level harnesses, 75,883 lines, 3,439 total obligations, 9 existing gaps. These are static declarations, not passed tests.

Original tests and harnesses remain unchanged except the exact separately approved DTR-18 fingerprint updates (including the final three reconciled hashes), notification-readiness fix, and Go wrapper candidate-binding fix. No retirement, exclusion, owner switch, redirection, or assertion weakening is approved. Replacement coverage remains pending until scenario receipts certify it.
The active waves candidate passed a 2,363-file original-preservation audit and an exact selector/command audit (`waves-original-preservation-audit-001.json` and `waves-selector-preservation-audit-001.json`). The user separately approved the exact original Go wrapper candidate-path and pipeline-exit repair (`approved-go-wrapper-candidate-binding.json`). It is integrated in the main worktree; prior candidate evidence remains bound to its recorded source. An additive completion adapter and owner now account for this retained wrapper; inventory discovery reports eight remaining coverage gaps (`next-full-inventory-001/plan.json`). The actual retained wrapper and its four causal adapter tests pass in `go-wrapper-execution-001/results.json`; the wrapper still runs the exact original Send selection and tail output. This diagnostic subset is not a full-suite pass. The expanded next-candidate preservation audit verifies 2,393 original files with only the three exact approved file exceptions (`next-original-preservation-audit-002.json`).

## Harness dispositions

Source anchors below bind the assertions to the original bytes, including existing local edits. Scenario/variant details and owner bindings are retained verbatim from discovery. External criteria and shared helpers remain additional obligations; an assertion-site list alone is not equivalence evidence.

### `apns_provider_probe_harness.dart`

- Boundary / wave: **provider proof / retain**. Retain provider capture; external provider/lifecycle driver remains required.
- Preserved source SHA-256: `068e5356cf8ceac0ba1d2ea6d8ed24b85d29b60bea4028aebcacc44f4473d161`.
- Original source: [`integration_test/apns_provider_probe_harness.dart`](../../integration_test/apns_provider_probe_harness.dart); unchanged, retirement not approved.
- Build/graph: provider-configured support application; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `8a901e37a4227f8935e4f51c` MANUAL; owner=none; selector=``; variant=``; reason=Provider capture support app waits ten minutes for externally driven provider sends and foreground/background/terminated probes (source comments and ready_for_provider_send marker); its token readiness check alone does not prove delivery. No automated provider-send/lifecycle driver owns this capture recipe.
- Direct importers: Entry point or externally selected source.
- Assertion sites: [81](../../integration_test/apns_provider_probe_harness.dart#L81)
- Replacement evidence: pending; original evidence and execution owner retained.

### `benchmark_1_1_send_harness.dart`

- Boundary / wave: **component evidence plus application measurement / 4**. Retain existing measured interval and thresholds; add separately named production startup/resume/routing/latency evidence where claimed.
- Preserved source SHA-256: `2966804def2f67bd5926a26636ee12fc0db8e6faeb53946f37e319255ef57351`.
- Original source: [`integration_test/benchmark_1_1_send_harness.dart`](../../integration_test/benchmark_1_1_send_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `b1ddad01e228c60b089ea43f` EXCLUDED; owner=none; selector=``; variant=``; reason=helper
- Direct importers: [`integration_test/benchmark_harness.dart`](../../integration_test/benchmark_harness.dart)
- Assertion sites: No direct expect/assert/fail; delegated to child/protocol criteria.
- Replacement evidence: pending; original evidence and execution owner retained.

### `benchmark_ack_harness.dart`

- Boundary / wave: **component benchmark / 4**. Retain focused component setup and existing thresholds; it does not certify application startup or end-user latency.
- Preserved source SHA-256: `b2f5256d252bff4675fdf221c4312211003d6550d514b589cd54cbb7d535f7b2`.
- Original source: [`integration_test/benchmark_ack_harness.dart`](../../integration_test/benchmark_ack_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `ae28734ed7db411db06d604c` EXCLUDED; owner=none; selector=``; variant=``; reason=helper
- Direct importers: [`integration_test/benchmark_harness.dart`](../../integration_test/benchmark_harness.dart)
- Assertion sites: [79](../../integration_test/benchmark_ack_harness.dart#L79)
- Replacement evidence: pending; original evidence and execution owner retained.

### `benchmark_background_resume_harness.dart`

- Boundary / wave: **component evidence plus application measurement / 4**. Retain existing measured interval and thresholds; add separately named production startup/resume/routing/latency evidence where claimed.
- Preserved source SHA-256: `c4e7cb38d48220510af2d08ab0650b09f3533457083faad261e242023bf920b9`.
- Original source: [`integration_test/benchmark_background_resume_harness.dart`](../../integration_test/benchmark_background_resume_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `cfaaa602e86e22da3e6d9695` EXCLUDED; owner=none; selector=``; variant=``; reason=helper
- Direct importers: [`integration_test/benchmark_harness.dart`](../../integration_test/benchmark_harness.dart)
- Assertion sites: [29](../../integration_test/benchmark_background_resume_harness.dart#L29), [46](../../integration_test/benchmark_background_resume_harness.dart#L46), [170](../../integration_test/benchmark_background_resume_harness.dart#L170), [184](../../integration_test/benchmark_background_resume_harness.dart#L184), [212](../../integration_test/benchmark_background_resume_harness.dart#L212), [227](../../integration_test/benchmark_background_resume_harness.dart#L227), [267](../../integration_test/benchmark_background_resume_harness.dart#L267), [369](../../integration_test/benchmark_background_resume_harness.dart#L369), [426](../../integration_test/benchmark_background_resume_harness.dart#L426)
- Replacement evidence: pending; original evidence and execution owner retained.

### `benchmark_bridge_crossing_harness.dart`

- Boundary / wave: **component benchmark / 4**. Retain focused component setup and existing thresholds; it does not certify application startup or end-user latency.
- Preserved source SHA-256: `4790629563993688e509b876966fd57006398f2ab20396206a6591cf6c3d3499`.
- Original source: [`integration_test/benchmark_bridge_crossing_harness.dart`](../../integration_test/benchmark_bridge_crossing_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `6fed1c40b0ac1892a1acb94e` EXCLUDED; owner=none; selector=``; variant=``; reason=helper
- Direct importers: [`integration_test/benchmark_harness.dart`](../../integration_test/benchmark_harness.dart)
- Assertion sites: [77](../../integration_test/benchmark_bridge_crossing_harness.dart#L77)
- Replacement evidence: pending; original evidence and execution owner retained.

### `benchmark_connection_reuse_harness.dart`

- Boundary / wave: **component benchmark / 4**. Retain focused component setup and existing thresholds; it does not certify application startup or end-user latency.
- Preserved source SHA-256: `7f6eccc747fe87e4d66b26fb2da32c849db2c4e29a0e2b9d2c7aefebc5c4f7cf`.
- Original source: [`integration_test/benchmark_connection_reuse_harness.dart`](../../integration_test/benchmark_connection_reuse_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `82313e99fa0689796c19c9f4` EXCLUDED; owner=none; selector=``; variant=``; reason=helper
- Direct importers: [`integration_test/benchmark_harness.dart`](../../integration_test/benchmark_harness.dart)
- Assertion sites: No direct expect/assert/fail; delegated to child/protocol criteria.
- Replacement evidence: pending; original evidence and execution owner retained.

### `benchmark_encryption_harness.dart`

- Boundary / wave: **component benchmark / 4**. Retain focused component setup and existing thresholds; it does not certify application startup or end-user latency.
- Preserved source SHA-256: `a44ec2ce7a876ed4404011635657369b2f915b71f418ff5ae1abf30fa79ec86e`.
- Original source: [`integration_test/benchmark_encryption_harness.dart`](../../integration_test/benchmark_encryption_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `b06e7ba9232892e06e7f6317` EXCLUDED; owner=none; selector=``; variant=``; reason=helper
- Direct importers: [`integration_test/benchmark_harness.dart`](../../integration_test/benchmark_harness.dart)
- Assertion sites: [42](../../integration_test/benchmark_encryption_harness.dart#L42), [71](../../integration_test/benchmark_encryption_harness.dart#L71), [95](../../integration_test/benchmark_encryption_harness.dart#L95), [112](../../integration_test/benchmark_encryption_harness.dart#L112), [146](../../integration_test/benchmark_encryption_harness.dart#L146), [163](../../integration_test/benchmark_encryption_harness.dart#L163)
- Replacement evidence: pending; original evidence and execution owner retained.

### `benchmark_event_queue_harness.dart`

- Boundary / wave: **component benchmark / 4**. Retain focused component setup and existing thresholds; it does not certify application startup or end-user latency.
- Preserved source SHA-256: `90f898c1cd33362ed21c18927aaebc35f08c6ec90cccc1abad2428f01ebf27ad`.
- Original source: [`integration_test/benchmark_event_queue_harness.dart`](../../integration_test/benchmark_event_queue_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `63cef0c53b7c42fc051be01f` EXCLUDED; owner=none; selector=``; variant=``; reason=helper
- Direct importers: [`integration_test/benchmark_harness.dart`](../../integration_test/benchmark_harness.dart)
- Assertion sites: [67](../../integration_test/benchmark_event_queue_harness.dart#L67)
- Replacement evidence: pending; original evidence and execution owner retained.

### `benchmark_group_publish_harness.dart`

- Boundary / wave: **component evidence plus application measurement / 4**. Retain existing measured interval and thresholds; add separately named production startup/resume/routing/latency evidence where claimed.
- Preserved source SHA-256: `8ce9f42cda34c2a52fdd5f141f30706e90a64dd3d59ee5402f5727e9b4251ac7`.
- Original source: [`integration_test/benchmark_group_publish_harness.dart`](../../integration_test/benchmark_group_publish_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; construction anchors: `setupGroupMultiDeviceStack`
- Discovered owners/selectors: `dbe1cb6d97011a70bfda05ea` EXCLUDED; owner=none; selector=``; variant=``; reason=helper
- Direct importers: [`integration_test/benchmark_harness.dart`](../../integration_test/benchmark_harness.dart)
- Assertion sites: [107](../../integration_test/benchmark_group_publish_harness.dart#L107), [123](../../integration_test/benchmark_group_publish_harness.dart#L123), [124](../../integration_test/benchmark_group_publish_harness.dart#L124), [160](../../integration_test/benchmark_group_publish_harness.dart#L160), [175](../../integration_test/benchmark_group_publish_harness.dart#L175)
- Replacement evidence: pending; original evidence and execution owner retained.

### `benchmark_harness.dart`

- Boundary / wave: **dispatcher / 4**. Retain benchmark selection and isolated child intervals.
- Preserved source SHA-256: `8a42dcf6351f1732945aa45bc800c0ec246746fa93ec5dd2ea956d73ecc39b33`.
- Original source: [`integration_test/benchmark_harness.dart`](../../integration_test/benchmark_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `2e0e66174fd29c17335dd670` SELECTED; owner=full-legacy; selector=``; variant=``; `a4953b13e8a14bd42159caf6` SELECTED; owner=full-legacy; selector=`ACK`; variant=`compile:BENCHMARK`; reason=Exact adapter scenario selection; `59b482a3621a992a3e03f73a` SELECTED; owner=full-legacy; selector=`BACKGROUND_RESUME`; variant=`compile:BENCHMARK`; reason=Exact adapter scenario selection; `3002816e084c981cee4289fa` SELECTED; owner=full-legacy; selector=`BRIDGE_CROSSING`; variant=`compile:BENCHMARK`; reason=Exact adapter scenario selection; `cca929b1febb973bdbf26f82` SELECTED; owner=full-legacy; selector=`CONNECTION_REUSE`; variant=`compile:BENCHMARK`; reason=Exact adapter scenario selection; `ceef9bf85d5d75a9658c4e0b` SELECTED; owner=full-legacy; selector=`ENCRYPTION`; variant=`compile:BENCHMARK`; reason=Exact adapter scenario selection; `8dec18b0e8550b27ecdcc31e` SELECTED; owner=full-legacy; selector=`EVENT_QUEUE`; variant=`compile:BENCHMARK`; reason=Exact adapter scenario selection; `406fb6808646e9cbdb3aeea3` SELECTED; owner=full-legacy; selector=`GROUP_PUBLISH`; variant=`compile:BENCHMARK`; reason=Exact adapter scenario selection; `b08560626449b84dbd661b5e` SELECTED; owner=full-legacy; selector=`INBOX`; variant=`compile:BENCHMARK`; reason=Exact adapter scenario selection; `faf0ea7bcc84c2165ebc12b9` SELECTED; owner=full-legacy; selector=`MEDIA`; variant=`compile:BENCHMARK`; reason=Exact adapter scenario selection; `e83fd20ec94070893d76fe79` SELECTED; owner=full-legacy; selector=`NODE_STARTUP`; variant=`compile:BENCHMARK`; reason=Exact adapter scenario selection; `bc8e757e024f87bd6af65903` SELECTED; owner=full-legacy; selector=`NOTIFICATION_TAP`; variant=`compile:BENCHMARK`; reason=Exact adapter scenario selection; `b955937acc5ad93a440fe705` SELECTED; owner=full-legacy; selector=`ONE_TO_ONE_SEND`; variant=`compile:BENCHMARK`; reason=Exact adapter scenario selection; `08f86bf9f82a447c0179dc02` SELECTED; owner=full-legacy; selector=`RELAY_RECOVERY`; variant=`compile:BENCHMARK`; reason=Exact adapter scenario selection; `efe03ccd5868e3e0f2949473` SELECTED; owner=full-legacy; selector=`ROUTING_PATHS`; variant=`compile:BENCHMARK`; reason=Exact adapter scenario selection; `06716d9136a14088c93ca2f8` SELECTED; owner=full-legacy; selector=`TIMEOUT_ACCURACY`; variant=`compile:BENCHMARK`; reason=Exact adapter scenario selection; `0f26e342850e562497e78d78` SELECTED; owner=full-legacy; selector=`TIME_TO_ONLINE`; variant=`compile:BENCHMARK`; reason=Exact adapter scenario selection; `e07505df82ed27ad483fb7bc` SELECTED; owner=full-legacy; selector=`VOICE`; variant=`compile:BENCHMARK`; reason=Exact adapter scenario selection
- Direct importers: Entry point or externally selected source.
- Assertion sites: [87](../../integration_test/benchmark_harness.dart#L87)
- Replacement evidence: pending; original evidence and execution owner retained.

### `benchmark_inbox_harness.dart`

- Boundary / wave: **component benchmark / 4**. Retain focused component setup and existing thresholds; it does not certify application startup or end-user latency.
- Preserved source SHA-256: `816d8d92e02b87670ea78ac2d7da2ab0e848c01226d4b1a4d2d315ec5a88a840`.
- Original source: [`integration_test/benchmark_inbox_harness.dart`](../../integration_test/benchmark_inbox_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `63e6a902d978858fb3c2ecdb` EXCLUDED; owner=none; selector=``; variant=``; reason=helper
- Direct importers: [`integration_test/benchmark_harness.dart`](../../integration_test/benchmark_harness.dart)
- Assertion sites: No direct expect/assert/fail; delegated to child/protocol criteria.
- Replacement evidence: pending; original evidence and execution owner retained.

### `benchmark_media_harness.dart`

- Boundary / wave: **component benchmark / 4**. Retain focused component setup and existing thresholds; it does not certify application startup or end-user latency.
- Preserved source SHA-256: `20e46762a43f72251047a44f2f801ac881070442166e29979ab6574b7e882999`.
- Original source: [`integration_test/benchmark_media_harness.dart`](../../integration_test/benchmark_media_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `d3c97950fb4e8e8248aabcd4` EXCLUDED; owner=none; selector=``; variant=``; reason=helper
- Direct importers: [`integration_test/benchmark_harness.dart`](../../integration_test/benchmark_harness.dart)
- Assertion sites: [121](../../integration_test/benchmark_media_harness.dart#L121), [124](../../integration_test/benchmark_media_harness.dart#L124), [127](../../integration_test/benchmark_media_harness.dart#L127), [136](../../integration_test/benchmark_media_harness.dart#L136), [155](../../integration_test/benchmark_media_harness.dart#L155), [235](../../integration_test/benchmark_media_harness.dart#L235), [238](../../integration_test/benchmark_media_harness.dart#L238), [241](../../integration_test/benchmark_media_harness.dart#L241), [250](../../integration_test/benchmark_media_harness.dart#L250), [268](../../integration_test/benchmark_media_harness.dart#L268)
- Replacement evidence: pending; original evidence and execution owner retained.

### `benchmark_node_startup_harness.dart`

- Boundary / wave: **component benchmark / 4**. Retain focused component setup and existing thresholds; it does not certify application startup or end-user latency.
- Preserved source SHA-256: `42c07e98d62f25a6c2771f582e47d7624b247a34f43f028d1056f970d90d6b59`.
- Original source: [`integration_test/benchmark_node_startup_harness.dart`](../../integration_test/benchmark_node_startup_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `ebf68dd8459e7af9abec1cfe` EXCLUDED; owner=none; selector=``; variant=``; reason=helper
- Direct importers: [`integration_test/benchmark_harness.dart`](../../integration_test/benchmark_harness.dart)
- Assertion sites: [33](../../integration_test/benchmark_node_startup_harness.dart#L33), [48](../../integration_test/benchmark_node_startup_harness.dart#L48), [78](../../integration_test/benchmark_node_startup_harness.dart#L78)
- Replacement evidence: pending; original evidence and execution owner retained.

### `benchmark_notification_tap_harness.dart`

- Boundary / wave: **component evidence plus application measurement / 4**. Retain existing measured interval and thresholds; add separately named production startup/resume/routing/latency evidence where claimed.
- Preserved source SHA-256: `5bae0910f9a1a24ce5fba7423ea1d4504204dae2c242f6e87d2a59757cd8f9bc`.
- Original source: [`integration_test/benchmark_notification_tap_harness.dart`](../../integration_test/benchmark_notification_tap_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `3bb2496346561a31bd7aa819` EXCLUDED; owner=none; selector=``; variant=``; reason=helper
- Direct importers: [`integration_test/benchmark_harness.dart`](../../integration_test/benchmark_harness.dart)
- Assertion sites: [249](../../integration_test/benchmark_notification_tap_harness.dart#L249), [279](../../integration_test/benchmark_notification_tap_harness.dart#L279), [317](../../integration_test/benchmark_notification_tap_harness.dart#L317)
- Replacement evidence: pending; original evidence and execution owner retained.

### `benchmark_relay_recovery_harness.dart`

- Boundary / wave: **component evidence plus application measurement / 4**. Retain existing measured interval and thresholds; add separately named production startup/resume/routing/latency evidence where claimed.
- Preserved source SHA-256: `890cad684e7254be0dfed0e2182fee8473f714132a405f34f4580c53ea0ce212`.
- Original source: [`integration_test/benchmark_relay_recovery_harness.dart`](../../integration_test/benchmark_relay_recovery_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `53722303fdc9937cdb3f93d5` EXCLUDED; owner=none; selector=``; variant=``; reason=helper
- Direct importers: [`integration_test/benchmark_harness.dart`](../../integration_test/benchmark_harness.dart)
- Assertion sites: [24](../../integration_test/benchmark_relay_recovery_harness.dart#L24), [124](../../integration_test/benchmark_relay_recovery_harness.dart#L124), [276](../../integration_test/benchmark_relay_recovery_harness.dart#L276)
- Replacement evidence: pending; original evidence and execution owner retained.

### `benchmark_routing_paths_harness.dart`

- Boundary / wave: **component evidence plus application measurement / 4**. Retain existing measured interval and thresholds; add separately named production startup/resume/routing/latency evidence where claimed.
- Preserved source SHA-256: `0dcd413808d070d859f579910f5701bd7ae4191a5b16d745c809f55b4e723383`.
- Original source: [`integration_test/benchmark_routing_paths_harness.dart`](../../integration_test/benchmark_routing_paths_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `d9ae35981f409a88111d4b92` EXCLUDED; owner=none; selector=``; variant=``; reason=helper
- Direct importers: [`integration_test/benchmark_harness.dart`](../../integration_test/benchmark_harness.dart)
- Assertion sites: [200](../../integration_test/benchmark_routing_paths_harness.dart#L200)
- Replacement evidence: pending; original evidence and execution owner retained.

### `benchmark_time_to_online_harness.dart`

- Boundary / wave: **component evidence plus application measurement / 4**. Retain existing measured interval and thresholds; add separately named production startup/resume/routing/latency evidence where claimed.
- Preserved source SHA-256: `ef013f202a6ce7fcc2e339629d820af9a4e0b64e990f6220357a29242619ec80`.
- Original source: [`integration_test/benchmark_time_to_online_harness.dart`](../../integration_test/benchmark_time_to_online_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `d08774dcae41dc9c5ceb705d` EXCLUDED; owner=none; selector=``; variant=``; reason=helper
- Direct importers: [`integration_test/benchmark_harness.dart`](../../integration_test/benchmark_harness.dart)
- Assertion sites: [23](../../integration_test/benchmark_time_to_online_harness.dart#L23), [154](../../integration_test/benchmark_time_to_online_harness.dart#L154)
- Replacement evidence: pending; original evidence and execution owner retained.

### `benchmark_timeout_accuracy_harness.dart`

- Boundary / wave: **component benchmark / 4**. Retain focused component setup and existing thresholds; it does not certify application startup or end-user latency.
- Preserved source SHA-256: `79a06446e62866d4e67950edf88ab1cab5d34174f7f0c8d5220fd6fab5dc2ecd`.
- Original source: [`integration_test/benchmark_timeout_accuracy_harness.dart`](../../integration_test/benchmark_timeout_accuracy_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `c95aeb171981ca8e2d700e96` EXCLUDED; owner=none; selector=``; variant=``; reason=helper
- Direct importers: [`integration_test/benchmark_harness.dart`](../../integration_test/benchmark_harness.dart)
- Assertion sites: [100](../../integration_test/benchmark_timeout_accuracy_harness.dart#L100), [118](../../integration_test/benchmark_timeout_accuracy_harness.dart#L118), [170](../../integration_test/benchmark_timeout_accuracy_harness.dart#L170), [233](../../integration_test/benchmark_timeout_accuracy_harness.dart#L233), [238](../../integration_test/benchmark_timeout_accuracy_harness.dart#L238)
- Replacement evidence: pending; original evidence and execution owner retained.

### `benchmark_voice_harness.dart`

- Boundary / wave: **component benchmark / 4**. Retain focused component setup and existing thresholds; it does not certify application startup or end-user latency.
- Preserved source SHA-256: `3d0d1b29d6f8a73f9a6fe914cf17462746d76670d6b1bfa44a2534e9ca68488c`.
- Original source: [`integration_test/benchmark_voice_harness.dart`](../../integration_test/benchmark_voice_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `adaf91cb2867f6044bb59ff1` EXCLUDED; owner=none; selector=``; variant=``; reason=helper
- Direct importers: [`integration_test/benchmark_harness.dart`](../../integration_test/benchmark_harness.dart)
- Assertion sites: No direct expect/assert/fail; delegated to child/protocol criteria.
- Replacement evidence: pending; original evidence and execution owner retained.

### `conversation_wired_performance_harness.dart`

- Boundary / wave: **component evidence plus application measurement / 4**. Retain existing measured interval and thresholds; add separately named production startup/resume/routing/latency evidence where claimed.
- Preserved source SHA-256: `b827ac8dc61542653c1be01d2b018a03952923ed6b57121c75a400ea4e5c6afc`.
- Original source: [`integration_test/conversation_wired_performance_harness.dart`](../../integration_test/conversation_wired_performance_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `f00704544e5d22006d09d2d9` EXCLUDED; owner=none; selector=``; variant=``; reason=helper
- Direct importers: [`integration_test/performance_harness.dart`](../../integration_test/performance_harness.dart)
- Assertion sites: [855](../../integration_test/conversation_wired_performance_harness.dart#L855), [894](../../integration_test/conversation_wired_performance_harness.dart#L894), [921](../../integration_test/conversation_wired_performance_harness.dart#L921), [922](../../integration_test/conversation_wired_performance_harness.dart#L922), [941](../../integration_test/conversation_wired_performance_harness.dart#L941), [951](../../integration_test/conversation_wired_performance_harness.dart#L951), [984](../../integration_test/conversation_wired_performance_harness.dart#L984), [998](../../integration_test/conversation_wired_performance_harness.dart#L998), [1091](../../integration_test/conversation_wired_performance_harness.dart#L1091)
- Replacement evidence: pending; original evidence and execution owner retained.

### `conversation_wired_subscription_performance_harness.dart`

- Boundary / wave: **component evidence plus application measurement / 4**. Retain existing measured interval and thresholds; add separately named production startup/resume/routing/latency evidence where claimed.
- Preserved source SHA-256: `7746927d3588770066f9bee30512a92944dfc072861951697283d428fe2b40e9`.
- Original source: [`integration_test/conversation_wired_subscription_performance_harness.dart`](../../integration_test/conversation_wired_subscription_performance_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `7c36167b0f2ae8282f1b6e0f` EXCLUDED; owner=none; selector=``; variant=``; reason=helper
- Direct importers: [`integration_test/performance_harness.dart`](../../integration_test/performance_harness.dart)
- Assertion sites: [456](../../integration_test/conversation_wired_subscription_performance_harness.dart#L456), [553](../../integration_test/conversation_wired_subscription_performance_harness.dart#L553), [554](../../integration_test/conversation_wired_subscription_performance_harness.dart#L554), [555](../../integration_test/conversation_wired_subscription_performance_harness.dart#L555), [562](../../integration_test/conversation_wired_subscription_performance_harness.dart#L562), [575](../../integration_test/conversation_wired_subscription_performance_harness.dart#L575), [625](../../integration_test/conversation_wired_subscription_performance_harness.dart#L625), [655](../../integration_test/conversation_wired_subscription_performance_harness.dart#L655), [812](../../integration_test/conversation_wired_subscription_performance_harness.dart#L812)
- Replacement evidence: pending; original evidence and execution owner retained.

### `diagnostics_reconnect_isolation_harness.dart`

- Boundary / wave: **component evidence plus application measurement / 4**. Retain existing measured interval and thresholds; add separately named production startup/resume/routing/latency evidence where claimed.
- Preserved source SHA-256: `821a6b5f29599819052d7fc90435acc93f4f5bc7ad44531d6f12aa4932ca688c`.
- Original source: [`integration_test/diagnostics_reconnect_isolation_harness.dart`](../../integration_test/diagnostics_reconnect_isolation_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `eb2466780ea39b1f4976b519` EXCLUDED; owner=none; selector=``; variant=``; reason=Android/iOS diagnostic archive and reconnect fault-injection comparison; controlled native replies and relay transport
- Direct importers: Entry point or externally selected source.
- Assertion sites: [86](../../integration_test/diagnostics_reconnect_isolation_harness.dart#L86), [87](../../integration_test/diagnostics_reconnect_isolation_harness.dart#L87), [107](../../integration_test/diagnostics_reconnect_isolation_harness.dart#L107), [137](../../integration_test/diagnostics_reconnect_isolation_harness.dart#L137), [144](../../integration_test/diagnostics_reconnect_isolation_harness.dart#L144), [145](../../integration_test/diagnostics_reconnect_isolation_harness.dart#L145), [152](../../integration_test/diagnostics_reconnect_isolation_harness.dart#L152), [153](../../integration_test/diagnostics_reconnect_isolation_harness.dart#L153), [154](../../integration_test/diagnostics_reconnect_isolation_harness.dart#L154), [160](../../integration_test/diagnostics_reconnect_isolation_harness.dart#L160), [165](../../integration_test/diagnostics_reconnect_isolation_harness.dart#L165), [166](../../integration_test/diagnostics_reconnect_isolation_harness.dart#L166), [167](../../integration_test/diagnostics_reconnect_isolation_harness.dart#L167), [169](../../integration_test/diagnostics_reconnect_isolation_harness.dart#L169), [171](../../integration_test/diagnostics_reconnect_isolation_harness.dart#L171), [176](../../integration_test/diagnostics_reconnect_isolation_harness.dart#L176)
- Replacement evidence: pending; original evidence and execution owner retained.

### `direct_private_media_device_local_journey_harness.dart`

- Boundary / wave: **application journey / 2**. Add production routing/lifecycle/notification/media owner with the same cold/warm and privacy boundaries.
- Preserved source SHA-256: `e93e271ec469dff7dcb78f97de7c75cf577ccf6df1e583af2bfe2c78dcb3887e`.
- Original source: [`integration_test/direct_private_media_device_local_journey_harness.dart`](../../integration_test/direct_private_media_device_local_journey_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `6dc51ac7e1fb9418529e5108` EXCLUDED; owner=none; selector=``; variant=``; reason=234 deterministic device-local private-media proof support
- Direct importers: Entry point or externally selected source.
- Assertion sites: [81](../../integration_test/direct_private_media_device_local_journey_harness.dart#L81), [82](../../integration_test/direct_private_media_device_local_journey_harness.dart#L82), [186](../../integration_test/direct_private_media_device_local_journey_harness.dart#L186), [292](../../integration_test/direct_private_media_device_local_journey_harness.dart#L292), [293](../../integration_test/direct_private_media_device_local_journey_harness.dart#L293), [333](../../integration_test/direct_private_media_device_local_journey_harness.dart#L333), [334](../../integration_test/direct_private_media_device_local_journey_harness.dart#L334), [335](../../integration_test/direct_private_media_device_local_journey_harness.dart#L335), [336](../../integration_test/direct_private_media_device_local_journey_harness.dart#L336), [337](../../integration_test/direct_private_media_device_local_journey_harness.dart#L337), [345](../../integration_test/direct_private_media_device_local_journey_harness.dart#L345), [346](../../integration_test/direct_private_media_device_local_journey_harness.dart#L346), [361](../../integration_test/direct_private_media_device_local_journey_harness.dart#L361), [362](../../integration_test/direct_private_media_device_local_journey_harness.dart#L362), [363](../../integration_test/direct_private_media_device_local_journey_harness.dart#L363), [407](../../integration_test/direct_private_media_device_local_journey_harness.dart#L407), [409](../../integration_test/direct_private_media_device_local_journey_harness.dart#L409), [410](../../integration_test/direct_private_media_device_local_journey_harness.dart#L410), [419](../../integration_test/direct_private_media_device_local_journey_harness.dart#L419), [420](../../integration_test/direct_private_media_device_local_journey_harness.dart#L420), [429](../../integration_test/direct_private_media_device_local_journey_harness.dart#L429), [438](../../integration_test/direct_private_media_device_local_journey_harness.dart#L438), [439](../../integration_test/direct_private_media_device_local_journey_harness.dart#L439), [442](../../integration_test/direct_private_media_device_local_journey_harness.dart#L442), [443](../../integration_test/direct_private_media_device_local_journey_harness.dart#L443), [444](../../integration_test/direct_private_media_device_local_journey_harness.dart#L444), [445](../../integration_test/direct_private_media_device_local_journey_harness.dart#L445), [446](../../integration_test/direct_private_media_device_local_journey_harness.dart#L446), [447](../../integration_test/direct_private_media_device_local_journey_harness.dart#L447), [448](../../integration_test/direct_private_media_device_local_journey_harness.dart#L448), [449](../../integration_test/direct_private_media_device_local_journey_harness.dart#L449), [450](../../integration_test/direct_private_media_device_local_journey_harness.dart#L450), [451](../../integration_test/direct_private_media_device_local_journey_harness.dart#L451), [509](../../integration_test/direct_private_media_device_local_journey_harness.dart#L509), [510](../../integration_test/direct_private_media_device_local_journey_harness.dart#L510), [511](../../integration_test/direct_private_media_device_local_journey_harness.dart#L511), [512](../../integration_test/direct_private_media_device_local_journey_harness.dart#L512), [516](../../integration_test/direct_private_media_device_local_journey_harness.dart#L516), [517](../../integration_test/direct_private_media_device_local_journey_harness.dart#L517), [566](../../integration_test/direct_private_media_device_local_journey_harness.dart#L566), [581](../../integration_test/direct_private_media_device_local_journey_harness.dart#L581), [589](../../integration_test/direct_private_media_device_local_journey_harness.dart#L589), [639](../../integration_test/direct_private_media_device_local_journey_harness.dart#L639), [655](../../integration_test/direct_private_media_device_local_journey_harness.dart#L655), [668](../../integration_test/direct_private_media_device_local_journey_harness.dart#L668), [670](../../integration_test/direct_private_media_device_local_journey_harness.dart#L670), [686](../../integration_test/direct_private_media_device_local_journey_harness.dart#L686), [870](../../integration_test/direct_private_media_device_local_journey_harness.dart#L870), [871](../../integration_test/direct_private_media_device_local_journey_harness.dart#L871), [899](../../integration_test/direct_private_media_device_local_journey_harness.dart#L899), [900](../../integration_test/direct_private_media_device_local_journey_harness.dart#L900), [912](../../integration_test/direct_private_media_device_local_journey_harness.dart#L912), [921](../../integration_test/direct_private_media_device_local_journey_harness.dart#L921), [922](../../integration_test/direct_private_media_device_local_journey_harness.dart#L922), [923](../../integration_test/direct_private_media_device_local_journey_harness.dart#L923), [928](../../integration_test/direct_private_media_device_local_journey_harness.dart#L928), [943](../../integration_test/direct_private_media_device_local_journey_harness.dart#L943), [944](../../integration_test/direct_private_media_device_local_journey_harness.dart#L944), [952](../../integration_test/direct_private_media_device_local_journey_harness.dart#L952), [955](../../integration_test/direct_private_media_device_local_journey_harness.dart#L955), [956](../../integration_test/direct_private_media_device_local_journey_harness.dart#L956), [957](../../integration_test/direct_private_media_device_local_journey_harness.dart#L957), [1029](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1029), [1051](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1051), [1169](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1169), [1183](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1183), [1208](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1208), [1295](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1295), [1297](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1297), [1299](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1299), [1301](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1301), [1395](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1395), [1396](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1396), [1397](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1397), [1398](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1398), [1399](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1399), [1400](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1400), [1402](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1402), [1403](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1403), [1404](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1404), [1405](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1405), [1407](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1407), [1409](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1409), [1411](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1411), [1412](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1412), [1413](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1413), [1418](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1418), [1419](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1419), [1423](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1423), [1424](../../integration_test/direct_private_media_device_local_journey_harness.dart#L1424)
- Replacement evidence: pending; original evidence and execution owner retained.

### `feed_wired_init_performance_harness.dart`

- Boundary / wave: **component evidence plus application measurement / 4**. Retain existing measured interval and thresholds; add separately named production startup/resume/routing/latency evidence where claimed.
- Preserved source SHA-256: `67e9fa02b0d8552ce38ef5d4b99e81e6c1708a871130aae583bee60b5040b2a7`.
- Original source: [`integration_test/feed_wired_init_performance_harness.dart`](../../integration_test/feed_wired_init_performance_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; construction anchors: `IdentityRepositoryImpl`
- Discovered owners/selectors: `1b66878e5d2459c0b47aa12c` EXCLUDED; owner=none; selector=``; variant=``; reason=helper
- Direct importers: [`integration_test/performance_harness.dart`](../../integration_test/performance_harness.dart)
- Assertion sites: [367](../../integration_test/feed_wired_init_performance_harness.dart#L367), [753](../../integration_test/feed_wired_init_performance_harness.dart#L753), [813](../../integration_test/feed_wired_init_performance_harness.dart#L813), [868](../../integration_test/feed_wired_init_performance_harness.dart#L868), [869](../../integration_test/feed_wired_init_performance_harness.dart#L869), [874](../../integration_test/feed_wired_init_performance_harness.dart#L874)
- Replacement evidence: pending; original evidence and execution owner retained.

### `foreground_group_push_simulator_harness.dart`

- Boundary / wave: **application journey / 1**. Add production foreground push owner: S1 exact missed-message recovery/payload, S2 live/push dedupe, S3 failed-drain eligibility suppression.
- Preserved source SHA-256: `69e9be5aadf36c8d3666a724b679794de836c0dc6b3cb939cff551477e26949b`.
- Original source: [`integration_test/foreground_group_push_simulator_harness.dart`](../../integration_test/foreground_group_push_simulator_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; construction anchors: `FakeNotificationService`, `GroupMessageListener`, `setupGroupMultiDeviceStack`
- Discovered owners/selectors: `92fb549cd5d4efb953cfa5b5` EXCLUDED; owner=none; selector=``; variant=``; reason=group simulator harness
- Direct importers: Entry point or externally selected source.
- Assertion sites: [151](../../integration_test/foreground_group_push_simulator_harness.dart#L151), [152](../../integration_test/foreground_group_push_simulator_harness.dart#L152), [189](../../integration_test/foreground_group_push_simulator_harness.dart#L189), [369](../../integration_test/foreground_group_push_simulator_harness.dart#L369), [381](../../integration_test/foreground_group_push_simulator_harness.dart#L381), [382](../../integration_test/foreground_group_push_simulator_harness.dart#L382), [383](../../integration_test/foreground_group_push_simulator_harness.dart#L383), [384](../../integration_test/foreground_group_push_simulator_harness.dart#L384), [409](../../integration_test/foreground_group_push_simulator_harness.dart#L409), [410](../../integration_test/foreground_group_push_simulator_harness.dart#L410), [427](../../integration_test/foreground_group_push_simulator_harness.dart#L427), [428](../../integration_test/foreground_group_push_simulator_harness.dart#L428), [437](../../integration_test/foreground_group_push_simulator_harness.dart#L437), [438](../../integration_test/foreground_group_push_simulator_harness.dart#L438), [439](../../integration_test/foreground_group_push_simulator_harness.dart#L439), [508](../../integration_test/foreground_group_push_simulator_harness.dart#L508), [512](../../integration_test/foreground_group_push_simulator_harness.dart#L512), [513](../../integration_test/foreground_group_push_simulator_harness.dart#L513), [514](../../integration_test/foreground_group_push_simulator_harness.dart#L514)
- Replacement evidence: pending; original evidence and execution owner retained.

### `group_invite_status_matrix_harness.dart`

- Boundary / wave: **application journey / shared setup / 3**. Add production-created group service consumers; preserve every role, intermediate assertion, and catalog receipt.
- Preserved source SHA-256: `f400c57acd6ede184e765058da3c06ca922d8976939b341b2618aa22ccd88de4`.
- Original source: [`integration_test/group_invite_status_matrix_harness.dart`](../../integration_test/group_invite_status_matrix_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `42613fd92ce4356ab904344a` EXCLUDED; owner=none; selector=``; variant=``; reason=group simulator harness
- Direct importers: Entry point or externally selected source.
- Assertion sites: [454](../../integration_test/group_invite_status_matrix_harness.dart#L454), [455](../../integration_test/group_invite_status_matrix_harness.dart#L455), [470](../../integration_test/group_invite_status_matrix_harness.dart#L470), [477](../../integration_test/group_invite_status_matrix_harness.dart#L477), [486](../../integration_test/group_invite_status_matrix_harness.dart#L486), [487](../../integration_test/group_invite_status_matrix_harness.dart#L487), [488](../../integration_test/group_invite_status_matrix_harness.dart#L488), [489](../../integration_test/group_invite_status_matrix_harness.dart#L489), [490](../../integration_test/group_invite_status_matrix_harness.dart#L490), [496](../../integration_test/group_invite_status_matrix_harness.dart#L496), [497](../../integration_test/group_invite_status_matrix_harness.dart#L497), [539](../../integration_test/group_invite_status_matrix_harness.dart#L539)
- Replacement evidence: `production.group_invite_status_matrix` (check `production-group-invite-matrix`) passed on devices 2026-09-30; see [the matrix record](#2026-09-30-wave-3-invite-status-matrix-replacement). Original retained; retirement not approved.

### `group_lifecycle_simulator_harness.dart`

- Boundary / wave: **dispatcher / 3**. Retain original lifecycle dispatch; additive production children in wave 3.
- Preserved source SHA-256: `04e3b3deda1b39a1871d18b800af2175413ff655ad022c410a7b5cd170e42617`.
- Original source: [`integration_test/group_lifecycle_simulator_harness.dart`](../../integration_test/group_lifecycle_simulator_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `89eac3be34dd0d9b9cb3bb6f` SELECTED; owner=full-sims; selector=``; variant=``
- Direct importers: Entry point or externally selected source.
- Assertion sites: [49](../../integration_test/group_lifecycle_simulator_harness.dart#L49)
- Replacement evidence: DELETE_PRESERVES_FRIENDS → `production.group_delete_preserves_friends` ([record](#2026-09-30-wave-3-delete-preserves-friends-replacement)), INVITE_ACCEPT_SPINNER → `production.group_invite_accept_spinner` ([record](#2026-09-30-wave-3-invite-accept-spinner-replacement)) and NEW_MEMBER_MEDIA → `production.group_new_member_media` ([record](#2026-09-30-wave-3-new-member-media-replacement)) passed on devices 2026-09-30. ADMIN_METADATA pending. Original dispatcher retained; retirement not approved.

### `group_multi_device_real_harness.dart`

- Boundary / wave: **application journey / shared setup / 3**. Add production-created group service consumers; preserve every role, intermediate assertion, and catalog receipt.
- Preserved source SHA-256: `1530f58491563d9fb7eb840028999d65419dfb056ea7f80f6a813e3ab99b280d`.
- Original source: [`integration_test/group_multi_device_real_harness.dart`](../../integration_test/group_multi_device_real_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; construction anchors: `ContactRepositoryImpl`, `FakeNotificationService`, `GroupExitIntentRepositoryImpl`, `GroupInviteDeliveryAttemptRepositoryImpl`, `GroupMessageListener`, `GroupMessageRepositoryImpl`, `GroupPendingBroadcastRepositoryImpl`, `GroupPendingKeyRepairRepositoryImpl`, `GroupReactionReplayOutboxRepositoryImpl`, `GroupRepositoryImpl`, `IdentityRepositoryImpl`, `MediaAttachmentRepositoryImpl`, `MessageRepositoryImpl`, `ReactionRepositoryImpl`, `setupGroupMultiDeviceStack`
- Discovered owners/selectors: `a182226e68297fce053462dc` EXCLUDED; owner=none; selector=``; variant=``; reason=group simulator harness
- Direct importers: [`integration_test/foreground_group_push_simulator_harness.dart`](../../integration_test/foreground_group_push_simulator_harness.dart), [`integration_test/group_multi_party_device_real_harness.dart`](../../integration_test/group_multi_party_device_real_harness.dart), [`integration_test/notification_sound_smoke_harness.dart`](../../integration_test/notification_sound_smoke_harness.dart), [`integration_test/notification_open_during_other_chat_harness.dart`](../../integration_test/notification_open_during_other_chat_harness.dart), [`integration_test/benchmark_group_publish_harness.dart`](../../integration_test/benchmark_group_publish_harness.dart), [`integration_test/group_smoke_harness.dart`](../../integration_test/group_smoke_harness.dart)
- Assertion sites: [2881](../../integration_test/group_multi_device_real_harness.dart#L2881), [2909](../../integration_test/group_multi_device_real_harness.dart#L2909), [2918](../../integration_test/group_multi_device_real_harness.dart#L2918), [2919](../../integration_test/group_multi_device_real_harness.dart#L2919), [2950](../../integration_test/group_multi_device_real_harness.dart#L2950), [2957](../../integration_test/group_multi_device_real_harness.dart#L2957), [2985](../../integration_test/group_multi_device_real_harness.dart#L2985), [3018](../../integration_test/group_multi_device_real_harness.dart#L3018), [3049](../../integration_test/group_multi_device_real_harness.dart#L3049), [3058](../../integration_test/group_multi_device_real_harness.dart#L3058), [3065](../../integration_test/group_multi_device_real_harness.dart#L3065), [3076](../../integration_test/group_multi_device_real_harness.dart#L3076), [3086](../../integration_test/group_multi_device_real_harness.dart#L3086), [3100](../../integration_test/group_multi_device_real_harness.dart#L3100), [3124](../../integration_test/group_multi_device_real_harness.dart#L3124), [3125](../../integration_test/group_multi_device_real_harness.dart#L3125), [3126](../../integration_test/group_multi_device_real_harness.dart#L3126), [3127](../../integration_test/group_multi_device_real_harness.dart#L3127), [3128](../../integration_test/group_multi_device_real_harness.dart#L3128), [3129](../../integration_test/group_multi_device_real_harness.dart#L3129), [3130](../../integration_test/group_multi_device_real_harness.dart#L3130), [3149](../../integration_test/group_multi_device_real_harness.dart#L3149), [3159](../../integration_test/group_multi_device_real_harness.dart#L3159), [3160](../../integration_test/group_multi_device_real_harness.dart#L3160), [3166](../../integration_test/group_multi_device_real_harness.dart#L3166), [3191](../../integration_test/group_multi_device_real_harness.dart#L3191), [3197](../../integration_test/group_multi_device_real_harness.dart#L3197), [3268](../../integration_test/group_multi_device_real_harness.dart#L3268), [3273](../../integration_test/group_multi_device_real_harness.dart#L3273), [3274](../../integration_test/group_multi_device_real_harness.dart#L3274), [3313](../../integration_test/group_multi_device_real_harness.dart#L3313), [3330](../../integration_test/group_multi_device_real_harness.dart#L3330), [3393](../../integration_test/group_multi_device_real_harness.dart#L3393), [3563](../../integration_test/group_multi_device_real_harness.dart#L3563), [3564](../../integration_test/group_multi_device_real_harness.dart#L3564), [3565](../../integration_test/group_multi_device_real_harness.dart#L3565), [3566](../../integration_test/group_multi_device_real_harness.dart#L3566), [3582](../../integration_test/group_multi_device_real_harness.dart#L3582), [3592](../../integration_test/group_multi_device_real_harness.dart#L3592), [3593](../../integration_test/group_multi_device_real_harness.dart#L3593), [3594](../../integration_test/group_multi_device_real_harness.dart#L3594), [3595](../../integration_test/group_multi_device_real_harness.dart#L3595), [3624](../../integration_test/group_multi_device_real_harness.dart#L3624), [3632](../../integration_test/group_multi_device_real_harness.dart#L3632), [3642](../../integration_test/group_multi_device_real_harness.dart#L3642), [3643](../../integration_test/group_multi_device_real_harness.dart#L3643), [3653](../../integration_test/group_multi_device_real_harness.dart#L3653), [3664](../../integration_test/group_multi_device_real_harness.dart#L3664), [3676](../../integration_test/group_multi_device_real_harness.dart#L3676), [3777](../../integration_test/group_multi_device_real_harness.dart#L3777), [3854](../../integration_test/group_multi_device_real_harness.dart#L3854), [3866](../../integration_test/group_multi_device_real_harness.dart#L3866), [3871](../../integration_test/group_multi_device_real_harness.dart#L3871), [3872](../../integration_test/group_multi_device_real_harness.dart#L3872), [3873](../../integration_test/group_multi_device_real_harness.dart#L3873), [3883](../../integration_test/group_multi_device_real_harness.dart#L3883), [3909](../../integration_test/group_multi_device_real_harness.dart#L3909), [3920](../../integration_test/group_multi_device_real_harness.dart#L3920), [3922](../../integration_test/group_multi_device_real_harness.dart#L3922), [3923](../../integration_test/group_multi_device_real_harness.dart#L3923), [3928](../../integration_test/group_multi_device_real_harness.dart#L3928), [3940](../../integration_test/group_multi_device_real_harness.dart#L3940), [3965](../../integration_test/group_multi_device_real_harness.dart#L3965), [4088](../../integration_test/group_multi_device_real_harness.dart#L4088), [4089](../../integration_test/group_multi_device_real_harness.dart#L4089), [4091](../../integration_test/group_multi_device_real_harness.dart#L4091), [4092](../../integration_test/group_multi_device_real_harness.dart#L4092), [4093](../../integration_test/group_multi_device_real_harness.dart#L4093), [4094](../../integration_test/group_multi_device_real_harness.dart#L4094), [4096](../../integration_test/group_multi_device_real_harness.dart#L4096), [4097](../../integration_test/group_multi_device_real_harness.dart#L4097), [4098](../../integration_test/group_multi_device_real_harness.dart#L4098), [4099](../../integration_test/group_multi_device_real_harness.dart#L4099), [4101](../../integration_test/group_multi_device_real_harness.dart#L4101), [4102](../../integration_test/group_multi_device_real_harness.dart#L4102), [4103](../../integration_test/group_multi_device_real_harness.dart#L4103), [4104](../../integration_test/group_multi_device_real_harness.dart#L4104), [4141](../../integration_test/group_multi_device_real_harness.dart#L4141), [4142](../../integration_test/group_multi_device_real_harness.dart#L4142), [4168](../../integration_test/group_multi_device_real_harness.dart#L4168), [4169](../../integration_test/group_multi_device_real_harness.dart#L4169), [4170](../../integration_test/group_multi_device_real_harness.dart#L4170), [4174](../../integration_test/group_multi_device_real_harness.dart#L4174), [4223](../../integration_test/group_multi_device_real_harness.dart#L4223), [4247](../../integration_test/group_multi_device_real_harness.dart#L4247), [4248](../../integration_test/group_multi_device_real_harness.dart#L4248), [4249](../../integration_test/group_multi_device_real_harness.dart#L4249), [4250](../../integration_test/group_multi_device_real_harness.dart#L4250), [4259](../../integration_test/group_multi_device_real_harness.dart#L4259), [4260](../../integration_test/group_multi_device_real_harness.dart#L4260), [4262](../../integration_test/group_multi_device_real_harness.dart#L4262), [4263](../../integration_test/group_multi_device_real_harness.dart#L4263), [4402](../../integration_test/group_multi_device_real_harness.dart#L4402), [5472](../../integration_test/group_multi_device_real_harness.dart#L5472), [5473](../../integration_test/group_multi_device_real_harness.dart#L5473), [5478](../../integration_test/group_multi_device_real_harness.dart#L5478), [5480](../../integration_test/group_multi_device_real_harness.dart#L5480), [5481](../../integration_test/group_multi_device_real_harness.dart#L5481), [5511](../../integration_test/group_multi_device_real_harness.dart#L5511), [5512](../../integration_test/group_multi_device_real_harness.dart#L5512), [5588](../../integration_test/group_multi_device_real_harness.dart#L5588), [5589](../../integration_test/group_multi_device_real_harness.dart#L5589), [5590](../../integration_test/group_multi_device_real_harness.dart#L5590), [5595](../../integration_test/group_multi_device_real_harness.dart#L5595), [5596](../../integration_test/group_multi_device_real_harness.dart#L5596), [5620](../../integration_test/group_multi_device_real_harness.dart#L5620), [5621](../../integration_test/group_multi_device_real_harness.dart#L5621), [5649](../../integration_test/group_multi_device_real_harness.dart#L5649), [5652](../../integration_test/group_multi_device_real_harness.dart#L5652), [5666](../../integration_test/group_multi_device_real_harness.dart#L5666), [5667](../../integration_test/group_multi_device_real_harness.dart#L5667), [5689](../../integration_test/group_multi_device_real_harness.dart#L5689), [5690](../../integration_test/group_multi_device_real_harness.dart#L5690), [5691](../../integration_test/group_multi_device_real_harness.dart#L5691), [5710](../../integration_test/group_multi_device_real_harness.dart#L5710), [5711](../../integration_test/group_multi_device_real_harness.dart#L5711), [5712](../../integration_test/group_multi_device_real_harness.dart#L5712), [5720](../../integration_test/group_multi_device_real_harness.dart#L5720), [5728](../../integration_test/group_multi_device_real_harness.dart#L5728), [5743](../../integration_test/group_multi_device_real_harness.dart#L5743), [5744](../../integration_test/group_multi_device_real_harness.dart#L5744), [5745](../../integration_test/group_multi_device_real_harness.dart#L5745), [5746](../../integration_test/group_multi_device_real_harness.dart#L5746), [5747](../../integration_test/group_multi_device_real_harness.dart#L5747), [5748](../../integration_test/group_multi_device_real_harness.dart#L5748), [5749](../../integration_test/group_multi_device_real_harness.dart#L5749), [5750](../../integration_test/group_multi_device_real_harness.dart#L5750), [5751](../../integration_test/group_multi_device_real_harness.dart#L5751), [5752](../../integration_test/group_multi_device_real_harness.dart#L5752), [5764](../../integration_test/group_multi_device_real_harness.dart#L5764), [5767](../../integration_test/group_multi_device_real_harness.dart#L5767), [5774](../../integration_test/group_multi_device_real_harness.dart#L5774), [5775](../../integration_test/group_multi_device_real_harness.dart#L5775), [5796](../../integration_test/group_multi_device_real_harness.dart#L5796), [5797](../../integration_test/group_multi_device_real_harness.dart#L5797), [5798](../../integration_test/group_multi_device_real_harness.dart#L5798), [5804](../../integration_test/group_multi_device_real_harness.dart#L5804), [5807](../../integration_test/group_multi_device_real_harness.dart#L5807), [5814](../../integration_test/group_multi_device_real_harness.dart#L5814), [5818](../../integration_test/group_multi_device_real_harness.dart#L5818), [5819](../../integration_test/group_multi_device_real_harness.dart#L5819), [5841](../../integration_test/group_multi_device_real_harness.dart#L5841), [5842](../../integration_test/group_multi_device_real_harness.dart#L5842), [5843](../../integration_test/group_multi_device_real_harness.dart#L5843), [5849](../../integration_test/group_multi_device_real_harness.dart#L5849), [5853](../../integration_test/group_multi_device_real_harness.dart#L5853), [5859](../../integration_test/group_multi_device_real_harness.dart#L5859), [5860](../../integration_test/group_multi_device_real_harness.dart#L5860), [5890](../../integration_test/group_multi_device_real_harness.dart#L5890), [5891](../../integration_test/group_multi_device_real_harness.dart#L5891), [5892](../../integration_test/group_multi_device_real_harness.dart#L5892), [5893](../../integration_test/group_multi_device_real_harness.dart#L5893), [5894](../../integration_test/group_multi_device_real_harness.dart#L5894), [5899](../../integration_test/group_multi_device_real_harness.dart#L5899), [5907](../../integration_test/group_multi_device_real_harness.dart#L5907), [5978](../../integration_test/group_multi_device_real_harness.dart#L5978), [5979](../../integration_test/group_multi_device_real_harness.dart#L5979), [5989](../../integration_test/group_multi_device_real_harness.dart#L5989), [5990](../../integration_test/group_multi_device_real_harness.dart#L5990), [5996](../../integration_test/group_multi_device_real_harness.dart#L5996), [6022](../../integration_test/group_multi_device_real_harness.dart#L6022), [6023](../../integration_test/group_multi_device_real_harness.dart#L6023), [6046](../../integration_test/group_multi_device_real_harness.dart#L6046), [6101](../../integration_test/group_multi_device_real_harness.dart#L6101), [6102](../../integration_test/group_multi_device_real_harness.dart#L6102), [6103](../../integration_test/group_multi_device_real_harness.dart#L6103), [6104](../../integration_test/group_multi_device_real_harness.dart#L6104), [6105](../../integration_test/group_multi_device_real_harness.dart#L6105), [6106](../../integration_test/group_multi_device_real_harness.dart#L6106), [6107](../../integration_test/group_multi_device_real_harness.dart#L6107), [6108](../../integration_test/group_multi_device_real_harness.dart#L6108), [6145](../../integration_test/group_multi_device_real_harness.dart#L6145), [6146](../../integration_test/group_multi_device_real_harness.dart#L6146), [6147](../../integration_test/group_multi_device_real_harness.dart#L6147), [6154](../../integration_test/group_multi_device_real_harness.dart#L6154), [6155](../../integration_test/group_multi_device_real_harness.dart#L6155), [6156](../../integration_test/group_multi_device_real_harness.dart#L6156), [6157](../../integration_test/group_multi_device_real_harness.dart#L6157), [6177](../../integration_test/group_multi_device_real_harness.dart#L6177), [6194](../../integration_test/group_multi_device_real_harness.dart#L6194), [6200](../../integration_test/group_multi_device_real_harness.dart#L6200), [6201](../../integration_test/group_multi_device_real_harness.dart#L6201), [6202](../../integration_test/group_multi_device_real_harness.dart#L6202), [6209](../../integration_test/group_multi_device_real_harness.dart#L6209), [6210](../../integration_test/group_multi_device_real_harness.dart#L6210), [6211](../../integration_test/group_multi_device_real_harness.dart#L6211), [6212](../../integration_test/group_multi_device_real_harness.dart#L6212), [6213](../../integration_test/group_multi_device_real_harness.dart#L6213), [6227](../../integration_test/group_multi_device_real_harness.dart#L6227), [6228](../../integration_test/group_multi_device_real_harness.dart#L6228), [6229](../../integration_test/group_multi_device_real_harness.dart#L6229), [6233](../../integration_test/group_multi_device_real_harness.dart#L6233), [6256](../../integration_test/group_multi_device_real_harness.dart#L6256), [6257](../../integration_test/group_multi_device_real_harness.dart#L6257), [6258](../../integration_test/group_multi_device_real_harness.dart#L6258), [6259](../../integration_test/group_multi_device_real_harness.dart#L6259), [6273](../../integration_test/group_multi_device_real_harness.dart#L6273), [6274](../../integration_test/group_multi_device_real_harness.dart#L6274), [6309](../../integration_test/group_multi_device_real_harness.dart#L6309), [6345](../../integration_test/group_multi_device_real_harness.dart#L6345), [6346](../../integration_test/group_multi_device_real_harness.dart#L6346), [6347](../../integration_test/group_multi_device_real_harness.dart#L6347), [6359](../../integration_test/group_multi_device_real_harness.dart#L6359), [6360](../../integration_test/group_multi_device_real_harness.dart#L6360), [6361](../../integration_test/group_multi_device_real_harness.dart#L6361), [6362](../../integration_test/group_multi_device_real_harness.dart#L6362), [6364](../../integration_test/group_multi_device_real_harness.dart#L6364), [6444](../../integration_test/group_multi_device_real_harness.dart#L6444), [6514](../../integration_test/group_multi_device_real_harness.dart#L6514), [6595](../../integration_test/group_multi_device_real_harness.dart#L6595), [6608](../../integration_test/group_multi_device_real_harness.dart#L6608), [6609](../../integration_test/group_multi_device_real_harness.dart#L6609), [6622](../../integration_test/group_multi_device_real_harness.dart#L6622), [6640](../../integration_test/group_multi_device_real_harness.dart#L6640), [6646](../../integration_test/group_multi_device_real_harness.dart#L6646), [6647](../../integration_test/group_multi_device_real_harness.dart#L6647), [6648](../../integration_test/group_multi_device_real_harness.dart#L6648), [6656](../../integration_test/group_multi_device_real_harness.dart#L6656), [6766](../../integration_test/group_multi_device_real_harness.dart#L6766), [6767](../../integration_test/group_multi_device_real_harness.dart#L6767), [6768](../../integration_test/group_multi_device_real_harness.dart#L6768), [6793](../../integration_test/group_multi_device_real_harness.dart#L6793), [6794](../../integration_test/group_multi_device_real_harness.dart#L6794), [6796](../../integration_test/group_multi_device_real_harness.dart#L6796), [6807](../../integration_test/group_multi_device_real_harness.dart#L6807), [6829](../../integration_test/group_multi_device_real_harness.dart#L6829), [6831](../../integration_test/group_multi_device_real_harness.dart#L6831), [6837](../../integration_test/group_multi_device_real_harness.dart#L6837), [6849](../../integration_test/group_multi_device_real_harness.dart#L6849), [6876](../../integration_test/group_multi_device_real_harness.dart#L6876), [6877](../../integration_test/group_multi_device_real_harness.dart#L6877), [6978](../../integration_test/group_multi_device_real_harness.dart#L6978), [6979](../../integration_test/group_multi_device_real_harness.dart#L6979), [6991](../../integration_test/group_multi_device_real_harness.dart#L6991), [7000](../../integration_test/group_multi_device_real_harness.dart#L7000), [7065](../../integration_test/group_multi_device_real_harness.dart#L7065), [7070](../../integration_test/group_multi_device_real_harness.dart#L7070), [7075](../../integration_test/group_multi_device_real_harness.dart#L7075), [7076](../../integration_test/group_multi_device_real_harness.dart#L7076), [7077](../../integration_test/group_multi_device_real_harness.dart#L7077), [7101](../../integration_test/group_multi_device_real_harness.dart#L7101), [7102](../../integration_test/group_multi_device_real_harness.dart#L7102), [7106](../../integration_test/group_multi_device_real_harness.dart#L7106), [7118](../../integration_test/group_multi_device_real_harness.dart#L7118), [7119](../../integration_test/group_multi_device_real_harness.dart#L7119), [7121](../../integration_test/group_multi_device_real_harness.dart#L7121), [7172](../../integration_test/group_multi_device_real_harness.dart#L7172), [7177](../../integration_test/group_multi_device_real_harness.dart#L7177), [7178](../../integration_test/group_multi_device_real_harness.dart#L7178), [7179](../../integration_test/group_multi_device_real_harness.dart#L7179), [7184](../../integration_test/group_multi_device_real_harness.dart#L7184), [7191](../../integration_test/group_multi_device_real_harness.dart#L7191), [7192](../../integration_test/group_multi_device_real_harness.dart#L7192), [7194](../../integration_test/group_multi_device_real_harness.dart#L7194), [7244](../../integration_test/group_multi_device_real_harness.dart#L7244), [7245](../../integration_test/group_multi_device_real_harness.dart#L7245), [7246](../../integration_test/group_multi_device_real_harness.dart#L7246), [7247](../../integration_test/group_multi_device_real_harness.dart#L7247), [7315](../../integration_test/group_multi_device_real_harness.dart#L7315), [7316](../../integration_test/group_multi_device_real_harness.dart#L7316), [7317](../../integration_test/group_multi_device_real_harness.dart#L7317), [7340](../../integration_test/group_multi_device_real_harness.dart#L7340), [7341](../../integration_test/group_multi_device_real_harness.dart#L7341), [7342](../../integration_test/group_multi_device_real_harness.dart#L7342), [7352](../../integration_test/group_multi_device_real_harness.dart#L7352), [7355](../../integration_test/group_multi_device_real_harness.dart#L7355), [7365](../../integration_test/group_multi_device_real_harness.dart#L7365), [7366](../../integration_test/group_multi_device_real_harness.dart#L7366), [7387](../../integration_test/group_multi_device_real_harness.dart#L7387), [7388](../../integration_test/group_multi_device_real_harness.dart#L7388), [7405](../../integration_test/group_multi_device_real_harness.dart#L7405), [7406](../../integration_test/group_multi_device_real_harness.dart#L7406), [7418](../../integration_test/group_multi_device_real_harness.dart#L7418), [7427](../../integration_test/group_multi_device_real_harness.dart#L7427), [7450](../../integration_test/group_multi_device_real_harness.dart#L7450), [7452](../../integration_test/group_multi_device_real_harness.dart#L7452), [7453](../../integration_test/group_multi_device_real_harness.dart#L7453), [7560](../../integration_test/group_multi_device_real_harness.dart#L7560), [7561](../../integration_test/group_multi_device_real_harness.dart#L7561), [7562](../../integration_test/group_multi_device_real_harness.dart#L7562), [7627](../../integration_test/group_multi_device_real_harness.dart#L7627), [7628](../../integration_test/group_multi_device_real_harness.dart#L7628), [7629](../../integration_test/group_multi_device_real_harness.dart#L7629), [7636](../../integration_test/group_multi_device_real_harness.dart#L7636), [7644](../../integration_test/group_multi_device_real_harness.dart#L7644), [7645](../../integration_test/group_multi_device_real_harness.dart#L7645), [7646](../../integration_test/group_multi_device_real_harness.dart#L7646), [7674](../../integration_test/group_multi_device_real_harness.dart#L7674), [7675](../../integration_test/group_multi_device_real_harness.dart#L7675), [7676](../../integration_test/group_multi_device_real_harness.dart#L7676), [7706](../../integration_test/group_multi_device_real_harness.dart#L7706), [7710](../../integration_test/group_multi_device_real_harness.dart#L7710), [7718](../../integration_test/group_multi_device_real_harness.dart#L7718), [7729](../../integration_test/group_multi_device_real_harness.dart#L7729), [7730](../../integration_test/group_multi_device_real_harness.dart#L7730), [7739](../../integration_test/group_multi_device_real_harness.dart#L7739), [7740](../../integration_test/group_multi_device_real_harness.dart#L7740)
- Replacement evidence: pending; original evidence and execution owner retained.

### `group_multi_party_device_real_android_harness.dart`

- Boundary / wave: **dispatcher / 3**. Retain original strict Android dispatch; additive production catalog owner in wave 3.
- Preserved source SHA-256: `7c45e1039caf985161d1f606d7216a185d7743c1bbcc3a61ee829e4d73a5b873`.
- Original source: [`integration_test/group_multi_party_device_real_android_harness.dart`](../../integration_test/group_multi_party_device_real_android_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `5d087bfd270f6639d04948ed` EXCLUDED; owner=none; selector=``; variant=``; reason=group simulator harness
- Direct importers: Entry point or externally selected source.
- Assertion sites: No direct expect/assert/fail; delegated to child/protocol criteria.
- Replacement evidence: pending; original evidence and execution owner retained.

### `group_multi_party_device_real_harness.dart`

- Boundary / wave: **application journey / shared setup / 3**. Add production-created group service consumers; preserve every role, intermediate assertion, and catalog receipt.
- Preserved source SHA-256: `7ed58f8e853d024b90a1ddc665ce58b2e4a7caacabb3969cb01dcb57338f2324`.
- Original source: [`integration_test/group_multi_party_device_real_harness.dart`](../../integration_test/group_multi_party_device_real_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; construction anchors: `setupGroupMultiDeviceStack`
- Discovered owners/selectors: `5e5ff66bbd320cd92ad38738` EXCLUDED; owner=none; selector=``; variant=``; reason=group simulator harness
- Direct importers: [`integration_test/group_multi_party_device_real_android_harness.dart`](../../integration_test/group_multi_party_device_real_android_harness.dart)
- Assertion sites: [951](../../integration_test/group_multi_party_device_real_harness.dart#L951), [956](../../integration_test/group_multi_party_device_real_harness.dart#L956), [957](../../integration_test/group_multi_party_device_real_harness.dart#L957), [1018](../../integration_test/group_multi_party_device_real_harness.dart#L1018), [1019](../../integration_test/group_multi_party_device_real_harness.dart#L1019), [1024](../../integration_test/group_multi_party_device_real_harness.dart#L1024), [1025](../../integration_test/group_multi_party_device_real_harness.dart#L1025), [4784](../../integration_test/group_multi_party_device_real_harness.dart#L4784), [4785](../../integration_test/group_multi_party_device_real_harness.dart#L4785), [5214](../../integration_test/group_multi_party_device_real_harness.dart#L5214), [5215](../../integration_test/group_multi_party_device_real_harness.dart#L5215), [5355](../../integration_test/group_multi_party_device_real_harness.dart#L5355), [5356](../../integration_test/group_multi_party_device_real_harness.dart#L5356), [5576](../../integration_test/group_multi_party_device_real_harness.dart#L5576), [5577](../../integration_test/group_multi_party_device_real_harness.dart#L5577), [6017](../../integration_test/group_multi_party_device_real_harness.dart#L6017), [6018](../../integration_test/group_multi_party_device_real_harness.dart#L6018), [6313](../../integration_test/group_multi_party_device_real_harness.dart#L6313), [6314](../../integration_test/group_multi_party_device_real_harness.dart#L6314), [6735](../../integration_test/group_multi_party_device_real_harness.dart#L6735), [6736](../../integration_test/group_multi_party_device_real_harness.dart#L6736), [9557](../../integration_test/group_multi_party_device_real_harness.dart#L9557), [9633](../../integration_test/group_multi_party_device_real_harness.dart#L9633), [9758](../../integration_test/group_multi_party_device_real_harness.dart#L9758), [9888](../../integration_test/group_multi_party_device_real_harness.dart#L9888), [10271](../../integration_test/group_multi_party_device_real_harness.dart#L10271), [10349](../../integration_test/group_multi_party_device_real_harness.dart#L10349), [10445](../../integration_test/group_multi_party_device_real_harness.dart#L10445), [19624](../../integration_test/group_multi_party_device_real_harness.dart#L19624), [19810](../../integration_test/group_multi_party_device_real_harness.dart#L19810), [19811](../../integration_test/group_multi_party_device_real_harness.dart#L19811), [23590](../../integration_test/group_multi_party_device_real_harness.dart#L23590), [23595](../../integration_test/group_multi_party_device_real_harness.dart#L23595), [23600](../../integration_test/group_multi_party_device_real_harness.dart#L23600), [23605](../../integration_test/group_multi_party_device_real_harness.dart#L23605), [23635](../../integration_test/group_multi_party_device_real_harness.dart#L23635), [23636](../../integration_test/group_multi_party_device_real_harness.dart#L23636), [24349](../../integration_test/group_multi_party_device_real_harness.dart#L24349), [25991](../../integration_test/group_multi_party_device_real_harness.dart#L25991), [25992](../../integration_test/group_multi_party_device_real_harness.dart#L25992), [31862](../../integration_test/group_multi_party_device_real_harness.dart#L31862), [32898](../../integration_test/group_multi_party_device_real_harness.dart#L32898), [46216](../../integration_test/group_multi_party_device_real_harness.dart#L46216)
- Replacement evidence: pending; original evidence and execution owner retained.

### `group_smoke_harness.dart`

- Boundary / wave: **application journey / shared setup / 3**. Add production-created group service consumers; preserve every role, intermediate assertion, and catalog receipt.
- Preserved source SHA-256: `f07bc386f27d206aac08768fa23e13c2201b4fb55caeefa211cc2924b1977729`.
- Original source: [`integration_test/group_smoke_harness.dart`](../../integration_test/group_smoke_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; construction anchors: `GroupMessageListener`, `setupGroupMultiDeviceStack`
- Discovered owners/selectors: `9b905013f407ec592b9e00b5` EXCLUDED; owner=none; selector=``; variant=``; reason=group routing smoke harness
- Direct importers: Entry point or externally selected source.
- Assertion sites: No direct expect/assert/fail; delegated to child/protocol criteria.
- Replacement evidence: G1–G8 are owned by the Wave 2 `production.routing_smoke` replacement (`tool/sims/production_routing_criteria.dart`, "19 direct checks and eight group checks" in [Routing replacement proof boundaries](#routing-replacement-proof-boundaries)); its 27-case integrated-main device pass is `wave2-continuation-003/main-routing-run-002/`. Original retained; retirement not approved.

### `inbox_replay_before_ack_custody_harness.dart`

- Boundary / wave: **protocol proof / retain**. Retain narrow inbox custody boundary; no foreground-startup claim.
- Preserved source SHA-256: `608cfbed804e6fe8991e3d4269a65c5570d9d9b00b8eb0a7fb33972b0590d709`.
- Original source: [`integration_test/inbox_replay_before_ack_custody_harness.dart`](../../integration_test/inbox_replay_before_ack_custody_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `36599e117c6f608b6d4f84a6` EXCLUDED; owner=none; selector=``; variant=``; reason=225 capture-owned TC-A6 replay-before-ack artifact binding; not a device execution row
- Direct importers: Entry point or externally selected source.
- Assertion sites: No direct expect/assert/fail; delegated to child/protocol criteria.
- Replacement evidence: pending; original evidence and execution owner retained.

### `notif_push_payload_persist_harness.dart`

- Boundary / wave: **native/background proof / retain / additive 2**. Retain headless payload persistence; wave 2 adds production lifecycle journey.
- Preserved source SHA-256: `70db77782d508f9732657528730a9e2a055d1a1df06a24d0b837c048ec5de225`.
- Original source: [`integration_test/notif_push_payload_persist_harness.dart`](../../integration_test/notif_push_payload_persist_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `49293b850117ef73549d48fa` EXCLUDED; owner=none; selector=``; variant=``; reason=225 capture-owned TC-B11 payload-persist artifact binding; not a device execution row
- Direct importers: Entry point or externally selected source.
- Assertion sites: No direct expect/assert/fail; delegated to child/protocol criteria.
- Replacement evidence: pending; original evidence and execution owner retained.

### `notification_open_during_other_chat_harness.dart`

- Boundary / wave: **application journey / 2**. Add production routing/lifecycle/notification/media owner with the same cold/warm and privacy boundaries.
- Preserved source SHA-256: `85893e51a1919de594ace0a12730be7f543f4246979aa3f94b6d31397988d887`.
- Original source: [`integration_test/notification_open_during_other_chat_harness.dart`](../../integration_test/notification_open_during_other_chat_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; construction anchors: `MessageRepositoryImpl`, `setupGroupMultiDeviceStack`
- Discovered owners/selectors: `7091c9ef93722bfad3e472ea` EXCLUDED; owner=none; selector=``; variant=``; reason=1:1 notification-open two-simulator harness
- Direct importers: Entry point or externally selected source.
- Assertion sites: [748](../../integration_test/notification_open_during_other_chat_harness.dart#L748)
- Replacement evidence: pending; original evidence and execution owner retained.

### `notification_sound_smoke_harness.dart`

- Boundary / wave: **application journey / 2**. Add production routing/lifecycle/notification/media owner with the same cold/warm and privacy boundaries.
- Preserved source SHA-256: `8e9453b7968f73d73c24d5eaf53aec105f58c4c6bf34c2db09b1a3a5e92f35e6`.
- Original source: [`integration_test/notification_sound_smoke_harness.dart`](../../integration_test/notification_sound_smoke_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; construction anchors: `GroupMessageListener`, `MediaAttachmentRepositoryImpl`, `MessageRepositoryImpl`, `setupGroupMultiDeviceStack`
- Discovered owners/selectors: `199b3125deeee104f15505e0` EXCLUDED; owner=none; selector=``; variant=``; reason=1:1/group notification sound harness
- Direct importers: Entry point or externally selected source.
- Assertion sites: No direct expect/assert/fail; delegated to child/protocol criteria.
- Replacement evidence: pending; original evidence and execution owner retained.

### `orbit_performance_harness.dart`

- Boundary / wave: **component evidence plus application measurement / 4**. Retain existing measured interval and thresholds; add separately named production startup/resume/routing/latency evidence where claimed.
- Preserved source SHA-256: `304221ef091f5c905a4481bf4f300e5cfa141a3f132047b584fe4981faf0ce3d`.
- Original source: [`integration_test/orbit_performance_harness.dart`](../../integration_test/orbit_performance_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `b69b6ba892be7f287bbeff8b` EXCLUDED; owner=none; selector=``; variant=``; reason=helper
- Direct importers: [`integration_test/performance_harness.dart`](../../integration_test/performance_harness.dart)
- Assertion sites: [282](../../integration_test/orbit_performance_harness.dart#L282), [295](../../integration_test/orbit_performance_harness.dart#L295), [299](../../integration_test/orbit_performance_harness.dart#L299), [303](../../integration_test/orbit_performance_harness.dart#L303), [310](../../integration_test/orbit_performance_harness.dart#L310), [328](../../integration_test/orbit_performance_harness.dart#L328), [548](../../integration_test/orbit_performance_harness.dart#L548)
- Replacement evidence: pending; original evidence and execution owner retained.

### `performance_harness.dart`

- Boundary / wave: **dispatcher / 4**. Retain performance selection; production measurements have separate names.
- Preserved source SHA-256: `559ff8c1cb88c48def99584a9091380ac1f20b5f216d8e122f873d11603cebee`.
- Original source: [`integration_test/performance_harness.dart`](../../integration_test/performance_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `45b7c537aec25b72ae748178` SELECTED; owner=full-legacy,full.performance.conversation,full.performance.conversation_sub,full.performance.feed_init,full.performance.feed_orbit_offscreen,full.performance.orbit,full.performance.shell_switch; selector=``; variant=``; `9a3f457535f15a0d04ba1f43` SELECTED; owner=full.performance.conversation; selector=`CONVERSATION`; variant=`compile:PERF_TARGET`; reason=Exact adapter scenario selection; `a98ff9eaa921a75afa0d75da` SELECTED; owner=full.performance.conversation_sub; selector=`CONVERSATION_SUB`; variant=`compile:PERF_TARGET`; reason=Exact adapter scenario selection; `2a9d9501eb0e58f9b967b0c5` SELECTED; owner=full-legacy; selector=`FEED`; variant=`compile:PERF_TARGET`; reason=Exact adapter scenario selection; `37b948e2cbbea401248f303e` SELECTED; owner=full.performance.feed_init; selector=`FEED_INIT`; variant=`compile:PERF_TARGET`; reason=Exact adapter scenario selection; `e78d977b893f3763a9072262` SELECTED; owner=full.performance.feed_orbit_offscreen; selector=`FEED_ORBIT_OFFSCREEN`; variant=`compile:PERF_TARGET`; reason=Exact adapter scenario selection; `ea54496b20488e6c7dfe5133` SELECTED; owner=full-legacy; selector=`IDENTITY_PROGRESS`; variant=`compile:PERF_TARGET`; reason=Exact adapter scenario selection; `de351e7a1b95c7817796089f` SELECTED; owner=full.performance.orbit; selector=`ORBIT`; variant=`compile:PERF_TARGET`; reason=Exact adapter scenario selection; `b3b5bd52f6fc0fc95a9561d3` SELECTED; owner=full.performance.shell_switch; selector=`SHELL_SWITCH`; variant=`compile:PERF_TARGET`; reason=Exact adapter scenario selection
- Direct importers: Entry point or externally selected source.
- Assertion sites: [62](../../integration_test/performance_harness.dart#L62)
- Replacement evidence: pending; original evidence and execution owner retained.

### `relay_recovery_diagnostics_harness.dart`

- Boundary / wave: **component evidence plus application measurement / 4**. Retain existing measured interval and thresholds; add separately named production startup/resume/routing/latency evidence where claimed.
- Preserved source SHA-256: `ef3bb9ef90e946c090f4ade7b96f0fb70fe732553585538b4de0c24578bfa86e`.
- Original source: [`integration_test/relay_recovery_diagnostics_harness.dart`](../../integration_test/relay_recovery_diagnostics_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; no matched graph-construction anchor; follow imported child setup.
- Discovered owners/selectors: `c7689cc6c995f14dc9da0794` EXCLUDED; owner=none; selector=``; variant=``; reason=Native relay recovery and diagnostics comparison harness; uploads terminate locally, explicit virtual-device lifecycle driver optional
- Direct importers: Entry point or externally selected source.
- Assertion sites: [166](../../integration_test/relay_recovery_diagnostics_harness.dart#L166), [167](../../integration_test/relay_recovery_diagnostics_harness.dart#L167), [175](../../integration_test/relay_recovery_diagnostics_harness.dart#L175), [181](../../integration_test/relay_recovery_diagnostics_harness.dart#L181), [182](../../integration_test/relay_recovery_diagnostics_harness.dart#L182), [196](../../integration_test/relay_recovery_diagnostics_harness.dart#L196), [202](../../integration_test/relay_recovery_diagnostics_harness.dart#L202), [203](../../integration_test/relay_recovery_diagnostics_harness.dart#L203), [221](../../integration_test/relay_recovery_diagnostics_harness.dart#L221), [244](../../integration_test/relay_recovery_diagnostics_harness.dart#L244), [260](../../integration_test/relay_recovery_diagnostics_harness.dart#L260), [265](../../integration_test/relay_recovery_diagnostics_harness.dart#L265), [273](../../integration_test/relay_recovery_diagnostics_harness.dart#L273), [274](../../integration_test/relay_recovery_diagnostics_harness.dart#L274), [276](../../integration_test/relay_recovery_diagnostics_harness.dart#L276), [297](../../integration_test/relay_recovery_diagnostics_harness.dart#L297), [299](../../integration_test/relay_recovery_diagnostics_harness.dart#L299), [300](../../integration_test/relay_recovery_diagnostics_harness.dart#L300)
- Replacement evidence: pending; original evidence and execution owner retained.

### `routing_smoke_harness.dart`

- Boundary / wave: **application journey / 2**. Add production routing/lifecycle/notification/media owner with the same cold/warm and privacy boundaries.
- Preserved source SHA-256: `6ed5dd8d340be9fa5f76afad87d7f2588a0ba0728f4ea2bbe785b5e6fdd091b8`.
- Original source: [`integration_test/routing_smoke_harness.dart`](../../integration_test/routing_smoke_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; construction anchors: `ContactRepositoryImpl`, `MediaAttachmentRepositoryImpl`, `MessageRepositoryImpl`
- Discovered owners/selectors: `152faacde601aa631d336961` EXCLUDED; owner=none; selector=``; variant=``; reason=1:1 routing smoke harness
- Direct importers: Entry point or externally selected source.
- Assertion sites: No direct expect/assert/fail; delegated to child/protocol criteria.
- Replacement evidence: pending; original evidence and execution owner retained.

### `transport_census_harness.dart`

- Boundary / wave: **component evidence plus application measurement / 4**. Retain existing measured interval and thresholds; add separately named production startup/resume/routing/latency evidence where claimed.
- Preserved source SHA-256: `288788a033b2dd1bbfe6c768ab050469481902e3245bd9cb54f36f49e6427997`.
- Original source: [`integration_test/transport_census_harness.dart`](../../integration_test/transport_census_harness.dart); unchanged, retirement not approved.
- Build/graph: legacy harness-specific compilation or dispatcher variant; construction anchors: `ContactRepositoryImpl`, `IdentityRepositoryImpl`, `MessageRepositoryImpl`
- Discovered owners/selectors: `cf4b103b34bdabb511b3cf7c` EXCLUDED; owner=none; selector=``; variant=``; reason=NET-REL-04 transport census role harness launched by census orchestrators
- Direct importers: Entry point or externally selected source.
- Assertion sites: [600](../../integration_test/transport_census_harness.dart#L600), [610](../../integration_test/transport_census_harness.dart#L610), [617](../../integration_test/transport_census_harness.dart#L617), [753](../../integration_test/transport_census_harness.dart#L753)
- Replacement evidence: pending; original evidence and execution owner retained.

## Multi-party catalog roles

Each row retains the existing scenario and its intermediate/terminal criteria in [`group_multi_party_device_criteria.dart`](../../integration_test/scripts/group_multi_party_device_criteria.dart). Wave 3 must produce independent production receipts for every applicable role. Four-peer cases require four available compatible targets; unavailable hardware is N/A by project policy. Three Android targets are currently available.

| Scenario | Required roles | Replacement evidence |
|---|---|---|
| `gm001` | alice, bob, charlie | Pending; original retained |
| `de002` | alice, bob, charlie | Pending; original retained |
| `de003` | alice, bob, charlie | Pending; original retained |
| `de007` | alice, bob, charlie | Pending; original retained |
| `de017` | alice, bob, charlie | Pending; original retained |
| `ir001` | alice, bob, charlie | Pending; original retained |
| `ir015` | alice, bob, charlie | Pending; original retained |
| `ir016` | alice, bob, charlie | Pending; original retained |
| `pl002` | alice, bob, charlie | Pending; original retained |
| `pl012` | alice, bob, charlie | Pending; original retained |
| `private_abc_create` | alice, bob, charlie | Pending; original retained |
| `private_reaction_roundtrip` | alice, bob, charlie | Pending; original retained |
| `private_reaction_toggle_convergence` | alice, bob, charlie | Pending; original retained |
| `private_media_reaction_roundtrip` | alice, bob, charlie | Pending; original retained |
| `private_removed_reaction_rejected` | alice, bob, charlie | Pending; original retained |
| `private_never_member_publish_rejected` | alice, bob, charlie, dana | Pending; original retained |
| `private_removed_old_key_publish_rejected` | alice, bob, charlie | Pending; original retained |
| `private_full_mesh_online` | alice, bob, charlie | Pending; original retained |
| `private_relay_only_delivery` | alice, bob, charlie | Pending; original retained |
| `private_stale_roster_recipient_omission` | alice, bob, charlie | Pending; original retained |
| `private_partition_readd_heal` | alice, bob, charlie | Pending; original retained |
| `private_relay_reconnect_group_recovery` | alice, bob, charlie | Pending; original retained |
| `private_peer_disconnect_not_removal` | alice, bob, charlie | Pending; original retained |
| `private_background_resume_group_delivery` | alice, bob, charlie | Pending; original retained |
| `private_long_offline_epoch_churn` | alice, bob, charlie | Pending; original retained |
| `private_process_death_matrix` | alice, bob, charlie | Pending; original retained |
| `private_online_add` | alice, bob, charlie, dana | Pending; original retained |
| `private_offline_add` | alice, bob, charlie, dana | Pending; original retained |
| `private_online_remove` | alice, bob, charlie | Pending; original retained |
| `private_offline_remove` | alice, bob, charlie | Pending; original retained |
| `private_removed_notification_privacy` | alice, bob, charlie | Pending; original retained |
| `private_offline_readd` | alice, bob, charlie | Pending; original retained |
| `private_readd_current` | alice, bob, charlie | Pending; original retained |
| `private_readd_active_members` | alice, bob, charlie, dana | Pending; original retained |
| `private_readd_alternating_churn` | alice, bob, charlie, dana | Pending; original retained |
| `private_max_group_size_churn` | alice, bob, charlie | Pending; original retained |
| `private_network_chaos_invariants` | alice, bob, charlie, dana | Pending; original retained |
| `private_late_leave_readd` | alice, bob, charlie | Pending; original retained |
| `private_rotated_device_readd` | alice, bob, charlie | Pending; original retained |
| `private_same_user_multi_device_readd` | alice, bob, charlie, dana | Pending; original retained |
| `private_readd_cycles` | alice, bob, charlie | Pending; original retained |
| `private_rapid_readd` | alice, bob, charlie | Pending; original retained |
| `private_concurrent_admin_membership_edits` | alice, bob, charlie, dana | Pending; original retained |
| `private_timeline_truth` | alice, bob, charlie | Pending; original retained |
| `private_history_retention` | alice, bob, charlie | Pending; original retained |
| `private_invite_terminal_states` | alice, bob, charlie | Pending; original retained |
| `private_stale_invite_readd` | alice, bob, charlie | Pending; original retained |
| `private_stale_lower_key_update` | alice, bob, charlie | Pending; original retained |
| `private_same_epoch_key_conflict` | alice, bob, charlie | Pending; original retained |
| `private_partial_key_distribution` | alice, bob, charlie | Pending; original retained |
| `private_non_friend_member_delivery` | alice, bob, dana | Pending; original retained |
| `private_online_dissolve_convergence` | alice, bob, charlie | Pending; original retained |
| `private_voluntary_leave_convergence` | alice, bob, charlie | Pending; original retained |
| `private_admin_role_transfer_delivery` | alice, bob, charlie | Pending; original retained |
| `private_admin_metadata_intro_photo_convergence` | alice, bob, charlie | Pending; original retained |
| `private_admin_demotion_enforcement` | alice, bob, charlie, dana | Pending; original retained |
| `private_override_removal_nonconvergence` | alice, bob, charlie | Pending; original retained |
| `regression_group_admin_permissions_and_message_reliability_four_users` | alice, bob, charlie, dana | Pending; original retained |
| `scenario7_group_invite_stale_metadata_recovery` | alice, bob, charlie, dana | Pending; original retained |
| `ge001` | alice, bob, charlie | Pending; original retained |
| `ge002` | alice, bob, charlie | Pending; original retained |
| `ge003` | alice, bob, charlie | Pending; original retained |
| `ge004` | alice, bob, charlie | Pending; original retained |
| `ge005` | alice, bob, charlie | Pending; original retained |
| `ge006` | alice, bob, charlie | Pending; original retained |
| `ge007` | alice, bob, charlie | Pending; original retained |
| `ge008` | alice, bob, charlie | Pending; original retained |
| `ge009` | alice, bob, charlie | Pending; original retained |
| `ge010` | alice, bob, charlie | Pending; original retained |
| `go001` | alice, bob, charlie | Pending; original retained |
| `go002` | alice, bob, charlie | Pending; original retained |
| `go003` | alice, bob, charlie | Pending; original retained |
| `ge011` | alice, bob, charlie | Pending; original retained |
| `ge012` | alice, bob, charlie | Pending; original retained |
| `ge013` | alice, bob, charlie | Pending; original retained |
| `ge014` | alice, bob, charlie | Pending; original retained |
| `ge015` | alice, bob, charlie | Pending; original retained |
| `ge016` | alice, bob, charlie | Pending; original retained |
| `ge020` | alice, bob, charlie | Pending; original retained |
| `ge021` | alice, bob, charlie | Pending; original retained |
| `ge023` | alice, bob, charlie | Pending; original retained |
| `ge024` | alice, bob, charlie | Pending; original retained |
| `gm002` | alice, bob, charlie, dana | Pending; original retained |
| `gm003` | alice, bob, charlie, dana | Pending; original retained |
| `gm004` | alice, bob, charlie | Pending; original retained |
| `gm005` | alice, bob, charlie | Pending; original retained |
| `gm006` | alice, bob, charlie | Pending; original retained |
| `gm007` | alice, bob, charlie | Pending; original retained |
| `gm008` | alice, bob, charlie | Pending; original retained |
| `gm009` | alice, bob, charlie | Pending; original retained |
| `gm010` | alice, bob, charlie | Pending; original retained |
| `gm011` | alice, bob, charlie | Pending; original retained |
| `gm012` | alice, bob, charlie | Pending; original retained |
| `gm013` | alice, bob, charlie | Pending; original retained |
| `gm014` | alice, bob, charlie | Pending; original retained |
| `gm015` | alice, bob, charlie | Pending; original retained |
| `gm016` | alice, bob, charlie | Pending; original retained |
| `gm017` | alice, bob, charlie | Pending; original retained |
| `gm018` | alice, bob, charlie | Pending; original retained |
| `gm019` | alice, bob, charlie | Pending; original retained |
| `gm020` | alice, bob, charlie | Pending; original retained |
| `gm021` | alice, bob, charlie | Pending; original retained |
| `gm022` | alice, bob, charlie | Pending; original retained |
| `gm023` | alice, bob, charlie | Pending; original retained |
| `gm024` | alice, bob, charlie | Pending; original retained |
| `gm025` | alice, bob, charlie | Pending; original retained |
| `gm033` | alice, bob, charlie | Pending; original retained |
| `gm034` | alice, bob, charlie | Pending; original retained |
| `gm035` | alice, bob, charlie | Pending; original retained |

## Existing reconciliation gaps

- `8d70069b3b1b7808df0e36df` — `docker-ws/alltests_go_test.sh` / ``: UNMAPPED. No exact executable selection for shell_contract: docker-ws/alltests_go_test.sh
- `8a901e37a4227f8935e4f51c` — `integration_test/apns_provider_probe_harness.dart` / ``: MANUAL. Provider capture support app waits ten minutes for externally driven provider sends and foreground/background/terminated probes (source comments and ready_for_provider_send marker); its token readiness check alone does not prove delivery. No automated provider-send/lifecycle driver owns this capture recipe.
- `c41214b98d71800cc33e5b3d` — `tool/testing/selection.json` / `signed-audio`: MANUAL. Short signed-candidate bidirectional audio and hangup; candidate includes call feature
- `5f1929e79898ac7d4fb76112` — `tool/testing/selection.json` / `signed-chat-group-media`: MANUAL. Signed Android/iOS representative messaging in both directions; record path and real recipient open
- `48623855ac44e2206f2b4b5d` — `tool/testing/selection.json` / `signed-dual-stack`: MANUAL. Exact signed candidate application transport and independent TURN network matrix, with observed families and authenticated content/media outcomes
- `3c042ea1634c51c9f541dd4f` — `tool/testing/selection.json` / `signed-full-review`: MANUAL. Review outstanding full-regression evidence without combining unrelated revisions
- `37b4a42d37fb9382546bd3a9` — `tool/testing/selection.json` / `signed-notifications`: MANUAL. Signed Android/iOS background, foreground, mute and tap behavior
- `07cbd8c461b58efb7a591316` — `tool/testing/selection.json` / `signed-startup-contacts`: MANUAL. Signed candidate startup/reopen and supported one-scan contact flow
- `d9e359883689c50804fc8353` — `tool/testing/selection.json` / `signed-upgrade-compat`: MANUAL. Upgrade actual previous published binary; old/new peer interoperability using isolated history

## Pilot assertion correspondence

| Original | Production replacement obligation | Proof required |
|---|---|---|
| S1 | Message absent before push; exact ID/text once after; one native notification request with exact route payload | Real production listener/repositories/visibility, same session, injected foreground push |
| S2 | Live arrival before push; one stored message after push; one notification request with exact payload | Same production graph; no replacement listener/notification service |
| S3 | `notificationNeededAfterDrainFailure`; one injected missing-group drain failure; fallback false; zero generic requests | Fault only at drain boundary; real fallback and membership eligibility chain |

Readiness, accepted runtime configuration, and artifact-cache hits never satisfy these scenario assertions.

The Android pilot now has two passing S1/S2/S3 runs on the same frozen source
identity `55e4248b56347026c2a70c16c7d7c5ddefa7575fd60119cabcc044d900d31f26`:
`pilot-device-008` built once; `pilot-device-009-warm` used zero builds and one
cache hit. Both consumed APK SHA-256
`c55bf61da656fc32ca4e17b679b88f5f40eae3d6c90df7dd365cdb39da5d6338` and verified
exact restoration of both devices. Each has three independently validated
scenario receipts; the original iOS assertions remain the comparison boundary.
The 21 bootstrap, 42 journey and 210 SIMS contracts passed on that source.
Evidence is under `.codex-test-logs/production-bootstrap-migration-20260927/`.
The wave host gate remains in progress; diagnostic subset runs do not certify
full migration closure.


## Pilot adapter boundary

Maestro owns ordinary message input, sending and navigation. Appium MCP owns live exploration and OS interaction. Neither a screenshot nor a UI assertion can establish an exact repository row count, a foreground push callback injection without provider delivery, or the precise failed-drain/fallback result and native notification-request count. The additive pilot adapter is limited to runtime configuration, fixture preparation, that injected failure/push boundary, production observations and receipt validation. It constructs no application graph. Its original simulator campaign remains independently selected and unchanged.

The production pilot must also establish S1's missed-live precondition against
production's periodic group recovery. Native topic leave alone is insufficient:
`pilot-device-007-raw` records leave at 16:21:00, an automatic rejoin at
16:21:17 and the message present before push. The fixture holds the existing
serialized group-recovery gate before leaving the owned topic, so competing
rejoin/drain cannot erase that gap. The actual foreground push still invokes
production's targeted inbox drain and listener directly. The hold waits for
prior recovery, expires after three minutes, rejects continuation after expiry,
and releases before S2 or on controller disposal. It never constructs a service
or changes the original missing-message, row-count or notification assertions.
The causal hold and guard probes are preserved under
`.codex-test-logs/production-bootstrap-migration-20260927/`.


The adapter's explicit UI-probe handoff retains the same fixture preparation and
original APK/data restoration guard, then suspends all runner UI actions while
Appium MCP controls the device. Appium cannot itself establish exact restoration
of the captured APK, private app data, permissions and original process state;
the existing guard verifies those boundaries. The probe has a bounded wait for
a run-bound release and always exits without passing scenario evidence. It does
not supply a second UI automation implementation or alter scenario deadlines.

## Notification-open replacement adapter boundary

The next additive journey observes the existing production navigator, real
conversation widgets, repositories, lifecycle and notification publication.
Maestro owns ordinary navigation, message entry and native notification taps;
Appium MCP owns exploration. Read-only internal observations preserve exact
route counts, already-active guard events, message IDs and unread state that a
screenshot alone cannot establish. Only unrelated user-C contact/history is
seeded directly, matching the original regression's prerequisite.

A cold notification tap requires the posted native card to survive death of
this run's app process. Appium's ordinary termination force-stops the package,
which changes that notification precondition. The bounded campaign may kill
only a verified process of the disposable owned package via that package's UID,
then require a new invocation acknowledgement and production startup after the
native notification tap. It may not force a notification route, substitute a
notification service, or treat readiness as a passing scenario. The unchanged
state guard owns exact APK/data/permission/process restoration.
The cold oracle also requires the production initial-payload parsed event with
its exact canonical peer/payload hashes. A fresh process or nonce alone cannot
satisfy the cold-tap assertion if the OS restarted the service before the tap.
The 26-case causal oracle and real navigation-observer host tests pass; device
scenario coverage remains pending.

## Notification-sound replacement observation boundary

The S1–S16 sound replacement must preserve the original upstream silent
parameter separately from the effective native publication decision, exact
contact/payload identity, title/body content, request count and stable native
notification ID. UI and notification-shade assertions cannot establish those
internal decisions. Extend the existing optional production publication
observer with the requested silent value, content hashes and publication time;
keep plaintext title/body out of observer receipts. This observer neither
selects policy nor substitutes the native notification service. Existing OS
channel/card assertions and the separate audible-device evidence remain
required. This is an observation boundary, not completed sound-journey proof.

The S5–S13 originals send controlled attachment-only encrypted descriptors,
not media blobs. Appium and ordinary picker flows cannot establish the same
fixed descriptor identities, empty text, encryption metadata, and per-lane
projection without changing that assertion. A sound-only runtime action may
submit those nine exact descriptors through the existing production send use
cases with production-owned bridge, repositories and identity. It must reject
other scenarios, roles, cases, unknown contacts/groups and replay. Read-only
repository observations prove actual listener persistence. Text sends,
conversation navigation and lifecycle transitions remain Maestro UI flows;
this adapter cannot publish notifications or change visibility trackers.

The production sound replacement is now implemented alongside the original.
Its independent oracle requires all sixteen cases, S15's post-clear control,
exact received rows and encrypted descriptor metadata, real lifecycle/tracker
state, full publication identity/content, upstream/native silence, stable IDs,
six-second suppression windows, and S14's actual first-card capture followed
by the same-ID update inside ten seconds. The original OS disposition CLI
executes on each capture. Host validation: 39 causal/composition tests, three
Maestro syntax checks, clean analysis and the unchanged original disposition
contract pass. Evidence is under `wave2-sound-*`; device evidence is pending.

The frozen Wave 1 host gate finished FAIL after 5,489 seconds: the Dart batch
reported 17,628 passed, six failed and two skipped; both iOS native owners
failed before their required semantic assertions because GoBridge was absent
from the compiled Runner module. Android native 374 passed 73 methods.
`wave1-host-all-002/cleanup-review.json` confirms exact mutation-source
restoration and released leases. The five affected original Dart files pass
107 focused tests in the later candidate, but mixed-candidate diagnostics do
not certify wave or final closure.

## Routing replacement proof boundaries

The routing replacement must account for the original 19 direct checks and
eight group checks, including S1 delivery convergence, S3/S9 actual inbox
receipts, every S8/G5 timeline entry, committed S10 deletion, and G7's receipts
on both sides of rotation. Maestro owns ordinary text sends, deletion and
navigation; real OS background/resume and owned process restarts replace
logical lifecycle simulation where the assertion concerns the application.
Read-only production send-timing events and exact repository observations
retain transport/outcome and persistence evidence that UI cannot establish.

The original S11 intentionally submits a fixed 10 KiB synthetic recording;
S12 measures exact 1 MiB/5 MiB bridge uploads; S13 performs ten sequential
sends without UI pacing; S15 targets the interval after core node restart
and before rendezvous registration; G7 explicitly rotates a group key.
Generic UI flows cannot establish these controlled protocol/measurement
preconditions. Narrow, scenario-bound actions may call the same production
use cases using production-owned services, with exact case IDs, prepared
peer/group identities, single-use invocation records and unchanged payloads.
They must report actual results and observations, never fabricate a passing
receipt or replace a production listener. Existing originals remain selected.
S12/G6/S14's original informational measurements must retain that scope;
reporting them must not turn their unconditional legacy checks into claims
that an unobserved transport path or receiver outcome was proven.

The additive implementation is now `run_production_routing.dart`,
`production_routing_journey_controls.dart` and `production_routing_criteria.dart`,
with a separately registered `production.routing_smoke` capability. The oracle
reuses the unchanged pure legacy predicates, binds them to exact persisted
rows and scoped production timing receipts, and checks actual stop/restart,
process nonce, paused/resumed, deletion and key-generation evidence. The S2,
S9 and G2 batch stages retain their original three-minute limit; S1 convergence
retains two minutes. Host polling intervals are labeled explicitly and are not
represented as cross-device message latency.

The frozen routing candidate passed 54 focused criteria/composition/original
fingerprint tests and 613 selected host checks, with zero failed or skipped
tests. Analysis and all three new Maestro flow syntax checks passed. Evidence:
`production-bootstrap-migration-20260927/wave2-routing-causal-probes-002.log`,
`wave2-routing-host-001/`, `wave2-routing-analysis-004.log` and
`wave2-routing-maestro-syntax-001.json` under `.codex-test-logs/`.
The diagnostic wrapper excludes other required checks and is therefore not
full closure. Device attempt 001 recorded S1 through S6, then failed before S7
when a repeated reopen label collided with its earlier evidence directory.
Exact device restoration passed. The failure and all earlier receipts remain
in `wave2-routing-device-001-raw/`; `cleanup-review.json` records the cause.
The replacement host helper allocates independent directories and four causal
receipt-allocation tests pass. No complete device routing pass or retirement
is claimed.

## Private-media replacement proof boundaries

The retained device-local harness combines encryption/policy component proofs
with manually mounted conversation/viewer proofs. Preserve its exact encrypted
envelope, preview/egress, manual download, expiry, protected-repeat and SQL
assertions. A production-entrypoint projection/open journey is additive and
does not, by itself, replace those component assertions or claim remote
consumption, account-wide revocation, or a network media-transfer proof.

For the application boundary, Maestro/Appium can establish ordinary navigation,
tile opens, viewer closure and deletion, but cannot observe the intermediate
committed SQL states, pending-file ownership, attachment deletion, or absence
of Flutter image widgets inside a private placeholder. Narrow controls may
seed only the fixed local projection, recipient and sender view-once fixtures in
the production-owned database/file manager, subscribe to the production
repository's committed mutation stream, and inspect the mounted production
widget tree. They must not create a database, repository, viewer controller,
policy engine, service container or alternative app root. Fixture and cleanup
identities remain bound to the runtime invocation. Equivalence and retirement
remain pending until both component and application evidence are accounted for.

The additive `production.private_media_local` route implements production
projection, outer-menu deletion, sender pending-open committed SQL lifecycle,
owned-file cleanup, cold persistence and consumed refusal. Its pure oracle has
43 passing positive/negative cases; the same focused run passed six composition
and original-preservation checks (`wave2-private-causal-001.log`). Fixed-fixture
seeding is role-bound and each file path must exactly match its production
pending-upload or canonical-incoming owner convention. The recipient extension
requires real UI open/close, committed available/opening/viewing/consumed states,
attachment/file cleanup, cold persistence and refused reopening. Sender native
window observations discriminate protection acquisition and release without
the protected-thumbnail route grant. Actual extended device evidence remains
pending; retained component coverage does not substitute for those journeys.

Private projection equivalence also distinguishes plan 301's protected-photo
thumbnail from the retained harness's unprotected mounted-widget fallback.
`conversation_protected_photo_thumbnail_test.dart` requires real outgoing bytes
to render the protected tile, and missing bytes to retain the old card. The
production replacement therefore covers both fixed fixture variants; view-once
and terminal placeholders still forbid pixels. The retained original harness's
no-coordinator fallback assertions remain unchanged. UI automation alone cannot
establish Android `FLAG_SECURE`; a read-only, exact-package window observation
binds the protected-pixel case to its actual native window flag. It does
not control the UI or inspect other applications' windows.

The retained private device attempts 002 and 003 failed new projection
expectations while completing the sender lifecycle. Both restored their exact
pre-run package state. Attempt 003 observed the current 88-pixel missing-byte
card with no Open action, matching the production `localMediaAvailable` guard;
the new oracle now requires that exact card and absence of the unavailable
action. Neither failed attempt is a scenario PASS. Evidence and cleanup reviews
remain under `wave2-private-device-002/` and `wave2-private-device-003/`.

## Shared XCTest consumer

`integration_test/support/production_shared_xctest.dart` is an additive consumer
for the existing compatible central physical-iOS app/XCTest bundle profiles.
It verifies the producer's input/artifact attestation and signed product graph,
then creates independent fixture, plist and result paths per selector. It
requires exact single-method/class receipts, fixture-bound assertions and
verified restoration, and exposes no build fallback. Original fresh-build
routes remain unchanged. The 29 focused host tests passed in
`wave4-xctest-causal-003.log`; their native process and codesign responses are
synthetic. A caller integration and real shared-bundle comparative execution
are still required before this Wave 4 obligation can close.

## Group invitation replacement boundary

The first Wave 3 invitation module preserves the original reliability journey's
F (decline acknowledgement), C (fresh invite identity and exact revocation),
and D (stale membership then authenticated metadata resync) intermediate facts.
Production UI owns group creation, decline and revoke. Appium MCP exploration
confirmed that declining retains a terminal card and that declined sender rows
have no Resend affordance. The original protocol's resend after decline is a
one-shot control over the existing production use case, restricted to the exact
run-owned declined attempt; it cannot synthesize delivery or persistence.
The original
150-second, three-minute and four-minute waits remain independent upper bounds.
Appium/Maestro cannot establish the persisted invite IDs, sender delivery status,
revocation tombstone, key generation or stale-to-fresh repository convergence.
A narrow module may observe those exact run-owned production repositories,
invoke the original explicit inbox-drain protocol leg, and prepare only the
original stale-membership and fixed fresh-metadata prerequisites for D. The
fresh metadata setup deliberately emits no broadcast: a normal UI edit could
converge the recipient before the encrypted config request being tested. It must not construct services,
create a group in lieu of the UI action, or synthesize receive/terminal outcomes.
Ordinary UI behavior must be explored through Appium MCP before recording the
stable Maestro flows. Original group harnesses and catalog selectors remain
unchanged; this incremental module alone cannot close the full group catalog.

## Production startup/resume measurement boundary

`production.startup_resume_performance` adds separately named B/M/BR observations
to the production entrypoint. The existing component benchmarks and their exact
selectors remain unchanged. Cold initial/distribution samples use six distinct
fixture identities and processes; hot core/node operations call the existing
production instance; healthy/degraded/extended resume uses actual OS lifecycle.
The readiness-window `totalMs` preserves original thresholds. It is not an
OS-launch-to-frame measurement. The registered target is one available physical
Android phone, with a separate `android.e2e.performance_relay` artifact using
the existing production `DISABLE_LOCAL_DISCOVERY` flag. The ordinary profile's
cold attempt and a single-phone diagnostic both retained failures when
production reached `onlineDirect`, which does not satisfy the original dotted
predicate. No predicate or deadline is relaxed. GP/H retain their separate
simulator/host-filesystem protocol.

Early flow capture, invocation checks and a pure evidence oracle are implemented
with fresh-process, readiness, lifecycle, timeout and failure probes. The twelve
B/M/BR stages passed on the recorded C10 source identity in
`performance-relay-device-005/`, using the attested cached artifact with zero
builds and verified restoration. Earlier failed attempts remain retained. This
result requires final-candidate reconciliation and does not close other
benchmark families, transport consumers or application latency obligations.
Executable ownership remains in the existing manifests; no original owner is
removed or redirected.

## Incremental multi-party reaction replacements

The additive ML-001 creation case passed all three roles using ordinary UI
creation, invitation acceptance and target send (`catalog-device-002/`), with
one central build, zero child builds and exact restoration. The PL-009 reaction
module shares those operations, adds ordinary UI reaction selection, and binds
the actual send return, both receiver streams and each exact persisted row to
the unchanged original terminal oracle. Device proof for PL-009 remains pending.

RT-001 shares ordinary UI setup and target send, then admits a single Bob
add/remove/re-add sequence through existing production use cases and repository
owners. Its two 500 ms delays begin after actual operation returns, preserving
the original rapid-churn protocol. UI picker pacing cannot establish that
interval. Independent receiver removal events and exact final SQL convergence
remain mandatory. The adapter refuses foreign targets, identity changes and
repeat attempts; a queued operation stops the sequence. Its host checks pass,
including the complete 536-test curated lane, but device execution remains
pending. Neither module closes the other original catalog cases or changes
their selection. No original route is retired.

## Main-worktree integration checkpoint

At the time of this checkpoint, rollout was paused by the user's explicit
2026-09-28 instruction. The integration location is
`/Volumes/CrucialX9/flutter_app`, on existing HEAD
`fbe1ae45f07e24e523cc6b63a0f8eb67fab42aab` with local changes preserved. All twelve
migration candidate worktrees were compared against the initial preservation
snapshot, their recorded source lineage and the later main overlay. The current
implementation includes unfinished PL-010 runner/flow registration and the
provider receiver artifact work. No further migration implementation was
permitted before the explicit Wave 2 resumption recorded below. The preservation
and evidence decisions in this checkpoint remain in force.

The source proposal contains 150 paths: 116 additions and 34 existing paths.
Only three original test/harness files change, each to its exact approved bytes.
Existing SIMS profiles and capabilities, mandatory/fast checks and all 109
original catalog selectors remain retained. The older compose/action semantics
versions were superseded by the recorded main reconciliation; the temporary
Podfile lock variation was already restored. Divergent historical log bytes
remain in their original candidates. The sole textual integration conflict is
the plan status; the user's main plan requirement body is preserved verbatim.

Ignored checkpoint evidence is under
`.codex-test-logs/production-bootstrap-migration-20260927/integration-checkpoint-001/`:
main source/index snapshot, candidate inventories, per-path decisions, complete
integration diff, preservation audit, and focused host plan/results. Candidate
worktrees and first-attempt evidence remain in place. No commits, publication,
retirement, new device campaigns, native builds or full host sweep are part of
this checkpoint.

Prior candidate evidence includes cold/warm S1–S3 foreground push, the eleven
private-media local stages, F/C/D invitation stages, all twelve B/M/BR stages,
and ML-001 creation. The final owned native campaign completed 371 and 373,
including all 28 selected Runner XCTest cases, before checkpoint integration.
These are source-bound candidate results, not device certification of integrated
main. The selected wrappers remain incomplete for omitted obligations.

PL-009, RT-001 and PL-010 have host evidence but no full device PASS. Routing
retains its S14 exact-case failure; the stricter additive UI flow has only probe
evidence. Provider background notification and sound, shared XCTest consumption,
remaining group/catalog and transport obligations, comparative retirement and
stable-candidate full closure remain incomplete. The mixed notification receiver
uses the new `android.production_fcm.journey` profile and existing production
Firebase configuration on the emulator only; its profile-specific artifact,
package, lifecycle and restoration changes are unfinished and lack dedicated
causal/device validation. Candidate analysis reports three existing-style lints
in `tool/sims/executor.dart` and no compile errors for that focused set.

Integrated-main bounded verification used verified base
`fbe1ae45f07e24e523cc6b63a0f8eb67fab42aab`, `--local`, and the package-config
Flutter 3.47.2/Dart 3.13.2 SDK. Metadata validation and complete-diff whitespace
checks passed. Focused analysis completed with no errors and three informational
lints in `tool/sims/executor.dart`. The selected host results are:

| Check | Observed result | Passed / failed cases |
| --- | --- | --- |
| `bootstrap` | PASS | 21 / 0 |
| `go-send-wrapper-contracts` | PASS | 4 / 0 |
| `group-harness-contract` | PASS | 357 / 0 |
| `maestro-flow-contracts` | PASS | 9 / 0 |
| `production-journey-contracts` | PASS | 582 / 0 |
| `ui-action-discoverability` | PASS | 263 / 0 |
| `workflow` | FAIL | 237 / 4 |
| `debug-composition-boundaries` | FAIL | 119 / 1 |
| `runtime-roots` | FAIL | 19 / 1 |
| `sims-plan-contract` | BLOCKED | 225 completed before registry setup failed |

Counts describe executions and can overlap across checks. The four workflow
failures and SIMS registry setup exception share six unclassified production
runners: group create, invite reliability, reaction, reaction toggle, removed
reaction and startup/resume performance. Runtime-root inventory also lacks the
three reaction entrypoints. The unchanged architecture checker rejects the
pre-existing beta evidence filename ending
`step-035-assertCondition-[0-9]+_items_pending.json` as an unsafe Git path. Its
bytes match the pre-integration snapshot. No assertion, classifier, inventory or
evidence file was altered to conceal these failures. The first boundary wrapper
attempt was blocked by this checkpoint's own host-check lease; the subsequent
invocation followed lease cleanup, and both results remain retained.

These are diagnostic observations, not certification of one unchanged candidate.
Both host wrappers explicitly report `Source/configuration changed during
execution; candidate evidence invalidated`. Their starting source fingerprints
are `800d9e97297c921609b9cb8281a997b1e8d865922e321c61defc92c8802cbaf2`
and `dafbe0420d6f971990afd807d54efb5fe7952223e01ac27c28f96f9dd6f7c61e`.
Concurrent main changes outside the integration set added two artifact-size
probes and `group_terminal_transition_binding_test.dart`, and edited
`group_message_listener_system_transition_processor.dart`. All were preserved;
an accompanying concurrent group-transition lesson in `TESTING.md` was also
preserved. Their owner and behavior are outside this checkpoint's verification. A separate
owner's group-transition host wrapper was observed and left untouched. The
wrappers also retain their unmapped local-change gaps and all omitted checks as
unrun. Raw plans/results, the failure review and concurrent-file snapshots are
in the checkpoint evidence directory.

The application-time preservation audit passed across all 10,304 pre-existing
main files, including the exact approved original test/harness bytes, with the
index unchanged and no deletions. The post-verification scan found only the
concurrent source edit above among those pre-existing files; it is preserved
alongside the unchanged integration source. All original executable selections
remain retained. There are no unresolved integration conflicts. No device/native
campaign or full host sweep was launched after the pause; the already-owned
native campaign completed cleanup and only the owned temporary emulator stopped.

At this checkpoint, the recommended next bounded batch was host registration
reconciliation for the six discovery and three runtime-root gaps, causal
investigation of the evidence-path rejection while preserving that file and every
original assertion, then exact affected checks on a stable source snapshot. The
resumption and resulting evidence are recorded below.

## Wave 2 resumption checkpoint

Wave 2 resumed on 2026-09-28. Waves 3–5 remain paused; only the shared
discovery/runtime-root registrations and DTR-12 literal Git-path correction
needed for Wave 2 and existing gates were implemented. The original tests and
harnesses remain retained. No retirement, commit, publication or
candidate-worktree cleanup occurred.

The integrated-main candidate is still HEAD and verified base
`fbe1ae45f07e24e523cc6b63a0f8eb67fab42aab`, with `--local` enabled. The wrapper
source identity is `e6130e3970c8ed93590cc5f15ea08a684d654467523dced88dc8ebc420861572`
and its plan fingerprint is
`7607b02b683cc4e0e7ae6480381a3709787cce5cf5506c6f5254864adcc57389`.
The Flutter/Dart toolchain was 3.47.2/3.13.2. The exact host results and
restricted logs are in
`.codex-test-logs/production-bootstrap-migration-20260928/wave2-resumption-001/host-prereq-002/`.

The focused current-source host results are:

| Check | Result | Passed / failed |
| --- | --- | ---: |
| `workflow` | PASS | 241 / 0 |
| `provider-schema` | PASS | 5 / 0 |
| `runtime-roots` | PASS | 20 / 0 |
| `sims-plan-contract` | PASS | 235 / 0 |
| `debug-composition-boundaries` | PASS | 121 / 0 |
| `maestro-flow-contracts` | PASS | 9 / 0 |
| `production-journey-contracts` | PASS | 582 / 0 |
| `strict-group-media-manifest` | PASS | 129 / 0 |

These eight checks were run through `scripts/mknoon_checks.py` with explicit
`--base fbe1ae45f07e24e523cc6b63a0f8eb67fab42aab --local`. The broad dirty-tree
preview selected 149 checks; the diagnostic subset passed those eight and left
141 `NOT RUN`. Its overall status is `BLOCKED`, with 604 unmapped local paths;
the report does not certify full affected-selection or full-host closure. The
first preview timeout, the SDK-path mismatch and the corrected pinned-SDK
preview are retained in `prerequisite-plan-001/`, `prerequisite-plan-002/` and
`prerequisite-plan-003/`. The final reliability-discovery classification is
captured in `reliability-discovery-final.stdout.tsv` with exit code 0.

| Original assertion / variant | Current owner | Integrated-main status and proof | Remaining gap |
| --- | --- | --- | --- |
| Six new runner classifications, three reaction runtime roots, and the DTR-12 Git evidence path containing literal `[0-9]+` | Reliability discovery, runtime-root inventory and architecture boundary checker | PASS: workflow 241, SIMS plan 235, runtime roots 20 and debug boundaries 121; the exact Git path regression test is included in `debug-composition-boundaries`. | No remaining prerequisite repair. Later-wave scenario campaigns remain paused. |
| Real provider delivery to the production notification receiver, with the production sender and receiver package identities preserved | `production.notification_open`; `android.production_fcm.journey` receiver profile | BLOCKED / not run: provider schema 5 and production journey contracts 582 pass. The earlier provider-background attempt still records a delivery failure in `.codex-test-logs/production-bootstrap-migration-20260927/wave2-device-001-raw/`. | Isolated device/account/service configuration and provider readiness are absent; execute the exact mixed sender/receiver proof after they are available. |
| Warm notification routing during chat, cold native tap startup, same-peer duplicate suppression, and persisted payload identity | `production.notification_open` | Host criteria and activation contracts pass within `production-journey-contracts` (582 / 0). No current-source device attempt was launched. | The campaign preview records `isolated device/account/service configuration required`; verify the original warm/cold/payload assertions on the pinned Android pair. |
| Sound S1–S16, including the post-clear S15 control and the first-card identity assertion | `production.notification_sound` | Host criteria and descriptor contracts pass within `production-journey-contracts` (582 / 0); the earlier 39 causal/composition probes remain retained. No current-source speaker/device result exists. | Run the complete campaign and retain native disposition plus speaker evidence; the campaign is blocked on isolated configuration. |
| All 27 ordered routing cases, with exact intermediate and terminal receipts | `production.routing_smoke` | Host criteria pass within `production-journey-contracts` (582 / 0). The prior S14 case-sensitive text failure remains preserved; no current-source full routing attempt ran. | Run the full 27-case catalog on the current candidate and preserve exact S14 text and receipts; campaign configuration is absent. |
| Private-media local user flow with committed SQL, exact bytes/owner cleanup and cold consumed-refusal assertions | `production.private_media_local` | Host criteria pass within `production-journey-contracts` (582 / 0). The earlier candidate's recipient/native-window device pass remains in `.codex-test-logs/production-bootstrap-migration-20260927/wave2-private-device-004/`; it is not proof for this current source identity. | Re-run on integrated main with isolated configuration, then retain the separate crypto, expiry, download and remote-revocation proofs. |

The corrected campaign preview for this source identity is
`.codex-test-logs/production-bootstrap-migration-20260928/wave2-resumption-001/wave2-campaign-plan-002/plan.json`.
With the repository Flutter SDK and installed Maestro 2.10.0 on `PATH`, all
four Wave 2 campaigns are blocked only by the absent isolated
device/account/service configuration. The current live matrix recorded in
`device-preflight-001/devices.json` contains the USB Pixel 6
`21071FDF600CSC` and Android emulator `emulator-5556`, both Android 17/API 37.
`tool/testing/config.local.json` is absent, and no campaign was launched or
device state changed. Prior failed attempts and their cleanup evidence remain
unchanged; candidate successes have not been promoted to integrated-main proof.

**Superseded setup diagnosis:** the claim above that an absent
`tool/testing/config.local.json` blocked the four campaigns was refuted by the
subsequent review. The wrapper accepts an explicit `--device-config`; the
existing ignored configuration was accepted in
`.codex-test-logs/production-bootstrap-migration-20260928/wave2-review-001/preview/plan.json`
with no reported Wave 2 campaign setup reason. That preview did not execute a
scenario or establish provider delivery. The continuation uses a separately
verified, ignored configuration pinned to the currently available USB Android
`21071FDF600CSC` and emulator `emulator-5554`. Its exact path and campaign
receipts are recorded in the continuation section below.

## Wave 2 continuation — verified device evidence

The continuation used detached candidate
`/Volumes/CrucialX9/flutter_app-wave2-candidate-20260928`, based on HEAD
`06d5ab5704cf0106e730f0dab17b0abfd645fe7c`, with explicit `--base HEAD
--local`. Its ignored device configuration is
`.codex-test-logs/production-bootstrap-migration-20260928/wave2-continuation-001/provider-device-config-emulator-5554.json`
(SHA-256 `38a3095fa6210407423372aaacfe9eaa66a81d3d05cce8e8cf551c3404cfb5c2`).
The verified pair is USB Android `21071FDF600CSC` and available Android
emulator `emulator-5554`. The sender profile is `android.e2e.main` with package
`com.mknoon.sims.connectivity`; notification receivers use additive
`android.production_fcm.journey` with package `com.mknoon.app`. The private
local journey uses the disposable package on both peers. No iOS-specific
boundary was needed for these Android two-peer obligations.

The later final candidate identity is
`48f5fd4fcbc941d838f0a63da638c6d3bf110efae447661e8a2b6671cb9dd18e`.
It includes the user's two separately approved original-file registration
patches: three journey send callers in the bootstrap caller census and two
already-passing call-wake methods in the Plan 374 native JUnit manifest (75
methods). The iOS Podfile now sets generated Pod targets to the app's existing
iOS 15 minimum; the pinned Plan 371 iOS native XCTest passed eight methods.
Both original-file proposals passed exact shadow-copy checks before approval;
the applied files match those proposals byte-for-byte in main and candidate.
The final candidate's source/configuration plan is
`wave2-frozen-035/plan-001/plan.json`. The original sound, notification-open,
private-media and routing passes in the table below precede these changes and
are retained as historical evidence. The final-source reruns below now pass.

| Obligation | Exact candidate receipt | Verified result and limit |
| --- | --- | --- |
| S1–S16 plus S15 post-clear notification sound | `wave2-frozen-029/sound-run-001/production-notification-sound-0-sims.json`; `build/sims/proofs/production.notification_sound/attempt-hWD5I8/` | PASS 17 observations, S14 first-card capture, S16 connected direct message, accepted FCM/native ingress and duplicate suppression, empty oracle, exact two-peer cleanup. Source `19f590e3abc2b798f94908ebe2945b5c0b96468103e518c27c15e1a2b56b1e84`; two attested profile cache hits, zero rebuilds. The preserved S16 native verifier returned `audibleStrict` pass. Acoustic speaker output was not monitorable and remains unobserved. The earlier passing source and two cold builds remain under `wave2-frozen-022/`. |
| Warm other-chat, cold-start and same-peer notification taps | `wave2-frozen-025/open-run-001/production-notification-open-0-sims.json`; `build/sims/proofs/production.notification_open/attempt-hmvmay/` | PASS three cases, actual native cards before tap, provider 2xx/native ingress, exact route/unread/cold initial-payload assertions, empty oracle and exact cleanup. Source `19f590e3abc2b798f94908ebe2945b5c0b96468103e518c27c15e1a2b56b1e84`; two attested build-cache hits and no rebuild. |
| Local private-media journey | `wave2-frozen-026/private-run-001/production-private-media-0-sims.json`; `build/sims/proofs/production.private_media_local/attempt-HezuWd/` | PASS production local journey with projection, committed transitions, exact bytes, ownership/cleanup, viewer and cold consumed-refusal assertions; empty oracle and exact two-peer cleanup. Same source `19f590e3abc2b798f94908ebe2945b5c0b96468103e518c27c15e1a2b56b1e84`; one attested sender cache hit, zero rebuilds. Separate crypto/policy/native owners remain retained. |
| 27 ordered routing cases | `wave2-frozen-027/routing-run-001/production-routing-0-sims.json`; `build/sims/proofs/production.routing_smoke/attempt-cuUHU9/` | PASS all 27 cases with intermediate receipts, empty oracle and exact two-peer cleanup. S14 stored exact lower-case `relay fallback` on both peers over relay transport. Same source `19f590e3abc2b798f94908ebe2945b5c0b96468103e518c27c15e1a2b56b1e84`; one attested sender cache hit and zero rebuilds. The original three-minute deadline was preserved. |

On final candidate source `48f5fd4fcbc941d838f0a63da638c6d3bf110efae447661e8a2b6671cb9dd18e`,
`wave2-frozen-035/open-run-002/production-notification-open-0-sims.json`
passed the same three notification-open cases, independent report verification,
two attested cache hits with zero builds, and exact cleanup. Its device proof
is `build/sims/proofs/production.notification_open/attempt-k9BbhV/`.
The first final-source private-media scenario
`wave2-frozen-035/private-run-002/` passed with exact cleanup, but that
invocation's immediate wrapper report verification blocked; the exact
standalone verifier later passed. The fresh
`wave2-frozen-035/private-run-003/production-private-media-0-sims.json`
passed the entire local journey and independent verification, with one
attested cache hit, zero builds and exact cleanup. Its proof is
`build/sims/proofs/production.private_media_local/attempt-WP74GE/`.
The first final-source routing attempt `wave2-frozen-035/routing-run-001/`
timed out at S9's Maestro batch-send flow without step results; it retained
exact cleanup. A pinned read-only Maestro hierarchy probe passed afterward.
The fresh `wave2-frozen-035/routing-run-002/production-routing-0-sims.json`
passed all 27 ordered cases, independent report verification, one attested
cache hit, zero builds and exact two-peer cleanup. Its proof is
`build/sims/proofs/production.routing_smoke/attempt-cVi14A/`. S14's sender
and receiver committed the same exact lower-case `relay fallback` text over
relay transport. The original three-minute deadline was preserved.
The final-source sound run
`wave2-frozen-035/sound-run-001/production-notification-sound-0-sims.json`
passed all 17 observations (S1–S16 plus S15 post-clear), independent report
verification, two attested cache hits, zero builds and exact two-peer
cleanup. S14 retained its first-card-before-update capture; S16's paused
receiver was connected and online, provider/native ingress was accepted and
the duplicate was suppressed. Its preserved OS verifier returned
`audibleStrict` pass and its oracle was empty. Its proof is
`build/sims/proofs/production.notification_sound/attempt-2tPq7W/`.
Acoustic tone for this S16 receipt is unobserved because emulator output
could not be monitored. A later S16-only diagnostic retained native
`audibleStrict` and exact cleanup but intentionally could not certify the
17-case campaign. Mac microphone capture detected the Pixie Dust reference
from Mac speakers but no matching waveform during that S16 diagnostic. The
Android Settings notification-sound preview also produced no clear
microphone signal despite the emulator notification stream being unmuted at
5/7 and routed to speaker. The user heard a tone later but could not tie it
to the Mknoon S16 arrival rather than the Settings preview. The diagnostic
is retained under `wave2-frozen-036/sound-s16-acoustic-001/` and the mic
evidence under main's `wave2-continuation-001/acoustic-s16-001/`.
All four Wave 2 campaigns now have passing, independently verified receipts
on the same final candidate source and ignored configuration.
Their four final-source reports record six attested cache hits and zero new
builds: two for opening, one for private media, one for routing and two for
sound. The shared `android.e2e.main` artifact SHA-256 is
`4f5ed9796a5bf54486c5a66059dc437cce2df8508d13afe9d8e6e96f60ec574f`;
the additive `android.production_fcm.journey` receiver artifact SHA-256 is
`162e17cebfe7b23eec03015f0f88a43de51c3208d158cb55e1c09f8de4f268b2`.
The two original cold builds are retained under `wave2-frozen-022/`; these
final-source runs demonstrate unchanged compatible artifact reuse. Each
final proof has `cleanup.json` with `exactRestorationVerified: true` for
`21071FDF600CSC` and `emulator-5554`.

These `--only` wrapper invocations intentionally leave other selected checks
`NOT RUN`; their overall `BLOCKED` status is not a failing campaign oracle.
The sound S12 transient failure and notification-open headless-observer and
Maestro startup failures remain preserved in `wave2-frozen-021/`,
`wave2-frozen-023/` and `wave2-frozen-024/` with exact cleanup receipts. The
verified diagnosis and additive repairs are recorded in `TESTING.md`.
The final-source `wave2-frozen-028/` S3 attempt also remains retained: a
production announcement recovery overlapped the UI send and returned
`group_recovery_pending`; cleanup passed. A fresh unchanged full run then
passed as shown above. This timing failure is not an acoustic observation.

The integrated-main wave-boundary `host-all` receipt is
`.codex-test-logs/production-bootstrap-migration-20260928/wave2-continuation-001/host-all-final-001.log`.
The Flutter batch ran 18,328 tests and failed five broad-tree assertions:
three unchanged DTR-18 fingerprint expectations against concurrent source
changes, the analyzer suppression inventory after `third_party/video_compress`
appeared, and a runtime-root directive in preserved beta video-compress
evidence. The Go libp2p contract leg failed two local peer dials during the
full sweep; both exact tests passed on a subsequent focused `go test` run.
The same full sweep passed Plan 371 (eight iOS XCTest methods), Plan 373
(native mutation and restoration), Plan 374 (nine Android classes / 75
methods), and the relay/native legs. The first full-host failure remains
retained; no original expectation or deadline was altered to force it green.
This is a failed wave-boundary gate, not a Wave 2 closure receipt.
The later repair restored only the missing beta video-compress
`subscription.dart` next to its existing copied source. The added file is
byte-identical to the vendored companion. After separate exact user approvals
and shadow-copy passes, the DTR-18 original test now has two reviewed
bootstrap fingerprints updated, and the analyzer original test registers
`third_party/video_compress` as an expected package root. No assertion logic
changed. The three original test files then passed 29 tests together. The
fresh full host sweep is retained separately as
`wave2-continuation-002/host-all-002.log`. It exited zero: 18,333 Flutter
tests passed with two skips; the Go and relay legs passed; Plan 371, Plan
373 and Plan 374 passed their native owners (Plan 374: nine Android classes,
75 methods). This is the passing wave-boundary host gate. Device acceptance
remains separate.
The final candidate's focused wrapper
`wave2-frozen-035/host-focused-001/` passed all eight selected host checks:
workflow, provider schema, strict group-media manifest, runtime roots,
debug composition boundaries, SIMS plan contracts, production journey
contracts and Maestro flow contracts. It is bound to the same
`48f5fd4fcbc941d838f0a63da638c6d3bf110efae447661e8a2b6671cb9dd18e`
source as the final device reports. Its overall `BLOCKED` classification
reflects intentionally unrun checks outside the `--only` subset; it does
not replace the failed integrated-main `host-all` result.
The first integrated-main Wave 2 selection
`wave2-continuation-002/main-wave2-run-001/` is bound to source
`914ac51ae5bbfc3818be44f09c4a26bd160371d129f377716004b51f980dcab0`.
All eight focused host checks passed. Notification-open and sound stopped at
preflight when the pinned emulator's automation `dumpsys` timed out; neither
launched a scenario. Three immediate exact direct probes succeeded in under
a quarter-second, so this is an intermittent setup observation. The private
campaign made one cold sender build (artifact SHA-256
`61e3c2517d18512f7aea3182ae4728219421f33125d258b420978d6f013ffa3c`)
and reached the app, then timed out in the first `alice-reopen` Maestro flow
without step results. Its `attempt-VozCOG/cleanup.json` verifies exact
two-peer restoration; routing stayed unrun. Appium page source and a pinned
Maestro hierarchy probe succeeded after cleanup. The fresh private attempt
`wave2-continuation-002/main-private-run-002/` passed both peer reopen flows
but timed out before step output in projection-open. Its
`attempt-CkxFQn/cleanup.json` also verifies exact two-peer restoration.
Machine load around 124 during repeated iOS native builds is a possible
automation timing cause, not a demonstrated product failure. These first
main-source device attempts are not acceptance passes.
The later `wave2-continuation-002/main-open-run-001/` stopped before launch:
the physical Pixel's process census showed an active Appium UiAutomator2
instrumentation owned outside this task's MCP sessions. The target was
available but another controller had UI ownership. The session has been
preserved; no notification-open assertion ran in that attempt.

## 2026-09-29 integrated-main device continuation

The user authorized taking over USB Pixel `21071FDF600CSC`. The active Appium
instrumentation on that phone was released; other Appium services and devices
were left alone. All subsequent Wave 2 campaigns targeted only that Pixel
and `emulator-5554` through the ignored pinned device configuration. On source
`bb29798e632479a820b8b4849894a32ba517e7f5344859187d91e07d16de1dc4`,
the explicit `--base HEAD --local` one-campaign wrapper runs passed:

| Campaign | Passing report | Exact proof and cleanup |
| --- | --- | --- |
| Notification open | `wave2-continuation-003/main-open-run-004/production-notification-open-0-sims.json` | `build/sims/proofs/production.notification_open/attempt-ftEuOX/`: three cases, three accepted provider/native ingress receipts, empty oracle, exact two-peer cleanup. |
| Private media | `wave2-continuation-003/main-private-run-001/production-private-media-0-sims.json` | `build/sims/proofs/production.private_media_local/attempt-rzBO1g/`: original local journey, empty oracle, exact two-peer cleanup. |
| Routing | `wave2-continuation-003/main-routing-run-002/production-routing-0-sims.json` | `build/sims/proofs/production.routing_smoke/attempt-r987Ml/`: 27 ordered cases, empty oracle, exact two-peer cleanup; S14 exact `relay fallback` and relay transport on both peers. |

The first notification-open send at `main-open-run-002/` failed before a case
assertion because the adapter ignored the provider helper's redacted stderr.
A focused parser test and analyzer pass preceded `main-open-run-003/`, which
identified FCM `404 UNREGISTERED`. Current main rotates a cached FCM token
after each app bootstrap first read, while the journey had claimed the token
before reopening Bob. The additive journey now claims after reopen and again
after the cold tap starts a new process; the fresh full run passed. Both first
failures and exact cleanup remain retained. The first routing run
`main-routing-run-001/` recorded through G1, then Maestro failed at G2 when
it enumerated a temporarily offline unrelated emulator. It never selected
that emulator; exact two-peer cleanup and a subsequent pinned Pixel hierarchy
probe passed before the fresh routing pass.

The first two integrated-main sound attempts remain failed. `main-sound-run-001/` recorded S1
and S2 before the next Maestro flow timed out after 110 seconds without step
results; `attempt-UTaiEs/` retains its first failure and exact cleanup.
`main-sound-run-002/` stopped at Bob's reopen with the same no-step timeout;
`attempt-wEw0Qe/` also retains its first failure and exact cleanup. High,
fluctuating host load is a possible automation cause, not a proved one.
The second sound run used source identity
`0c0b6fccb7514726d74bd15636e1951df18b4b3698c571e75467c89838458703`,
different from the three passing main wrapper reports; the whole-tree source
fingerprint had changed between invocations. The fresh
`main-sound-run-003/production-notification-sound-0-sims.json` passed all 17
observations, including S14's first card and S16's background provider/native
proof. Its `build/sims/proofs/production.notification_sound/attempt-T6INKk/`
contains an empty oracle, `audibleStrict` native receipt, accepted FCM/native
ingress and exact two-peer cleanup. The wrapper selected check is `PASS` on
source fingerprint `b5e11c661e396bd857224695c7516ea6786c36752145786012946e0f67e7e624`.
All four passing integrated-main SIMS reports record the same campaign source
digest `82d32bb186b69fea5fe9b77dbf811ca997a47afaa629ff19a2f3e058f43a94fc`
and the same respective APK digests: sender
`3b2729fd2b9d9d0330aa827daf8d836687848b460218a37371c56b92d99d5a1e`,
provider receiver
`51e19f1740ac2054c0c257e3acb310184d601b54ba7fc58d007cca8c4bc83211`.
The wrapper's broader source fingerprint also hashes non-campaign checkout
inputs, including unrelated untracked files written by a concurrent call
campaign; it must not be mistaken for a changed SIMS source or artifact.
The four passing runs used two cold builds and four attested cache hits in
total. Each one-campaign wrapper remains overall `BLOCKED` because other
selected checks were intentionally `NOT RUN` outside its `--only` selection.

S16's device audio service retained a notification MediaPlayer started at
15:34:26.912, 0.616 seconds after the journey's OS-post event. It reported
no mute and device `speaker(2)` with notification volume 5/7; the correlated
redacted excerpt is `attempt-T6INKk/S16-android-audio-playback.txt`. This
establishes Android's speaker playback path, separately from the OS card and
internal disposition. The user could not monitor this S16 arrival, so an
acoustic waveform or hearing observation attributable to S16 remains open.

The fresh integrated-main focused wrapper passed eight selected host checks
on the sound-run wrapper fingerprint at
`wave2-continuation-003/host-focused-run-001/`. The first later full
`host-all` at `wave2-continuation-003/host-all-final-003.log` passed 18,333
Flutter tests with two skips but failed original group membership UP-012 once
in the batch; the exact test and its complete 91-test file then passed in
isolation (`group-up012-focused-001.log` and
`group-membership-file-001.log`). The full Dart `host-all` rerun at
`host-all-dart-rerun-001.log` then passed 18,334 tests with two skips, including
UP-012. The first batch failure remains retained with no proved cause. The
first full run's Go/relay and Plan 374 Android native tails passed. Plans 371
and 373 stopped before tests because that invocation omitted the required iOS
simulator ID. The user subsequently allowed available iOS simulators other
than iPhone 15, or connected iPhones, for separate iOS-specific checks; the
native reruns are pinned to the available iPhone 17 Pro simulator
`674DFFF6-5F38-4235-93F6-AF7FBF86AE65`. Plan 371 passed its native host
contract in `ios-native-371-001.log`; the XCTest summary reports eight passed,
zero failed and zero skipped methods in `/tmp/plan371-native.Q1GeXu/`. The
user requested a stop for reboot during Plan 373. Its three intentional
mutation controls each re-redded and restored the same original Swift source
hash `e0900f0c246af544ac60a83b21f715ddfeae6c293a37ca483bcd36510149b650`;
the restored XCTest build was interrupted before its 28-method verdict.
`ios-native-373-001.log` and `/tmp/plan373-native.HdQXuo/` retain the
partial result. This is an interrupted check, not a test failure.

A bounded output-capture probe on `emulator-5554` did not establish a usable
audio recorder: an Android Settings notification sound preview started a
MediaPlayer, but the scrcpy capture had no sustained signal above -55 dB.
The probe is retained in `sound-audio-positive-001.*`; no S16 result is
inferred from that failed positive control. At this 2026-09-29 checkpoint,
Wave 2 closure was incomplete pending a completed Plan 373 native rerun and
S16 acoustic attribution. The Plan 373 status is superseded by the audit below;
Waves 3–5 remain paused.

## 2026-09-30 bounded Wave 2 closure audit

**WAVE 2 COMPLETE (2026-09-30).** The user explicitly accepted S16's native
speaker-path receipt as sufficient audible-device evidence for Wave 2 closure,
with direct acoustic hearing explicitly unverified. The passing 17-case
integrated-main sound receipt in `wave2-continuation-003/main-sound-run-003/`
records S16 `audibleStrict`, accepted provider/native ingress, the OS post and
a SystemUI notification MediaPlayer started 0.616 seconds later on an unmuted
speaker route at volume 5/7. This acceptance is limited to native playback
through the speaker path; no S16 waveform or human hearing is claimed. It
supersedes the earlier acoustic-attribution-only INCOMPLETE verdict without
changing any campaign assertion or erasing a failed attempt.

The bounded system-audio positive control in
`wave2-continuation-003/sound-system-control-001.*` captured two Android
Settings notification previews; its two signal windows matched the device's
SoundPicker MediaPlayer starts after the measured capture latency. This proved
the global recorder could see those previews, not that it captured S16. One
fresh full sound attempt used the same pinned USB Pixel `21071FDF600CSC` and
`emulator-5554` and the ignored provider device configuration. Its two APK
digests remained `3b2729fd2b9d9d0330aa827daf8d836687848b460218a37371c56b92d99d5a1e`
and `51e19f1740ac2054c0c257e3acb310184d601b54ba7fc58d007cca8c4bc83211`;
the build ledger reports zero builds and two attested hits. The run failed
after S7 when `production_conversation_back` returned no Maestro step results
within 110 seconds. `main-sound-run-004/` and
`build/sims/proofs/production.notification_sound/attempt-kO09aL/` retain the
first failure, seven case observations and `cleanup.json` with exact restoration
on both peers. S15 and S16 were never reached, so the planned S16 recording
never started. The user explicitly bounded sound exploration; no further audio
campaign is inferred from the passing native playback trace.

The pinned iPhone 17 Pro simulator
`674DFFF6-5F38-4235-93F6-AF7FBF86AE65` completed
`scripts/test/run_ios_nse_native_373.sh` with the repository's Flutter 3.47.2
SDK. `wave2-continuation-003/ios-native-373-003/` retains exact Go discovery,
four focused roots (including race execution), four preservers, fixture and
binding checks, and the TC-398-03 native-result pull. Its three XCTest mutation
summaries each report one intended failure, zero skips; the restored TC-373-05
summary reports one pass; the final `ios-xctest-summary.json` reports exactly
28 passes, zero failures and zero skips. The wrapper exited zero, removed its
owned DerivedData directories, and restored
`IosLocalNotificationFinalEffect.swift` to SHA-256
`e0900f0c246af544ac60a83b21f715ddfeae6c293a37ca483bcd36510149b650`.
The earlier `ios-native-373-002/` setup failure is retained separately: the
default Flutter 3.41.4 tool and stale iOS plugin metadata caused duplicate
WebRTC framework producers before the first native assertion. Correct SDK
selection, `flutter pub get` and `pod install` resolved that setup defect;
neither the setup failure nor the interrupted pre-reboot attempt is presented
as a product test failure.

`wave2-continuation-003/final-original-preservation-audit.json` compares the
reconciled checkout against the 2026-09-27 original-file baseline. All 282
baseline `integration_test` regular files, including 42 harnesses and the five
Wave 2 original harnesses, match byte-for-byte; no protected baseline file is
missing and no path is staged. The broader 2,347-file protected scan finds 38
changed original test/wrapper files in this concurrently dirty checkout. Five
whole-file exceptions match the reviewed registration/wrapper changes; the
DTR18 file also contains a separate application-root fingerprint change beyond
the two approved Wave 2 bootstrap fingerprints. The remaining 33 whole-file
differences are listed in the audit and are not silently certified by Wave 2.
This scoped audit supports preservation of the Wave 2 originals, while a
global dirty-tree original-file claim remains unproved.

The first full host run's one UP-012 batch failure remains in
`host-all-final-003.log`; the exact case, its full 91-test file and the complete
18,334-test Dart rerun passed separately. The previously recorded Plan 371
eight-method iOS result, Plan 374 Android native result and four passing Android
campaigns remain separate receipts. The broad `--base
06d5ab5704cf0106e730f0dab17b0abfd645fe7c --local` affected selection has
intentionally unrun unrelated dirty-tree checks; the one-campaign wrapper's
overall status cannot be read as a full-selection pass. The final preview in
`wave2-continuation-003/final-change-plan-001/` selected 173 checks and listed
789 unmapped changes across the much wider dirty checkout; it did not execute
those checks. `final-adb-devices-001.txt` shows that `adb devices` no longer
listed the earlier `emulator-5554`, so 19 selected device checks had
unavailable-target prerequisites. That later device availability does not
negate the earlier pinned campaign receipts or make unavailable hardware a
failed Wave 2 gate.
For the Wave 2 boundary, the original notification-open, private-media,
routing and sound assertions are accounted for by the four independently
verified integrated-main campaign receipts above. All four passing reports
share SIMS source digest
`82d32bb186b69fea5fe9b77dbf811ca997a47afaa629ff19a2f3e058f43a94fc`;
the sender and provider APKs retain their respective SHA-256 digests
`3b2729fd2b9d9d0330aa827daf8d836687848b460218a37371c56b92d99d5a1e`
and `51e19f1740ac2054c0c257e3acb310184d601b54ba7fc58d007cca8c4bc83211`.
Their build ledgers total two cold builds and four attested cache hits, and
each exact proof's `cleanup.json` verifies restoration of both pinned peers.
The later failed sound repeat retained the same APK digests and two further
attested hits, but its different whole-suite source digest and pre-S16 timeout
are diagnostic only; it is not substituted for the passing 17-case receipt.
The broader dirty-tree selection, whole-file protected inventory differences
and final rollout remain separate obligations, not Wave 2 acceptance passes.
Waves 3–5 remain paused.

## 2026-09-30 Wave 1 device rerun and closure

**WAVE 1 COMPLETE (2026-09-30).** The user asked for the Wave 1 foreground
group-push pilot (`production.foreground_group_push`) to be re-run on the
default Android pair and recorded. The earlier frozen Wave 1 host gate failure
above remains retained; no Wave 1 closure had been recorded before this run.

The run used `docker-ws/run_wave1_foreground_group_push.sh` on the Mac:
`mknoon_checks.py run --mode change --base 06d5ab5704cf0106e730f0dab17b0abfd645fe7c --local --only production-foreground-group-push`
with the Wave 2 device configuration
`wave2-continuation-001/provider-device-config-emulator-5554.json`. Targets were
USB Pixel 6 `21071FDF600CSC` (`android_physical`) and `emulator-5554` (AVD
`Pixel_7`, `android_emulator`).

The first attempt, `production-bootstrap-migration-20260930/wave1-rerun-20260930T141159Z/`,
was `BLOCKED` at `prerequisite_unavailable` (`maestro unavailable`) before any
device step: the host bridge PATH had no Maestro or Java. The wrapper now exports
the same `~/.maestro/bin`, `JAVA_HOME` and Android platform-tools settings as
`docker-ws/beta/beta_env.sh`. No deadline, assertion or selector changed.

| Case | Receipt | Result |
|---|---|---|
| S1 missed live delivery recovered by injected foreground push | `wave1-rerun-20260930T141538Z/`; `build/sims/proofs/production.foreground_group_push/attempt-JUUiKy/` | PASS. Zero messages before; one stored message `a418b358-…` and one notification request with route payload `group:597b5ffa-…\|message:a418b358-…` after. |
| S2 live delivery then push | same | PASS. Two stored messages before and after; notification requests unchanged from the S1 baseline of one. |
| S3 controlled missing-group drain failure | same | PASS. `notificationNeededAfterDrainFailure`, `drainAttempts: 1`, `fallbackShown: false`. |

The wrapper recorded `PASS production-foreground-group-push` at checkpoint
`sims_assertions_and_artifact_observed`, three assertions attempted, SIMS report
SHA-256 `b07923eb52c2133cab6131b35f6a0e8432b8dd81e40eddf0306b964b632beede`,
source digest `ffbbee65cf07d10aa539db80424ec383f369cd7da4d8c64b335f5aa4ad2c9adf`.
Both device preflight probes were idle and the campaign preflight was ready.
The build ledger shows one cold build (78.8 s, one miss, zero hits); the
campaign ran 14:18:18–14:22:05 UTC and the attempt took 355.6 s.
`cleanup.json` reports `PASS` with `exactRestorationVerified: true` for both
devices and package `com.mknoon.sims.connectivity`. The wrapper's overall
`BLOCKED` reflects only the deliberately omitted checks of this `--only` subset.

The host side of Wave 1 is covered by the passing integrated-main `host-all`
at `production-bootstrap-migration-20260928/wave2-continuation-002/host-all-002.log`,
which ran the production journey composition-guard, criteria, runtime and build
contract tests. This rerun did not repeat the host gate, the negative-probe
mutations or the original iOS simulator comparison route; the original harness
remains retained and unchanged. Waves 3–5 remain paused.

## 2026-09-30 Wave 3 device run — implemented group modules

At the user's request all local changes were first committed on local branch
`wave3-baseline-20260930` as `c4b38285fc54bc8a8ea60ecbaf620603a636953e`
(local device-run output was added to `.gitignore`; nothing was pushed; `main`
stays at `06d5ab5704cf0106e730f0dab17b0abfd645fe7c`).

The five implemented Wave 3 campaigns then ran through
`docker-ws/run_wave3_group_campaigns.sh`:
`mknoon_checks.py run --mode change --base 06d5ab5704cf0106e730f0dab17b0abfd645fe7c --local --only production-group-invites,production-group-create,production-group-reaction,production-group-reaction-toggle,production-group-removed-reaction`
with the ignored three-Android configuration
`production-bootstrap-migration-20260930/wave3-device-config.json`: USB Pixel 6
`21071FDF600CSC` (`android_physical`), `emulator-5554` AVD `Pixel_7`
(`android_emulator`) and `emulator-5556` AVD `Pixel_6a`
(`android_emulator_second`). A first attempt, `wave3-run-20260930T150250Z/`,
stopped before any device step with `Unknown/unselected --only check` because
`--base` was the new baseline commit and selected nothing; the wrapper now uses
`main` as the base, as Waves 1 and 2 did.

Receipts are under `production-bootstrap-migration-20260930/wave3-run-20260930T150355Z/`
(source digest `a862fd37285d51aa69a5571f54472b994e8e3f1427bbb4421e50403c622c36ca`).

| Check | Original catalog obligations | Proof | Result |
|---|---|---|---|
| `production-group-invites` | F decline acknowledgement, C exact invite revocation, D metadata convergence | `build/sims/proofs/production.group_invite_reliability/attempt-NWQVTX/` | PASS, 3 assertions, 232.6 s; cleanup exact on `21071FDF600CSC` + `emulator-5554`. |
| `production-group-create` | ML-001 create/two pending invites/accept/readable joins/exact message; KE-001 initial epoch | `.../production.group_catalog.private_abc_create/attempt-6YZpQ2/` | PASS, 4 assertions, 313.6 s; cleanup exact on all three devices. |
| `production-group-reaction` | PL-009 target send, reaction send outcome, two receiver streams, exact persisted reactions | `.../production.group_catalog.private_reaction_roundtrip/attempt-Sj0QVE/` | PASS, 5 assertions, 318.7 s; cleanup exact on all three. |
| `production-group-reaction-toggle` | RT-001 target send, add/remove/re-add returns, two 500 ms intervals, two receiver removal streams, exact final SQL | `.../production.group_catalog.private_reaction_toggle_convergence/attempt-9eIMQq/` | PASS, 5 assertions, 297.7 s; cleanup exact on all three. |
| `production-group-removed-reaction` | PL-010 target send, UI member removal, former-member rejection, five-second receiver absence, exact empty reaction rows | `.../production.group_catalog.private_removed_reaction_rejected/attempt-bg2xfQ/` | PASS, 5 assertions, 326.2 s; cleanup exact on all three. |

Each campaign reached `sims_assertions_and_artifact_observed` with zero builds
and one attested build-cache hit. Total wall time was 1,555.9 s. The wrapper's
overall `BLOCKED` reflects only the deliberately omitted checks of this `--only`
subset. This closes the pending device proof for PL-009 and RT-001 recorded in
"Incremental multi-party reaction replacements". It does not close Wave 3: the
group smoke, invite/status matrix and lifecycle replacements, the remaining
multi-party catalog cases, the replacement-module regression guard and the
wave-boundary `host-all` remain open. Original harnesses and selectors are
unchanged; no route is retired.

## 2026-09-30 Wave 3 invite-status matrix replacement

The original `group_invite_status_matrix_harness.dart` is a display proof: it
renders `GroupInfoWired` over in-memory fakes and seeded rows and records
`relayLifecycleProof: false`. With the user's choice (seed the real app
database), the replacement keeps that boundary but runs the production app:

- `lib/debug/production_journeys/production_group_invite_matrix_controls.dart`
  writes the original eight-member matrix through the production group,
  message and invite-attempt repositories: Admin (the creator device's real
  account), Accepted One (the member device's real account) and six run-owned
  synthetic members `matrix-<run>-<slot>`, with the original attempt statuses,
  `missing_secure_key` error, `member_joined` timeline evidence and minute
  offsets (relative to one base time). Accepted Two keeps its stale `sent`
  attempt; the later join evidence is what makes the production projection show
  Joined. No invitation is sent and no service is constructed.
- `integration_test/scripts/run_production_group_invite_status_matrix.dart`
  seeds both devices, reopens them so Orbit lists the group, and drives
  ordinary UI with Maestro: `production_group_open` then
  `production_group_invite_matrix` (creator) and `production_group_info_self`
  (member).
- The creator flow asserts each member name is followed, after its role line,
  by the expected label: Joined ×2, Invite sent, In their inbox, Resend needed,
  Cannot send with the original secure-info explanation, and Invite unknown.
  The member flow asserts `You`. The badge has no accessibility identifier, so
  the flows match the merged Members node text, as the existing revoke flow does.
- `tool/sims/production_group_invite_matrix_criteria.dart` (16 tests) requires
  the exact seeded rows on both devices, the stale-attempt ordering, foreground
  lifecycle, exact ordered flows, and rows unchanged through the UI check.

Host: analysis clean; 92 focused tests passed; curated `workflow`,
`production-journey-contracts`, `maestro-flow-contracts`, `runtime-roots`,
`group-media-schema-contract`, `notification-payload-harness-contract` and
`notifications` passed (`production-bootstrap-migration-20260930/matrix-host-20260930T155149Z/`).

Device (USB Pixel 6 `21071FDF600CSC` creator, `emulator-5554` Pixel_7 member):
`wave3-run-20260930T155613Z/` PASS, two cases, oracle `failures: []`, one
build, 232.8 s; proof `build/sims/proofs/production.group_invite_status_matrix/attempt-PCoVbr/`;
both Maestro flows `SUCCESS`; `cleanup.json` exact on both devices.

Negative probe: the creator flow was temporarily changed to expect
`In their inbox` for Sent Member. `wave3-run-20260930T160110Z/` FAILED at
exactly that assertion (`attempt-3lGnow/`, earlier Joined assertions passed,
cleanup exact); the flow file was restored byte-for-byte afterwards.

Like the original, this does not prove relay delivery; invite delivery
lifecycle stays with the invitation and catalog journeys. Group smoke needs no
new module: G1–G8 are already covered by the Wave 2 routing replacement (row
updated above).

## 2026-09-30 Wave 3 delete-preserves-friends replacement

First production child of the lifecycle dispatcher (`GROUP_SIM_SCENARIO=DELETE_PRESERVES_FRIENDS`).
The original drives `OrbitWired` over in-memory fakes: Bob has friends Alice
and Charlie with two 1:1 messages each and a group with two messages; he swipes
the group row, taps Leave and confirms; the group and its messages are purged,
contacts and 1:1 message ids are intact, one leave broadcast is issued, and
both 1:1 chats still render.

The replacement `production.group_delete_preserves_friends` runs the same user
story on three real accounts (USB Pixel 6 Alice/admin, `emulator-5554` Pixel_7
Bob, `emulator-5556` Pixel_6a Charlie):

- The group is a prerequisite prepared with the existing production fixture
  controls (`prepare_group`, `import_group`, `mark_fixture_joined`), named
  `Game Night <run>`. All four 1:1 messages and both group messages are real
  Maestro UI sends.
- Bob deletes through ordinary Orbit UI (`production_orbit_group_leave_delete`:
  swipe left, Leave, Leave & Delete, row disappears, both friend rows remain)
  and then opens each 1:1 chat and sees both messages
  (`production_direct_assert_two`).
- The read-only `delete_snapshot` control (`production_group_delete_controls.dart`)
  proves on Bob: group and group messages purged; contacts and every 1:1
  message id and text unchanged. The original's single leave broadcast is
  proven on the receiving side instead: Alice's production roster drops Bob.
- `tool/sims/production_group_delete_criteria.dart` (16 tests).

Host: analysis clean; 89 focused tests; the seven curated host checks passed
(`delete-host-20260930T161111Z/`).

Device: `wave3-run-20260930T161509Z/` PASS, oracle `failures: []`, 617.8 s,
one build; proof `build/sims/proofs/production.group_delete_preserves_friends/attempt-zNIYz1/`
(23 Maestro flows); waits beforeDelete 220 ms, afterDelete 209 ms, adminAfter
325 ms; cleanup exact on all three devices.

Negative probe: the leave flow was run without the swipe and Leave taps. The
run FAILED at `orbit.group.<id> is not visible` (`attempt-2r0Rdn/`, cleanup
exact); the flow file was restored byte-for-byte.

## 2026-09-30 Wave 3 invite-accept-spinner replacement

Second production child of the lifecycle dispatcher
(`GROUP_SIM_SCENARIO=INVITE_ACCEPT_SPINNER`). The original seeds a pending
invite into `OrbitWired` over fakes, taps Accept and requires within 10 s: the
card and spinner cleared, the group persisted, the pending invite removed, no
SnackBar, and `GroupConversationWired` open.

`production.group_invite_accept_spinner` (USB Pixel 6 Alice, `emulator-5554`
Pixel_7 Bob): Alice creates `Writers Room <run>` through ordinary UI
(`production_group_create`); Bob receives the real invitation, opens Intros,
sees the card and taps Accept (`production_group_invite_accept_spinner`); the
flow requires the joined chat within the original 10 s. The read-only
`accept_snapshot` (`production_group_accept_controls.dart`) reports the
run-owned pending invite, the persisted group and, like the original's widget
finders, the mounted `SnackBar` and `GroupConversationWired` counts from the
live element tree. `tool/sims/production_group_accept_criteria.dart` (14 tests).
The original's fake-bridge hang reproduction mode is not replicated.

Host: analysis clean; focused tests passed; the seven curated host checks
passed. Device: `wave3-run-20260930T164240Z/` PASS, oracle `failures: []`;
invite arrived in 981 ms; after Accept 0 SnackBars, 1 group conversation,
pending cleared, group persisted with role member; proof
`build/sims/proofs/production.group_invite_accept_spinner/attempt-JhRSSq/`;
cleanup exact on both devices.

Negative probe: the flow without the Accept tap FAILED at
`id: chat_composer is visible` (`wave3-run-20260930T164704Z/`,
`attempt-4BijSH/`, cleanup exact); the flow file was restored byte-for-byte.

## 2026-09-30 Wave 3 new-member-media replacement

Third production child of the lifecycle dispatcher
(`GROUP_SIM_SCENARIO=NEW_MEMBER_MEDIA`, report 89). The original pumps
`GroupConversationScreen` alone over two seeded messages (Alice's post-join
text+video+voice, Bob's own video+voice) backed by tiny fixture files, then,
initially and after re-pumping: both texts once, two `VideoThumbnailOverlay`,
two `AudioPlayerWidget` showing `0:01`, the first voice enters its pause state
on tap, and the first video opens a `VideoPlayer` without "Could not load video".

`production.group_new_member_media` (USB Pixel 6 Alice identity, `emulator-5554`
Pixel_7 Bob) keeps that display boundary on the production app:

- `production_group_media_controls.dart` writes the same two messages and four
  attachments through the production group message and media attachment
  repositories, with files at the trusted `media/<groupId>/<attachmentId>`
  paths and the video thumbnail sibling. The runner reads the fixture bytes,
  key and nonce from the unchanged original file, so the bytes are identical.
- Maestro opens the group; the voice play control and the video cell have no
  accessibility identifiers, so the runner takes their tap points from the
  pinned device's `uiautomator` hierarchy (inside the incoming bubble: the
  square unlabeled control and the largest cell) and Maestro taps them
  (`production_media_tap_point`), then leaves the viewer
  (`production_media_viewer_back`). The reopen pass restarts the app.
- Read-only element-tree observations mirror the original finders. Text uses
  `find.text` rules (Text data or span, EditableText) and is scoped to the
  open `GroupConversationWired`, because Orbit stays mounted underneath and
  its row previews the latest message; the viewer is observed across the tree.
  Playback is caught by an in-app watcher armed before the tap, since the clip
  lasts one second.
- `tool/sims/production_group_media_criteria.dart` (16 tests).

Exploration and first failures (all with exact cleanup), retained:
`wave3-run-20260930T170053Z/` (tap targets not yet known; saved hierarchy),
`T170419Z/` and `T170840Z/` and `T171421Z/` (text counting did not yet match
`find.text` and the conversation scope; every other assertion passed).

Pass: `wave3-run-20260930T172006Z/` PASS, oracle `failures: []`; both passes
show texts 1/1, thumbnails 2, players 2, durations 2, playback observed,
VideoPlayer 1 and no load error; proof
`build/sims/proofs/production.group_new_member_media/attempt-Q43Szc/`; cleanup exact.

Negative probe: with the tap flow made a no-op, the run FAILED
(`wave3-run-20260930T172442Z/`, `attempt-KC3dj1/`): the watcher recorded
`playingObserved: false` and the viewer wait timed out; cleanup exact; the
flow was restored byte-for-byte.

## 2026-09-30 Wave 3 catalog private_online_remove

User decision (2026-09-30): catalog cases that need exact protocol timing get
narrow **debug-build-only** seams in production paths. The fourth device for
four-peer cases is `emulator-5560` (AVD `Pixel_8`); `emulator-5558`
(`Codex_API35`) is not used.

First seam: `lib/features/groups/application/group_key_distribution_debug_gate.dart`.
`rotateAndDistributeGroupKey` wraps its `sendP2PMessage` with the gate only
when one is set; the getter returns null and the setter throws outside debug
builds (`kDebugMode`), so release/profile builds never run a gate.
`test/features/groups/application/group_key_distribution_debug_gate_test.dart`
(3 tests) proves unchanged sends without a gate, gate-before-send ordering, and
a held recipient; the existing 51 rotation tests still pass.

`production.group_catalog.private_online_remove` (USB Pixel 6 Alice,
`emulator-5554` Bob, `emulator-5556` Charlie) reproduces the original GM-004
online-removal sequence with ML-005, KE-006, KE-007, ST-006 and PL-006:

- UI: create, both accepts, Charlie's removal (`production_catalog_remove_charlie_start`,
  then `..._verify` after the rotation), Bob's two text sends.
- ST-006: the gate holds Alice's rotated-key send to Bob; Bob publishes at
  epoch 1 during the hold and Alice receives it; then the gate is released.
- Narrow production use-case calls with the original payloads: Alice's
  post-removal PL-006 image (bytes read from the unchanged original harness)
  via `uploadMedia` + `sendGroupMessage`, Bob's `downloadMedia`, Charlie's
  rejected `sendGroupMessage` and `callP2PMediaDownload`.
- `tool/sims/production_group_online_remove_criteria.dart` checks the
  production intermediate stages, builds the original three role verdicts
  from observations and runs the unchanged `evaluateGroupMultiPartyVerdicts`
  (18 tests; the valid fixture passes the original oracle).

Device: the first attempt `wave3-run-20260930T174236Z/` FAILED before the
rotation: the app refused the removal with "Group recovery is in progress"
because the runner removed while post-accept recovery was active; cleanup
exact. The runner now waits for `groupRecoveryActive: false` on all peers.
`wave3-run-20260930T175042Z/` PASS, oracle `failures: []`
(`attempt-G7Iupu/`): rotation held at epoch 1 when Alice received Bob's
ST-006 message; Alice and Bob epoch 2, Charlie 0; Alice's media at epoch 2
with allowed peers exactly Alice and Bob; Bob's download done; Charlie's
direct download denied (`not authorized`, 0 bytes), send `groupNotFound`,
zero leaked messages, group retained; cleanup exact on all three devices.

Negative probe (gate not armed): three attempts (`T175756Z`, `T180759Z`,
`T181641Z`) failed during device preparation, before any scenario step (one
readiness timeout, then two `emulator-5556` install timeouts). A manual install
of the 321 MB APK on `emulator-5556` then took 2 m 3 s, just over the state
guard's 2-minute host-command limit, after two more emulators were started.
After the user restored emulator conditions, `wave3-run-20260930T184015Z/`
(`attempt-fCEE3n/`) ran the whole scenario unheld and FAILED at the ST-006
checks ("rotation held before Bob publishes, still at epoch 1; Alice received
Bob during the held rotation"). Cleanup was exact each time; the runner was
restored byte-for-byte.

## 2026-09-30 Wave 3 catalog private_relay_only_delivery

NW-002 needs Bob relay-only: at least one role must log a `group:discovery`
route to Bob with `path=relay`, `attemptedDirect=false`, `directAddrCount=0`.

Second debug-only seam, in Go and Dart:
- `go-mknoon/node/feature_flags.go` `DebugAdvertiseRelayOnly`
  (`debugAdvertiseRelayOnly`, default false, handled by
  `MergeFeatureFlagsOverDefaults` and reported by `featureFlagsStatusMap`);
  `node.go` then advertises only relay-circuit addresses (`relayOnlyAddresses`).
  Go tests: `node/relay_only_addresses_test.go` plus the existing
  every-field-mergeable guard, which caught the first missing merge case.
- `lib/core/bridge/debug_node_feature_flags.dart`: a debug-only override map
  (empty and unsettable outside debug builds) merged into
  `defaultResilienceFeatureFlags()`; `ProductionJourneyController` sets it only
  for Bob in this journey. `test/core/bridge/debug_node_feature_flags_test.dart`.

`production.group_catalog.private_relay_only_delivery` (USB Pixel 6 Alice,
`emulator-5554` Bob, `emulator-5556` Charlie): UI create, accepts, Alice's send
and Bob's publish-back. `production_group_catalog_watch_controls.dart` captures
the app's own sanitized `GROUP_DISCOVERY` and send flow events;
`tool/sims/production_group_relay_only_criteria.dart` rebuilds the route
diagnostics with a faithful copy of the original `_nw002*` helpers, adds a
production check that only Bob's node advertises relay-only, and runs the
unchanged original oracle (14 tests).

Production precondition not in the original: the contact exchange already
connects everyone over Bob's relay circuit, so group discovery never dials
Bob. After the group settles, Alice and Charlie are restarted normally so their
group rejoin runs discovery against the real members; Alice then sends through
`production_group_send`.

Attempts (all with exact cleanup), retained:
- `wave3-run-20260930T185507Z/` FAIL, no seam: Bob advertised 2 direct
  addresses; Alice reached him by `relay_fallback` after a direct attempt.
- `T192504Z` FAIL: seam present but not yet reported by `featureFlagsStatusMap`.
- `T193319Z` FAIL: Bob relay-only, but no discovery dial targeted him.
- `T194127Z` **PASS**, oracle `failures: []` (`attempt-hoz3GV/`): Alice and
  Charlie reached Bob with `relay`/`attemptedDirect=false`/`directAddrCount=0`;
  every other pair used `relay_fallback` after direct attempts.
- Negative probe `T194841Z` (`attempt-k7O0v7/`, seam off, controller restored
  byte-for-byte): FAILED at "relay-only advertising only on Bob". On that run's
  events the original NW-002 rule alone would have passed (right after a
  restart a peer can briefly see Bob with no known direct addresses), so the
  added advertising check is what makes the relay-only claim sound.

Host: focused Dart tests (124) and Go tests pass; curated `workflow`,
`production-journey-contracts`, `maestro-flow-contracts`, `runtime-roots` and
`notifications` passed. `go-core` ran 1,909 tests with 0 failures and 2
pre-existing skips and is classified BLOCKED by its own "skips remain
incomplete" rule; neither skip is from this change.

## 2026-10-01 Wave 3 catalog private_process_death_matrix

`production.group_catalog.private_process_death_matrix` (ST-007; USB Pixel 6
Alice, `emulator-5554` Bob, `emulator-5556` Charlie) reproduces the original
sequence with real UI: Alice creates the group with Bob, adds Charlie from
Group Info (Charlie accepts the invitation), removes Charlie, and re-adds him.
Charlie is killed right after the add is persisted, Bob right after the
removal is persisted, and Charlie again after the re-add, each with the
journey's verified owned-UID `kill -9` and an ordinary relaunch; recovery,
removed-window exclusion and post-restart delivery are observed read-only.
`tool/sims/production_group_process_death_criteria.dart` (12 tests) carries the
original checkpoint/killed-role catalog verbatim and feeds the unchanged
original oracle; received entries are taken at receipt time, as the original
records them.

New production accessibility identifier: Group Info's Add Member button is now
`Semantics(identifier: 'group-info-add-member', button: true)` (its text was
merged into the Members node and could not be targeted), with
`test/features/groups/presentation/widgets/group_info_add_member_accessibility_test.dart`;
the five existing Group Info test files (28 tests) still pass.

Findings and runner measures, all retained as attempts with exact cleanup:
- `wave3-run-20261001T070820Z`: Add Member not targetable (fixed by the
  identifier above).
- `T072202Z` and `T073934Z`: the app refused the add/remove with "Group
  recovery is in progress". The refusal gate is also held by background work
  such as the pending-message retrier (`pending_message_retrier.dart:783`), so
  real users can be refused at random; this is recorded as a product finding.
  The runner waits for a quiet group (every invite attempt joined and recovery
  inactive for three consecutive seconds) and retries a refused edit the way a
  user would, at most three times, recording each retry.
- `T072857Z` and `T074823Z`: the USB Pixel's SwiftKey autocorrected the
  original text ("readd" became "read"). `T075851Z`: switching the whole run
  to the Appium keyboard broke `hideKeyboard` (it pressed Back). Final measure:
  for each proof send only, the device is switched to the installed Appium
  keyboard (verbatim, no on-screen keyboard), sends through
  `production_verbatim_send`, and its own keyboard is restored immediately;
  `emulator-5556` has no Appium keyboard and uses its own with the same exact
  composer check. Every switch is recorded; keyboards were verified restored.

Pass: `wave3-run-20261001T080438Z/` PASS, oracle `failures: []`
(`attempt-cvPXUe/`): kills `charlie:add`, `bob:remove`, `charlie:readd` all
verified; no membership-edit retries needed; cleanup exact on all three devices.

Negative probe: without Bob's kill at the removal checkpoint the run FAILED at
"bob:remove: verified owned-process kill" (`T081521Z`, `attempt-dtJrUv/`);
cleanup exact, runner restored byte-for-byte, keyboards restored.
