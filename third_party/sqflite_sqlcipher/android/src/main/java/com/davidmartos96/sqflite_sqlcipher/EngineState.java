package com.davidmartos96.sqflite_sqlcipher;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Objects;

/** Per-Flutter-engine database ownership and task admission state. */
final class EngineState<H> {
    interface HandleOpener<H> {
        H open(int id) throws Exception;
    }

    interface OpenHandleChecker<H> {
        boolean isOpen(H handle);
    }

    interface HandleCloser<H> {
        boolean close(H handle);
    }

    static final class OpenOutcome<H> {
        final int id;
        final H handle;
        final boolean recovered;

        OpenOutcome(int id, H handle, boolean recovered) {
            this.id = id;
            this.handle = handle;
            this.recovered = recovered;
        }
    }

    private static final class OwnedHandle<H> {
        final int id;
        final String path;
        final boolean singleInstance;
        final H handle;

        OwnedHandle(int id, String path, boolean singleInstance, H handle) {
            this.id = id;
            this.path = path;
            this.singleInstance = singleInstance;
            this.handle = handle;
        }
    }

    private static final class Opening<H> {
        final int id;
        boolean done;
        int waiters;
        H handle;
        Exception error;

        Opening(int id) {
            this.id = id;
        }
    }

    private final Object lock = new Object();
    private final EngineWorker worker;
    private final Map<Integer, OwnedHandle<H>> handles = new HashMap<>();
    private final List<OwnedHandle<H>> closingHandles = new ArrayList<>();
    private final Map<String, Integer> singletonIdsByPath = new HashMap<>();
    private final Map<String, Opening<H>> openingsByPath = new HashMap<>();
    private int nextDatabaseId;
    private boolean detached;
    private boolean terminated;

    EngineState(EngineWorker worker) {
        this.worker = worker;
        EngineDebugCensus.instanceAttached();
    }

    boolean post(Runnable task) {
        synchronized (lock) {
            if (detached) {
                return false;
            }
            return worker.post(task);
        }
    }

    OpenOutcome<H> openOrReuse(
            String path,
            boolean singleInstance,
            HandleOpener<H> opener,
            OpenHandleChecker<H> checker) throws Exception {
        Opening<H> openingToJoin = null;
        int databaseId = 0;

        synchronized (lock) {
            if (singleInstance) {
                Integer existingId = singletonIdsByPath.get(path);
                if (existingId != null) {
                    OwnedHandle<H> existing = handles.get(existingId);
                    if (existing != null && checker.isOpen(existing.handle)) {
                        return new OpenOutcome<>(existing.id, existing.handle, true);
                    }
                    if (removeHandleLocked(existingId) != null) {
                        // The checker established that this native handle had
                        // already closed before its stale ownership entry was
                        // discarded.
                        EngineDebugCensus.handlesClosed(1);
                    }
                }

                openingToJoin = openingsByPath.get(path);
                if (openingToJoin == null) {
                    databaseId = ++nextDatabaseId;
                    openingsByPath.put(path, new Opening<H>(databaseId));
                }
            } else {
                databaseId = ++nextDatabaseId;
            }

            if (openingToJoin != null) {
                openingToJoin.waiters++;
                try {
                    while (!openingToJoin.done) {
                        lock.wait();
                    }
                } finally {
                    openingToJoin.waiters--;
                }
                if (openingToJoin.error != null) {
                    throw openingToJoin.error;
                }
                return new OpenOutcome<>(
                        openingToJoin.id,
                        openingToJoin.handle,
                        true);
            }
        }

        H opened;
        try {
            opened = opener.open(databaseId);
        } catch (Exception error) {
            if (singleInstance) {
                synchronized (lock) {
                    Opening<H> opening = openingsByPath.remove(path);
                    if (opening != null) {
                        opening.error = error;
                        opening.done = true;
                    }
                    lock.notifyAll();
                }
            }
            throw error;
        }

        synchronized (lock) {
            OwnedHandle<H> owned = new OwnedHandle<>(
                    databaseId,
                    path,
                    singleInstance,
                    opened);
            handles.put(databaseId, owned);
            if (singleInstance) {
                singletonIdsByPath.put(path, databaseId);
                Opening<H> opening = openingsByPath.remove(path);
                if (opening != null) {
                    opening.handle = opened;
                    opening.done = true;
                }
                lock.notifyAll();
            }
            EngineDebugCensus.handleOpened();
            return new OpenOutcome<>(databaseId, opened, false);
        }
    }

    H getHandle(int id) {
        synchronized (lock) {
            OwnedHandle<H> owned = handles.get(id);
            return owned == null ? null : owned.handle;
        }
    }

