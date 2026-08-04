package com.davidmartos96.sqflite_sqlcipher;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

/** Process-wide aggregate diagnostics. No database or engine identifiers are retained. */
final class EngineDebugCensus {
    private static final AtomicInteger liveInstances = new AtomicInteger();
    private static final AtomicInteger liveWorkers = new AtomicInteger();
    private static final AtomicInteger liveHandles = new AtomicInteger();
    private static final AtomicInteger queuedTasks = new AtomicInteger();
    private static final AtomicInteger runningTasks = new AtomicInteger();
    private static final AtomicInteger detachedInstances = new AtomicInteger();
    private static final AtomicInteger terminatedInstances = new AtomicInteger();
    private static final AtomicInteger suppressedResults = new AtomicInteger();

    private EngineDebugCensus() {
    }

    static void instanceAttached() {
        liveInstances.incrementAndGet();
    }

    static void instanceDetached() {
        detachedInstances.incrementAndGet();
    }

    static void instanceTerminated() {
        decrement(liveInstances);
        terminatedInstances.incrementAndGet();
    }

    static void workerStarted() {
        liveWorkers.incrementAndGet();
    }

    static void workerTerminated() {
        decrement(liveWorkers);
    }

    static void handleOpened() {
        liveHandles.incrementAndGet();
    }

    static void handlesClosed(int count) {
        addNegative(liveHandles, count);
    }

    static void taskQueued() {
        queuedTasks.incrementAndGet();
    }

    static void taskDequeued() {
        decrement(queuedTasks);
        runningTasks.incrementAndGet();
    }

    static void taskFinished() {
        decrement(runningTasks);
    }

    static void taskRejectedBeforeRun() {
        decrement(queuedTasks);
    }

    static void resultSuppressed() {
        suppressedResults.incrementAndGet();
    }

    static Map<String, Object> snapshot() {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("liveInstances", liveInstances.get());
        result.put("liveWorkers", liveWorkers.get());
        result.put("liveHandles", liveHandles.get());
        result.put("queuedTasks", queuedTasks.get());
        result.put("runningTasks", runningTasks.get());
        result.put("detachedInstances", detachedInstances.get());
        result.put("terminatedInstances", terminatedInstances.get());
        result.put("suppressedResults", suppressedResults.get());
        return result;
    }

    static void resetForTests() {
        liveInstances.set(0);
        liveWorkers.set(0);
        liveHandles.set(0);
        queuedTasks.set(0);
        runningTasks.set(0);
        detachedInstances.set(0);
        terminatedInstances.set(0);
        suppressedResults.set(0);
    }

    private static void addNegative(AtomicInteger value, int count) {
        if (count <= 0) {
            return;
        }
        value.addAndGet(-count);
    }

    private static void decrement(AtomicInteger value) {
        addNegative(value, 1);
    }
}
