package com.mknoon.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executor
import java.util.concurrent.Executors

internal class AppVisibilityLifecycleCoordinator private constructor(
    createStore: () -> AppVisibilitySnapshotStore,
    private val executor: Executor,
    private val replyExecutor: Executor,
) {
    constructor(
        store: AppVisibilitySnapshotStore,
        executor: Executor = newStoreExecutor(),
        replyExecutor: Executor = mainReplyExecutor(),
    ) : this({ store }, executor, replyExecutor)

    companion object {
        private var processCoordinator: AppVisibilityLifecycleCoordinator? = null

        @Synchronized
        fun get(context: Context): AppVisibilityLifecycleCoordinator {
            processCoordinator?.let { return it }
            val applicationContext = context.applicationContext
            return AppVisibilityLifecycleCoordinator(
                createStore = { AppVisibilitySnapshotStore(applicationContext) },
                executor = newStoreExecutor(),
                replyExecutor = mainReplyExecutor(),
            ).also { processCoordinator = it }
        }

        private fun newStoreExecutor(): Executor = Executors.newSingleThreadExecutor { task ->
            Thread(task, "mknoon-app-visibility").apply { isDaemon = true }
        }

        private fun mainReplyExecutor(): Executor {
            val handler = Handler(Looper.getMainLooper())
            return Executor { handler.post(it) }
        }
    }

    private class LifecycleRequest(
        val owner: Any,
        val lifecycle: AppVisibilityLifecycle,
    ) {
        @Volatile
        var completion: LifecycleCompletion? = null

        // Lifecycle callbacks, channel handlers and replies access this on the main looper.
        val pendingReplyCancellations = mutableSetOf<() -> Unit>()
    }

    private class LifecycleCompletion(val generation: Long?)

    private val store by lazy(LazyThreadSafetyMode.NONE, createStore)

    @Volatile
    private var currentRequest: LifecycleRequest? = null

    fun onLaunch(owner: Any = this) = transition(
        owner,
        AppVisibilityLifecycle.INACTIVE,
        force = true,
    )

    fun onResume(owner: Any = this) = transition(
        owner,
        AppVisibilityLifecycle.FOREGROUND_ACTIVE,
    )

    fun onPause(owner: Any = this) = transition(
        owner,
        AppVisibilityLifecycle.INACTIVE,
    )

    fun onStop(owner: Any = this) = transition(
        owner,
        AppVisibilityLifecycle.BACKGROUND,
    )

    private fun transition(owner: Any, lifecycle: AppVisibilityLifecycle, force: Boolean = false) {
        val previous = currentRequest
        val ownerChanged = previous != null && previous.owner !== owner
        if (ownerChanged && !force && lifecycle != AppVisibilityLifecycle.FOREGROUND_ACTIVE) return
        val request = LifecycleRequest(owner, lifecycle)
        // This invalidates the previous generation before Flutter sees the edge.
        currentRequest = request
        executor.execute {
            val commit = try {
                // A new owner cannot inherit another Activity's foreground digest.
                store.transitionLifecycle(lifecycle, force = force || ownerChanged)
            } catch (_: RuntimeException) {
                null
            }
            request.completion = LifecycleCompletion(
                commit?.takeIf { it.committed }?.snapshot?.lifecycleGeneration,
            )
        }
        if (previous != null) {
            val cancellations = previous.pendingReplyCancellations.toList()
            previous.pendingReplyCancellations.clear()
            cancellations.forEach { it() }
        }
    }

    fun readSnapshot(
        owner: Any = this,
        isAttached: () -> Boolean = { true },
        reply: (AppVisibilityReadEnvelope?) -> Unit,
    ) {
        val request = currentRequest
        if (!isAttached() || request == null || request.owner !== owner || !request.canRead()) {
            reply(null)
            return
        }
        submit(request, isAttached, reply) { generation ->
            store.readSnapshot()?.takeIf {
                it.snapshot.lifecycle == request.lifecycle &&
                    it.snapshot.lifecycleGeneration == generation
            }
        }
    }

    fun publishVisibleConversation(
        visibleConversationDigest: String?,
        lifecycleGeneration: Long,
        owner: Any = this,
        isAttached: () -> Boolean = { true },
        reply: (AppVisibilityCommitEnvelope?) -> Unit,
    ) {
        val request = currentRequest
        if (
            !isAttached() ||
            request == null ||
            request.owner !== owner ||
            request.lifecycle != AppVisibilityLifecycle.FOREGROUND_ACTIVE ||
            !request.canRead()
        ) {
            reply(null)
            return
        }
        submit(request, isAttached, reply) { generation ->
            if (lifecycleGeneration != generation) {
                null
            } else {
                store.publishVisibleConversation(visibleConversationDigest, lifecycleGeneration)
            }
        }
    }

    private fun LifecycleRequest.canRead(): Boolean {
        val completed = completion
        // During pause/stop, fail toward notification without waiting for disk.
        // During resume, the worker can read the new generation once it commits.
        return if (completed == null) {
            lifecycle == AppVisibilityLifecycle.FOREGROUND_ACTIVE
        } else {
            completed.generation != null
        }
    }

    private fun <T> submit(
        request: LifecycleRequest,
        isAttached: () -> Boolean,
        reply: (T?) -> Unit,
        operation: (Long) -> T?,
    ) {
        val cancel = { reply(null) }
        request.pendingReplyCancellations.add(cancel)
        executor.execute {
            val generation = request.completion?.generation
            val value = if (isAttached() && currentRequest === request && generation != null) {
                try {
                    operation(generation)
                } catch (_: RuntimeException) {
                    null
                }
            } else {
                null
            }
            replyExecutor.execute {
                if (request.pendingReplyCancellations.remove(cancel)) {
                    reply(if (isAttached() && currentRequest === request) value else null)
                }
            }
        }
    }
}
