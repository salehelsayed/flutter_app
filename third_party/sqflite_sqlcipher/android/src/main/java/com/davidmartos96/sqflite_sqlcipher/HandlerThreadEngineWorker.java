package com.davidmartos96.sqflite_sqlcipher;

import android.os.Handler;
import android.os.HandlerThread;

import java.util.function.IntSupplier;

/** Android HandlerThread-backed implementation of one engine-owned FIFO. */
final class HandlerThreadEngineWorker implements EngineWorker {
    private static final String WORKER_THREAD_NAME = "SqfliteEngine";
    private static final String REAPER_THREAD_NAME = "SqfliteEngineReaper";

    private final Object lock = new Object();
    private final IntSupplier prioritySupplier;
    private HandlerThread handlerThread;
    private Handler handler;
    private boolean shutdownRequested;

    HandlerThreadEngineWorker(IntSupplier prioritySupplier) {
        this.prioritySupplier = prioritySupplier;
    }

    @Override
    public boolean post(Runnable task) {
        synchronized (lock) {
            if (shutdownRequested) {
                return false;
            }
            ensureStartedLocked();
            return postLocked(task);
        }
    }

    @Override
    public void shutdownAfterDrain(Runnable cleanup, Runnable onTerminated) {
        HandlerThread threadToJoin;
        synchronized (lock) {
            if (shutdownRequested) {
                return;
            }
            shutdownRequested = true;
            if (handlerThread == null) {
                cleanup.run();
                onTerminated.run();
                return;
            }
            threadToJoin = handlerThread;
            if (!postLocked(() -> {
                try {
                    cleanup.run();
                } finally {
                    threadToJoin.quitSafely();
                }
            })) {
                throw new IllegalStateException("Could not enqueue engine worker shutdown");
            }
        }

        Thread reaper = new Thread(() -> {
            boolean interrupted = false;
            while (true) {
                try {
                    threadToJoin.join();
                    break;
                } catch (InterruptedException ignored) {
                    interrupted = true;
                }
            }
            synchronized (lock) {
                if (handlerThread == threadToJoin) {
                    handler = null;
                    handlerThread = null;
                }
            }
            EngineDebugCensus.workerTerminated();
            onTerminated.run();
            if (interrupted) {
                Thread.currentThread().interrupt();
            }
        }, REAPER_THREAD_NAME);
        reaper.setDaemon(true);
        reaper.start();
    }

    private void ensureStartedLocked() {
        if (handlerThread != null) {
            return;
        }
        handlerThread = new HandlerThread(
                WORKER_THREAD_NAME,
                prioritySupplier.getAsInt());
        handlerThread.start();
        handler = new Handler(handlerThread.getLooper());
        EngineDebugCensus.workerStarted();
    }

    private boolean postLocked(Runnable task) {
        EngineDebugCensus.taskQueued();
        boolean accepted = handler.post(() -> {
            EngineDebugCensus.taskDequeued();
            try {
                task.run();
            } finally {
                EngineDebugCensus.taskFinished();
            }
        });
        if (!accepted) {
            EngineDebugCensus.taskRejectedBeforeRun();
        }
        return accepted;
    }
}
