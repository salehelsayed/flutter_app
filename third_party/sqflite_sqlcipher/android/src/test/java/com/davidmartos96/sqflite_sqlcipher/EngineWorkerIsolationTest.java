package com.davidmartos96.sqflite_sqlcipher;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNotSame;
import static org.junit.Assert.assertSame;
import static org.junit.Assert.assertTrue;

import org.junit.After;
import org.junit.Before;
import org.junit.Test;

import com.davidmartos96.sqflite_sqlcipher.dev.Debug;

import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

public class EngineWorkerIsolationTest {
    private static final long TIMEOUT_SECONDS = 5L;
    private final List<TestEngineWorker> workers = new ArrayList<>();
    private final List<EngineState<TestHandle>> states = new ArrayList<>();

    @Before
    public void setUp() {
        EngineDebugCensus.resetForTests();
    }

    @After
    public void tearDown() throws Exception {
        for (EngineState<TestHandle> state : states) {
            if (!state.isDetached()) {
                state.detach(TestHandle::close);
            }
        }
        for (TestEngineWorker worker : workers) {
            assertTrue("worker did not terminate", worker.awaitTerminated());
        }
        Map<String, Object> census = EngineDebugCensus.snapshot();
        assertEquals(0, census.get("liveInstances"));
        assertEquals(0, census.get("liveWorkers"));
        assertEquals(0, census.get("liveHandles"));
        assertEquals(0, census.get("queuedTasks"));
        assertEquals(0, census.get("runningTasks"));
    }

    @Test
    public void differentPluginInstancesOwnDistinctWorkersAndMaps() throws Exception {
        EngineState<TestHandle> first = newState();
        EngineState<TestHandle> second = newState();
        AtomicReference<EngineState.OpenOutcome<TestHandle>> firstOpen =
                new AtomicReference<>();
        AtomicReference<EngineState.OpenOutcome<TestHandle>> secondOpen =
                new AtomicReference<>();
        CountDownLatch firstStarted = new CountDownLatch(1);
        CountDownLatch releaseFirst = new CountDownLatch(1);
        CountDownLatch secondCompleted = new CountDownLatch(1);

        assertTrue(first.post(() ->
                firstOpen.set(openUnchecked(first, "/first.db", true))));
        assertTrue(second.post(() ->
                secondOpen.set(openUnchecked(second, "/second.db", true))));
        workers.get(0).awaitIdle();
        workers.get(1).awaitIdle();

        assertEquals(1, firstOpen.get().id);
        assertEquals(1, secondOpen.get().id);
        assertNotEquals(firstOpen.get().handle, secondOpen.get().handle);
        assertEquals(1, first.handleCount());
        assertEquals(1, second.handleCount());

        assertTrue(first.post(() -> {
            firstStarted.countDown();
            awaitUnchecked(releaseFirst);
        }));
        assertTrue(firstStarted.await(TIMEOUT_SECONDS, TimeUnit.SECONDS));
        assertTrue(second.post(secondCompleted::countDown));

        assertTrue(
                "second engine was blocked by the first engine's worker",
                secondCompleted.await(1, TimeUnit.SECONDS));
        releaseFirst.countDown();
    }

    @Test
    public void pluginOptionsAndOwnershipFieldsAreInstanceOwned() {
        assertNoMutableStatics(SqfliteSqlCipherPlugin.class);
        assertNoMutableStatics(EngineState.class);
        assertNoMutableStatics(HandlerThreadEngineWorker.class);
        assertNoMutableStatics(Debug.class);
    }

    @Test
    public void productionPluginInstancesCreateDistinctEngineStatesAndWorkers()
            throws Exception {
        SqfliteSqlCipherPlugin firstPlugin = new SqfliteSqlCipherPlugin();
        SqfliteSqlCipherPlugin secondPlugin = new SqfliteSqlCipherPlugin();
        EngineState<Database> first = firstPlugin.createEngineState();
        EngineState<Database> second = secondPlugin.createEngineState();
        Object firstWorker = readField(first, "worker");
        Object secondWorker = readField(second, "worker");

        assertNotSame(first, second);
        assertTrue(firstWorker instanceof HandlerThreadEngineWorker);
        assertTrue(secondWorker instanceof HandlerThreadEngineWorker);
        assertNotSame(firstWorker, secondWorker);
        assertNotSame(readField(first, "handles"), readField(second, "handles"));

        first.detach(ignored -> true);
        second.detach(ignored -> true);
        assertTrue(first.isTerminated());
        assertTrue(second.isTerminated());
    }

