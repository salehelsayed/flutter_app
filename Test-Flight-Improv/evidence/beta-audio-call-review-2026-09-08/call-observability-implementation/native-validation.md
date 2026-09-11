Native observability validation is green on source `f1899f0d63e1724b` (58 verified production inputs).

- Android: **101 native tests passed**, no failures or skips; native calling is enabled in the packaged DEX.
- Swift: **15 host tests passed** using actual source and minimal Flutter type stubs. The actual iOS profile app also compiled successfully (81.9 seconds in Xcode).
- Dart entrypoint: **7 tests passed**, analyzer clean. Final curated gate: **3,544 passed, 4 skipped**, no failures; all 58 production hashes matched before and after.
- Optional headless causes preserve mandatory authority/custody validation. Deferred persistence reports no invented write failure. Native terminal logs use known cause or unknown. Native build stamps are assigned only at creation and survive upgrades unchanged.

| Artifact | Diagnostic fingerprint | SHA256 |
| --- | --- | --- |
| Android debug APK | `58b1ba6035e82327` | `de42656e4aba9e51cccdff78d9d8e06469eedea3ed601105443116ee665526be` |
| iOS profile app tree | `8bc9c8a8e32d3a38` | `0bdb7af7c092ad33d920aecd0819f5841e86f93848f249d15265ab82fb876261` |

Android was built with `--android-project-arg=enableAndroidNativeCalls=true` and all seven call flags. iOS signed APNs environment is `development`. Native-only event build is `1.0.1+111`; Flutter events also carry the platform fingerprint above. Older native events intentionally retain their original or missing build field.

The earlier native-disabled Android lab package omitted the existing Gradle enable flag. That packaging error is preserved as historical evidence and is not attributed to the original beta incident or a changed production default.

Final matching-device probe is pending and owned by root. Host/native tests and packaging do not establish media success. Store distribution remains unpublished. Exact commands, hashes, RED/GREEN logs, prior artifacts, and limits are in [native-validation.json](native-validation.json) and [final-native-cause-validation.json](final-native-cause-validation.json).
