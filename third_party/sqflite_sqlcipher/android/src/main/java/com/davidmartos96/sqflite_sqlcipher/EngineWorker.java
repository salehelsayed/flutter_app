package com.davidmartos96.sqflite_sqlcipher;

/** One serial execution lane owned by one Flutter plugin instance. */
interface EngineWorker {
    /** Returns false after shutdown admission has closed. */
    boolean post(Runnable task);

    /**
     * Runs cleanup after every previously admitted task, terminates the lane,
     * and invokes {@code onTerminated} only after thread termination is joined.
     */
    void shutdownAfterDrain(Runnable cleanup, Runnable onTerminated);
}