    @Test
    public void sameEngineOperationsRemainFifo() throws Exception {
        EngineState<TestHandle> state = newState();
        List<Integer> order = Collections.synchronizedList(new ArrayList<>());
        CountDownLatch completed = new CountDownLatch(3);

        for (int value = 1; value <= 3; value++) {
            final int captured = value;
            assertTrue(state.post(() -> {
                order.add(captured);
                completed.countDown();
            }));
        }

        assertTrue(completed.await(TIMEOUT_SECONDS, TimeUnit.SECONDS));
        assertEquals(List.of(1, 2, 3), order);
    }

    @Test
    public void concurrentSingletonOpensCoalesceWhileOpening() throws Exception {
        EngineState<TestHandle> state = newState();
        AtomicInteger nativeOpenCount = new AtomicInteger();
        CountDownLatch firstOpenStarted = new CountDownLatch(1);
        CountDownLatch releaseFirstOpen = new CountDownLatch(1);
        AtomicReference<EngineState.OpenOutcome<TestHandle>> first =
                new AtomicReference<>();
        AtomicReference<EngineState.OpenOutcome<TestHandle>> second =
                new AtomicReference<>();
        AtomicReference<Throwable> failure = new AtomicReference<>();

        Thread firstCaller = new Thread(() -> openSingleton(
                state,
                first,
                failure,
                nativeOpenCount,
                firstOpenStarted,
                releaseFirstOpen));
        Thread secondCaller = new Thread(() -> openSingleton(
                state,
                second,
                failure,
                nativeOpenCount,
                firstOpenStarted,
                releaseFirstOpen));

        firstCaller.start();
        assertTrue(firstOpenStarted.await(TIMEOUT_SECONDS, TimeUnit.SECONDS));
        secondCaller.start();
        awaitOpeningWaiter(state);
        releaseFirstOpen.countDown();
        firstCaller.join(TimeUnit.SECONDS.toMillis(TIMEOUT_SECONDS));
        secondCaller.join(TimeUnit.SECONDS.toMillis(TIMEOUT_SECONDS));

        if (failure.get() != null) {
            throw new AssertionError(failure.get());
        }
        assertFalse(firstCaller.isAlive());
        assertFalse(secondCaller.isAlive());
        assertEquals(1, nativeOpenCount.get());
        assertEquals(1, state.handleCount());
        assertEquals(0, state.openingCount());
        assertEquals(first.get().id, second.get().id);
        assertSame(first.get().handle, second.get().handle);
        assertNotEquals(first.get().recovered, second.get().recovered);
    }

    @Test
    public void detachClosesOnlyOwnedHandlesAndSuppressesLateResults()
            throws Exception {
        EngineState<TestHandle> detached = newState();
        EngineState<TestHandle> survivor = newState();
        TestEngineWorker detachedWorker = workers.get(0);
        CountDownLatch admittedStarted = new CountDownLatch(1);
        CountDownLatch releaseAdmitted = new CountDownLatch(1);
        AtomicReference<TestHandle> detachedHandle = new AtomicReference<>();
        AtomicReference<TestHandle> survivorHandle = new AtomicReference<>();

        assertTrue(detached.post(() -> {
            admittedStarted.countDown();
            awaitUnchecked(releaseAdmitted);
            detachedHandle.set(openUnchecked(detached, "/detached.db", true).handle);
        }));
        assertTrue(survivor.post(() ->
                survivorHandle.set(openUnchecked(survivor, "/survivor.db", true).handle)));
        assertTrue(admittedStarted.await(TIMEOUT_SECONDS, TimeUnit.SECONDS));
        workers.get(1).awaitIdle();

        detached.detach(TestHandle::close);
        assertTrue(detached.isDetached());
        assertFalse(detached.post(() -> {
        }));
        assertFalse(detached.allowResultDelivery());
        releaseAdmitted.countDown();
        assertTrue(detachedWorker.awaitTerminated());

        assertTrue(detached.isTerminated());
        assertTrue(detachedHandle.get().closed.get());
        assertEquals(0, detached.handleCount());
        assertFalse(survivorHandle.get().closed.get());
        assertEquals(1, survivor.handleCount());
        assertEquals(1, EngineDebugCensus.snapshot().get("suppressedResults"));
    }

