# Android manifest check recovery

Both original checks independently rebuilt the same generated Android AAR in
parallel. Renderer failed to rename the shared `GoMknoon.inputs.sha256.tmp`;
dropped-push failed with ZIP error `invalid bit length repeat`. Full ZIP checking
confirmed the generated AAR was corrupt. Both original Gradle logs were saved.

Recovery changed generated artifacts only. After both wrappers had exited, the
ignored input stamp was backed up and the existing
`bash scripts/ensure_go_android_bindings.sh` rebuilt the AAR once with Go 1.25.0.
The build exited **0**. Full ZIP validation passed, including `classes.jar` and
JNI libraries for arm64-v8a, armeabi-v7a, x86, and x86_64.

Final AAR SHA-256:
`f6c16f714b2b49cf7ee4c70bbb71df542ffdfe98e2fc7b336588f6b1e07f78fa`.

The checks then ran sequentially:

- Renderer: **exit 0**, profile/release manifest assertions passed; Gradle 18s.
- Dropped-push: **exit 0**, messaging ownership/receiver assertions passed; Gradle 6s.

See `core-android-renderer-contract-final.log`,
`core-dropped-push-contract-final.log`, and `android-aar-recovery-zip-check.log`.
The AAR's ZIP integrity and unchanged hash were verified again after both checks.
No source files were edited and no processes were killed.
