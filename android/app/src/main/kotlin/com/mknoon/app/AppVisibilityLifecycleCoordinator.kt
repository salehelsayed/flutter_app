package com.mknoon.app

internal class AppVisibilityLifecycleCoordinator(
    private val store: AppVisibilitySnapshotStore,
) {
    fun onLaunch(): AppVisibilityCommitEnvelope = store.transitionLifecycle(
        AppVisibilityLifecycle.INACTIVE,
        force = true,
    )

    fun onResume(): AppVisibilityCommitEnvelope = store.transitionLifecycle(
        AppVisibilityLifecycle.FOREGROUND_ACTIVE,
    )

    fun onPause(): AppVisibilityCommitEnvelope = store.transitionLifecycle(
        AppVisibilityLifecycle.INACTIVE,
    )

    fun onStop(): AppVisibilityCommitEnvelope = store.transitionLifecycle(
        AppVisibilityLifecycle.BACKGROUND,
    )
}