    @Test
    public void closeThenImmediateReopenKeepsNewOpen() throws Exception {
        EngineState<TestHandle> state = newState();
        List<String> order = Collections.synchronizedList(new ArrayList<>());
        AtomicReference<TestHandle> first = new AtomicReference<>();
        AtomicReference<TestHandle> second = new AtomicReference<>();
        CountDownLatch completed = new CountDownLatch(3);

        assertTrue(state.post(() -> {
            first.set(openUnchecked(state, "/ordered.db", true).handle);
            order.add("open-1");
            completed.countDown();
        }));
        assertTrue(state.post(() -> {
            TestHandle removed = state.removeHandle(first.get().id);
            assertTrue(state.closeOwnedHandle(removed, TestHandle::close));
            order.add("close");
            completed.countDown();
        }));
        assertTrue(state.post(() -> {
            second.set(openUnchecked(state, "/ordered.db", true).handle);
            order.add("open-2");
            completed.countDown();
        }));

        assertTrue(completed.await(TIMEOUT_SECONDS, TimeUnit.SECONDS));
        assertEquals(List.of("open-1", "close", "open-2"), order);
        assertTrue(first.get().closed.get());
        assertFalse(second.get().closed.get());
        assertNotEquals(first.get().id, second.get().id);
        assertSame(second.get(), state.getHandle(second.get().id));
        assertEquals(1, state.handleCount());
    }

    @Test
    public void deleteADoesNotStopEngineB() throws Exception {
        EngineState<TestHandle> first = newState();
        EngineState<TestHandle> second = newState();
        AtomicReference<TestHandle> deleted = new AtomicReference<>();
        AtomicReference<TestHandle> reopened = new AtomicReference<>();
        AtomicReference<TestHandle> survivor = new AtomicReference<>();
        CountDownLatch completed = new CountDownLatch(5);

        assertTrue(first.post(() -> {
            deleted.set(openUnchecked(first, "/engine-a.db", true).handle);
            completed.countDown();
        }));
        assertTrue(second.post(() -> {
            survivor.set(openUnchecked(second, "/engine-b.db", true).handle);
            completed.countDown();
        }));
        assertTrue(first.post(() -> {
            for (TestHandle removed : first.removeHandlesForPath("/engine-a.db")) {
                assertTrue(first.closeOwnedHandle(removed, TestHandle::close));
            }
            completed.countDown();
        }));
        assertTrue(first.post(() -> {
            reopened.set(openUnchecked(first, "/engine-a.db", true).handle);
            completed.countDown();
        }));
        assertTrue(second.post(completed::countDown));

        assertTrue(completed.await(TIMEOUT_SECONDS, TimeUnit.SECONDS));
        assertTrue(deleted.get().closed.get());
        assertFalse(reopened.get().closed.get());
        assertFalse(survivor.get().closed.get());
        assertEquals(1, first.handleCount());
        assertEquals(1, second.handleCount());
        assertSame(survivor.get(), second.getHandle(survivor.get().id));
    }

    @Test
    public void failedCloseDoesNotReportZeroNativeHandles() throws Exception {
        EngineState<TestHandle> state = newState();
        AtomicReference<TestHandle> opened = new AtomicReference<>();

        assertTrue(state.post(() ->
                opened.set(openUnchecked(state, "/close-failure.db", false).handle)));
        workers.get(0).awaitIdle();

        TestHandle removed = state.removeHandle(opened.get().id);
        assertFalse(state.closeOwnedHandle(removed, ignored -> false));
        assertEquals(1, state.closingHandleCount());
        assertEquals(1, EngineDebugCensus.snapshot().get("liveHandles"));

        List<TestHandle> deleteRetry =
                state.removeHandlesForPath("/close-failure.db");
        assertEquals(List.of(removed), deleteRetry);
        assertTrue(state.closeOwnedHandle(deleteRetry.get(0), TestHandle::close));
        assertEquals(0, state.closingHandleCount());
        assertEquals(0, EngineDebugCensus.snapshot().get("liveHandles"));
    }

    @Test
    public void zeroCensusAcknowledgesBothTerminatedInstances() throws Exception {
        EngineState<TestHandle> first = newState();
        EngineState<TestHandle> second = newState();
        assertTrue(first.post(() -> openUnchecked(first, "/first.db", false)));
        assertTrue(second.post(() -> openUnchecked(second, "/second.db", false)));
        workers.get(0).awaitIdle();
        workers.get(1).awaitIdle();

        first.detach(TestHandle::close);
        second.detach(TestHandle::close);
        assertTrue(workers.get(0).awaitTerminated());
        assertTrue(workers.get(1).awaitTerminated());

        Map<String, Object> census = EngineDebugCensus.snapshot();
        assertEquals(0, census.get("liveInstances"));
        assertEquals(0, census.get("liveWorkers"));
        assertEquals(0, census.get("liveHandles"));
        assertEquals(0, census.get("queuedTasks"));
        assertEquals(0, census.get("runningTasks"));
        assertEquals(2, census.get("detachedInstances"));
        assertEquals(2, census.get("terminatedInstances"));
    }

    private EngineState<TestHandle> newState() {
        TestEngineWorker worker = new TestEngineWorker();
        EngineState<TestHandle> state = new EngineState<>(worker);
        workers.add(worker);
        states.add(state);
        return state;
    }

