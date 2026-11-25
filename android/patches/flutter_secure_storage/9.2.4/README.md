# Flutter Secure Storage 9.2.4 Android override

These two Java classes come from the Flutter Secure Storage 9.2.4 package pinned in `pubspec.lock`, under `android/src/main/java/com/it_nomads/fluttersecurestorage/`. The upstream BSD 3-Clause license is included here.

BL-86 makes ordinary write, delete, and delete-all operations wait for `SharedPreferences.Editor.commit()` on the plugin's existing worker thread. If commit returns false, the plugin reports its existing method-channel error and bypasses the opt-in reset path.

When upgrading the dependency, compare the upstream Android mutation and reset paths, then remove the override if upstream covers both behaviors. If the override is still needed, regenerate it from the new upstream sources and update the Gradle version and source checks. Recheck the stop scenario under disk pressure, persisted writes and deletes, and the false-commit error with reset enabled.
