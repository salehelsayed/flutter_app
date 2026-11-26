# Flutter Secure Storage 9.2.4 Android override

These two Java classes come from the Flutter Secure Storage 9.2.4 package pinned in `pubspec.lock`, under `android/src/main/java/com/it_nomads/fluttersecurestorage/`. The upstream BSD 3-Clause license is included here.

BL-86 makes ordinary write, delete, and delete-all operations wait for `SharedPreferences.Editor.commit()` on the plugin's existing worker thread. If commit returns false, the plugin reports its existing method-channel error and bypasses the opt-in reset path.

BL-86b submits the encrypted migration's metadata cleanup only while a legacy algorithm marker exists. A settled encrypted store can be read repeatedly without adding empty SharedPreferences work for Android to drain at Activity stop.

When upgrading the dependency, compare the upstream Android mutation, reset, and migration paths. Remove the override if upstream covers these behaviors. If the override is still needed, regenerate it from the new upstream sources and update the Gradle version and source checks. Recheck the stop scenario under disk pressure, persisted writes and deletes, metadata cleanup, and the false-commit error with reset enabled.