    H removeHandle(int id) {
        synchronized (lock) {
            OwnedHandle<H> removed = removeHandleLocked(id);
            if (removed != null) {
                closingHandles.add(removed);
            }
            return removed == null ? null : removed.handle;
        }
    }

    List<H> removeHandlesForPath(String path) {
        synchronized (lock) {
            List<H> removed = new ArrayList<>();
            for (OwnedHandle<H> closing : closingHandles) {
                if (Objects.equals(closing.path, path)) {
                    removed.add(closing.handle);
                }
            }
            Iterator<Map.Entry<Integer, OwnedHandle<H>>> iterator =
                    handles.entrySet().iterator();
            while (iterator.hasNext()) {
                OwnedHandle<H> owned = iterator.next().getValue();
                if (!Objects.equals(owned.path, path)) {
                    continue;
                }
                iterator.remove();
                if (owned.singleInstance &&
                        Integer.valueOf(owned.id).equals(singletonIdsByPath.get(path))) {
                    singletonIdsByPath.remove(path);
                }
                closingHandles.add(owned);
                removed.add(owned.handle);
            }
            return removed;
        }
    }

    /** Records zero native handles only after the close itself succeeds. */
    boolean closeOwnedHandle(H handle, HandleCloser<H> closer) {
        boolean closed;
        try {
            closed = closer.close(handle);
        } catch (RuntimeException error) {
            closed = false;
        }
        boolean wasOwned = false;
        if (closed) {
            synchronized (lock) {
                Iterator<OwnedHandle<H>> iterator = closingHandles.iterator();
                while (iterator.hasNext()) {
                    if (iterator.next().handle == handle) {
                        iterator.remove();
                        wasOwned = true;
                        break;
                    }
                }
            }
        }
        if (closed && wasOwned) {
            EngineDebugCensus.handlesClosed(1);
        }
        return closed;
    }

    int handleCount() {
        synchronized (lock) {
            return handles.size();
        }
    }

    int openingCount() {
        synchronized (lock) {
            return openingsByPath.size();
        }
    }

    int openingWaiterCount() {
        synchronized (lock) {
            int count = 0;
            for (Opening<H> opening : openingsByPath.values()) {
                count += opening.waiters;
            }
            return count;
        }
    }

    int closingHandleCount() {
        synchronized (lock) {
            return closingHandles.size();
        }
    }

    boolean allowResultDelivery() {
        synchronized (lock) {
            if (!detached) {
                return true;
            }
        }
        EngineDebugCensus.resultSuppressed();
        return false;
    }

    void recordSuppressedResult() {
        EngineDebugCensus.resultSuppressed();
    }

    boolean isDetached() {
        synchronized (lock) {
            return detached;
        }
    }

    boolean isTerminated() {
        synchronized (lock) {
            return terminated;
        }
    }

    void detach(HandleCloser<H> closer) {
        synchronized (lock) {
            if (detached) {
                return;
            }
            detached = true;
            EngineDebugCensus.instanceDetached();
            worker.shutdownAfterDrain(
                    () -> closeAllHandles(closer),
                    () -> {
                        synchronized (lock) {
                            terminated = true;
                        }
                        EngineDebugCensus.instanceTerminated();
                    });
        }
    }

    private void closeAllHandles(HandleCloser<H> closer) {
        List<H> owned;
        synchronized (lock) {
            owned = new ArrayList<>();
            for (OwnedHandle<H> handle : closingHandles) {
                owned.add(handle.handle);
            }
            for (OwnedHandle<H> handle : handles.values()) {
                closingHandles.add(handle);
                owned.add(handle.handle);
            }
            handles.clear();
            singletonIdsByPath.clear();
            for (Opening<H> opening : openingsByPath.values()) {
                opening.error = new IllegalStateException("engine detached during open");
                opening.done = true;
            }
            openingsByPath.clear();
            lock.notifyAll();
        }
        for (H handle : owned) {
            closeOwnedHandle(handle, closer);
        }
        synchronized (lock) {
            // A failed close remains visible in the aggregate native-handle
            // census, but no destroyed engine retains identifiers or handles.
            closingHandles.clear();
        }
    }

    private OwnedHandle<H> removeHandleLocked(int id) {
        OwnedHandle<H> removed = handles.remove(id);
        if (removed == null) {
            return null;
        }
        if (removed.singleInstance &&
                Integer.valueOf(id).equals(singletonIdsByPath.get(removed.path))) {
            singletonIdsByPath.remove(removed.path);
        }
        return removed;
    }
}