    private static void assertNoMutableStatics(Class<?> type) {
        for (Field field : type.getDeclaredFields()) {
            int modifiers = field.getModifiers();
            if (!Modifier.isStatic(modifiers)) {
                continue;
            }
            boolean immutableConstant = Modifier.isFinal(modifiers) &&
                    (field.getType().isPrimitive() || field.getType() == String.class);
            assertTrue(
                    type.getSimpleName() + "." + field.getName() +
                            " must not be mutable process-static ownership",
                    immutableConstant);
        }
    }

    private static Object readField(Object target, String name) throws Exception {
        Field field = target.getClass().getDeclaredField(name);
        field.setAccessible(true);
        return field.get(target);
    }

    private static EngineState.OpenOutcome<TestHandle> openUnchecked(
            EngineState<TestHandle> state,
            String path,
            boolean singleInstance) {
        try {
            return state.openOrReuse(
                    path,
                    singleInstance,
                    id -> new TestHandle(id, path),
                    handle -> !handle.closed.get());
        } catch (Exception error) {
            throw new AssertionError(error);
        }
    }

    private static void openSingleton(
            EngineState<TestHandle> state,
            AtomicReference<EngineState.OpenOutcome<TestHandle>> outcome,
            AtomicReference<Throwable> failure,
            AtomicInteger nativeOpenCount,
            CountDownLatch firstOpenStarted,
            CountDownLatch releaseFirstOpen) {
        try {
            outcome.set(state.openOrReuse(
                    "/singleton.db",
                    true,
                    id -> {
                        nativeOpenCount.incrementAndGet();
                        firstOpenStarted.countDown();
                        assertTrue(releaseFirstOpen.await(
                                TIMEOUT_SECONDS,
                                TimeUnit.SECONDS));
                        return new TestHandle(id, "/singleton.db");
                    },
                    handle -> !handle.closed.get()));
        } catch (Throwable error) {
            failure.compareAndSet(null, error);
        }
    }

    private static void awaitUnchecked(CountDownLatch latch) {
        try {
            if (!latch.await(TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
                throw new AssertionError("latch timed out");
            }
        } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
            throw new AssertionError(error);
        }
    }

    private static void awaitOpeningWaiter(EngineState<TestHandle> state) {
        long deadline = System.nanoTime() +
                TimeUnit.SECONDS.toNanos(TIMEOUT_SECONDS);
        while (state.openingWaiterCount() != 1 && System.nanoTime() < deadline) {
            Thread.yield();
        }
        assertEquals(1, state.openingWaiterCount());
    }

    private static final class TestHandle {
        final int id;
        final String path;
        final AtomicBoolean closed = new AtomicBoolean();

        TestHandle(int id, String path) {
            this.id = id;
            this.path = path;
        }

        boolean close() {
            closed.set(true);
            return true;
        }
    }

    private static final class TestEngineWorker implements EngineWorker {
        private final Object lock = new Object();
        private final ExecutorService executor = Executors.newSingleThreadExecutor();
        private final CountDownLatch terminated = new CountDownLatch(1);
        private boolean shutdown;

        TestEngineWorker() {
            EngineDebugCensus.workerStarted();
        }

        @Override
        public boolean post(Runnable task) {
            synchronized (lock) {
                if (shutdown) {
                    return false;
                }
                submit(task);
                return true;
            }
        }

        @Override
        public void shutdownAfterDrain(Runnable cleanup, Runnable onTerminated) {
            synchronized (lock) {
                if (shutdown) {
                    return;
                }
                shutdown = true;
                submit(cleanup);
                executor.shutdown();
            }
            Thread reaper = new Thread(() -> {
                try {
                    if (!executor.awaitTermination(TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
                        throw new AssertionError("test worker did not drain");
                    }
                    EngineDebugCensus.workerTerminated();
                    onTerminated.run();
                } catch (InterruptedException error) {
                    Thread.currentThread().interrupt();
                } finally {
                    terminated.countDown();
                }
            });
            reaper.setDaemon(true);
            reaper.start();
        }

        void awaitIdle() throws Exception {
            CountDownLatch idle = new CountDownLatch(1);
            assertTrue(post(idle::countDown));
            assertTrue(idle.await(TIMEOUT_SECONDS, TimeUnit.SECONDS));
        }

        boolean awaitTerminated() throws InterruptedException {
            return terminated.await(TIMEOUT_SECONDS, TimeUnit.SECONDS);
        }

        private void submit(Runnable task) {
            EngineDebugCensus.taskQueued();
            executor.execute(() -> {
                EngineDebugCensus.taskDequeued();
                try {
                    task.run();
                } finally {
                    EngineDebugCensus.taskFinished();
                }
            });
        }
    }
}
