package app.wardpulse.watchsync;

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;

/** Runs the production transaction engine with an ordinary durable map backend. */
public final class ConnectionCacheEngineTest {
    static final String C = "openai.plan";
    static final String ID = "a".repeat(64);
    static int assertions;
    static class Disk implements ConnectionCacheEngine.Backend {
        Map<String, String> data = new HashMap<>(); boolean fail;
        public Map<String, String> read() { return new HashMap<>(data); }
        public boolean commit(Map<String, String> values) {
            if (fail) return false; data = new HashMap<>(values); return true;
        }
    }
    static void check(boolean value, String message) { assertions++; if (!value) throw new AssertionError(message); }
    @SuppressWarnings("unchecked") static Map<String, String> version(Map<String, Object> value) {
        Map<String, String> result = new HashMap<>();
        for (String key : new String[]{"generation", "revision", "epoch", "identity"})
            if (value.get(key) != null) result.put(key, (String)value.get(key));
        return result;
    }
    static Map<String, Object> acquire(ConnectionCacheEngine engine, String owner, String action, Map<String, String> expected) {
        AtomicReference<Map<String, Object>> answer = new AtomicReference<>();
        engine.acquire(owner, C, action, expected, answer::set, error -> { throw new RuntimeException(error); });
        if (answer.get() == null) throw new AssertionError("Unexpected queued operation."); return answer.get();
    }
    static Map<String, Object> finish(ConnectionCacheEngine engine, String owner, Map<String, Object> lease, String operation) {
        return engine.finish(owner, C, (String)lease.get("lease"), operation, ID);
    }
    static Map<String, Object> login(ConnectionCacheEngine engine) {
        Map<String, Object> pending = acquire(engine, "ui", "reconnect", null);
        finish(engine, "ui", pending, "release");
        Map<String, Object> complete = acquire(engine, "ui", "complete", version(pending));
        return finish(engine, "ui", complete, "activate");
    }
    public static void main(String[] ignored) {
        automaticAdmission(); automaticMetadataFailure(); automaticWriteCannotActivateCandidate();
        restartPartialAndMonotonic(); deletionAndOAuthRevision(); leaseQueueAndDetach(); cancellationAndMigration(); corruptionAndFailures(); identityAndAggregate(); fetchExclusion(); cleanupAcknowledgement(); supersededCancellation(); failedCommitMemoryCannotActivate(); activeBackupCleanupProtection(); timestampPrecisionAndLegacyUpgrade(); rejectionLifecycle(); rejectionOwnership(); noticeFailures(); noticeMetadataValidation();
        System.out.println("Connection cache engine: " + assertions + " assertions passed.");
    }
    static void restartPartialAndMonotonic() {
        Disk disk = new Disk(); ConnectionCacheEngine first = new ConnectionCacheEngine(disk);
        Map<String, String> v = version(login(first));
        check(first.writeSnapshot(C, v, "sanitized-normalized", 100), "Warm cache write.");
        ConnectionCacheEngine cold = new ConnectionCacheEngine(disk);
        check("sanitized-normalized".equals(cold.readSnapshot(C, v)), "Restart retains snapshot.");
        check(!cold.writeSnapshot(C, v, "older", 99), "Older timestamp cannot replace cache.");
        cold.clearSnapshot(C, v);
        check(!cold.valid(C, v), "Cache epoch invalidates old write.");
        Map<String, Object> read = acquire(cold, "worker", "read", null);
        check(read.get("slot").equals(disk.data.get(C + ".slot")), "Cache clear preserves encrypted slot.");
        check(read.get("generation").equals(v.get("generation")), "Cache clear preserves credential generation.");
        finish(cold, "worker", read, "release");
    }
    static void deletionAndOAuthRevision() {
        Disk disk = new Disk(); ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
        Map<String, String> old = version(login(engine)); engine.writeSnapshot(C, old, "cached", 10);
        Map<String, Object> refresh = acquire(engine, "A", "refresh", old);
        Map<String, String> newer = version(finish(engine, "A", refresh, "activate"));
        check(newer.get("generation").equals(old.get("generation")), "Token refresh keeps principal generation.");
        check(!newer.get("revision").equals(old.get("revision")), "Token refresh rotates revision.");
        Map<String, Object> failedOldToken = acquire(engine, "B", "delete", old);
        check(Boolean.FALSE.equals(failedOldToken.get("accepted")), "Old auth failure cannot delete refreshed token.");
        check(engine.valid(C, old), "Cached metrics survive token refresh.");
        Map<String, Object> deletion = acquire(engine, "ui", "delete", null);
        check(engine.readNotice(C).isEmpty(), "Ordinary deletion supplies no authentication-rejection reason.");
        check(!engine.valid(C, old), "Delete barrier precedes secure SDK cleanup.");
        check(!engine.writeSnapshot(C, old, "late-result", 99), "Deleted cache cannot resurrect.");
        finish(engine, "ui", deletion, "release");
        Map<String, String> reconnected = version(login(engine));
        check(Boolean.FALSE.equals(acquire(engine, "old", "delete", newer).get("accepted")), "Old auth failure cannot delete newer login.");
        check(engine.valid(C, reconnected), "New login retained.");
    }
    static void leaseQueueAndDetach() {
        Disk disk = new Disk(); ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
        Map<String, String> v = version(login(engine));
        Map<String, Object> read = acquire(engine, "A", "read", null);
        AtomicReference<Map<String, Object>> deletion = new AtomicReference<>();
        engine.acquire("B", C, "delete", null, deletion::set, error -> { throw new RuntimeException(error); });
        check(deletion.get() == null, "Cross-engine delete queues behind awaited secure read.");
        finish(engine, "A", read, "confirm");
        check(deletion.get() != null && !engine.valid(C, v), "Queued deletion commits barrier after read.");
        finish(engine, "B", deletion.get(), "release");
        Map<String, String> active = version(login(engine));
        Map<String, Object> refresh = acquire(engine, "dead", "refresh", active);
        String abandonedSlot = (String)refresh.get("writeSlot");
        engine.detach("dead");
        check(!engine.valid(C, active), "Detached unresolved SDK write fails closed.");
        Map<String, Object> login = login(engine);
        check(!abandonedSlot.equals(login.get("slot")), "Reconnect selects different encrypted slot.");
        boolean rejected = false;
        try { finish(engine, "dead", refresh, "activate"); } catch (IllegalStateException expected) { rejected = true; }
        check(rejected, "Detached engine cannot complete old credential write.");
    }
    static void cancellationAndMigration() {
        Disk disk = new Disk(); ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
        Map<String, Object> active = login(engine);
        Map<String, Object> reconnect = acquire(engine, "ui", "reconnect", null);
        check(!engine.valid(C, version(active)), "Reconnect barrier starts before network sign-in.");
        finish(engine, "ui", reconnect, "release");
        Map<String, Object> pendingRead = acquire(engine, "worker", "read", null);
        check("pending".equals(pendingRead.get("mode")), "Worker cannot select credentials while sign-in pending.");
        finish(engine, "worker", pendingRead, "release");
        Map<String, Object> cancel = acquire(engine, "ui", "cancel", version(reconnect));
        Map<String, Object> restored = finish(engine, "ui", cancel, "cancel");
        check(active.get("slot").equals(restored.get("slot")), "Cancelled reconnect retains previous credential.");
        check(!active.get("generation").equals(restored.get("generation")), "Cancellation cannot revive old in-flight request.");
        Disk installed = new Disk(); ConnectionCacheEngine migrationEngine = new ConnectionCacheEngine(installed);
        Map<String, Object> read = acquire(migrationEngine, "ui", "read", null);
        migrationEngine.prepareMigration("ui", C, (String)read.get("lease"));
        migrationEngine.detach("ui");
        check("migration".equals(acquire(new ConnectionCacheEngine(installed), "worker", "read", null).get("mode")), "Detached migration retains installed-session retry path without selecting abandoned slot.");
        // A completed operation failure preserves the legacy backup for retry after restart.
        Disk retryDisk = new Disk(); ConnectionCacheEngine retry = new ConnectionCacheEngine(retryDisk);
        Map<String, Object> r = acquire(retry, "ui", "read", null);
        retry.prepareMigration("ui", C, (String)r.get("lease")); finish(retry, "ui", r, "release");
        ConnectionCacheEngine cold = new ConnectionCacheEngine(retryDisk);
        Map<String, Object> retryRead = acquire(cold, "ui", "read", null);
        check("migration".equals(retryRead.get("mode")), "Interrupted migration retains installed-session retry path.");
        cold.prepareMigration("ui", C, (String)retryRead.get("lease"));
        check("active".equals(finish(cold, "ui", retryRead, "activate").get("mode")), "Legacy migration can recover.");
    }
    static void corruptionAndFailures() {
        Disk disk = new Disk(); ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
        Map<String, Object> active = login(engine); Map<String, String> v = version(active);
        engine.writeSnapshot(C, v, "payload", 10); disk.data.put(C + ".snapshotVersion", "future");
        check(engine.readSnapshot(C, v) == null, "Unsupported payload version refused.");
        check(active.get("slot").equals(disk.data.get(C + ".slot")), "Bad payload retains credential slot.");
        Map<String, Object> read = acquire(engine, "ui", "read", null); finish(engine, "ui", read, "release");
        Map<String, String> current = version(read);
        disk.fail = true;
        check(!engine.writeSnapshot(C, current, "fresh", 20), "Payload disk failure is best effort.");
        check(engine.valid(C, current), "Payload failure does not fence login.");
        boolean failed = false;
        try { acquire(engine, "ui", "delete", null); } catch (RuntimeException expected) { failed = true; }
        check(failed, "Failed deletion barrier rejects SDK cleanup before lease granted.");
        disk.fail = false; check("active".equals(login(engine).get("mode")), "Explicit reconnect recovers unknown storage state.");
        Map<String, Object> lease = acquire(engine, "ui", "read", null);
        Map<String, Object> missing = engine.finish("ui", C, (String)lease.get("lease"), "confirm", "b".repeat(64));
        check("deleted".equals(missing.get("mode")) && !disk.data.containsKey(C + ".snapshot"), "Identity mismatch purges cache and pointer.");
    }
    static void identityAndAggregate() {
        Disk disk = new Disk(); ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
        Map<String, String> v = version(login(engine)); engine.writeSnapshot(C, v, "cached", 10);
        Map<String, String> wrong = new HashMap<>(v); wrong.put("identity", "b".repeat(64));
        check(!engine.valid(C, wrong), "Cache identity is part of ownership.");
        check(engine.readSnapshot(C, wrong) == null && !engine.writeSnapshot(C, wrong, "wrong", 20), "Wrong identity cannot read/write payload.");
        check(Boolean.FALSE.equals(acquire(engine, "other", "refresh", wrong).get("accepted")), "Wrong identity cannot refresh credentials.");
        check(Boolean.FALSE.equals(acquire(engine, "other", "delete", wrong).get("accepted")), "Wrong identity cannot delete credentials.");
        Map<String, Map<String, String>> all = new HashMap<>(); all.put(C, v);
        check(engine.validAll(all), "Aggregate validates current lease atomically."); all.put(C, wrong);
        check(!engine.validAll(all), "Aggregate rejects any obsolete lease.");
    }
    static void fetchExclusion() {
        Disk disk = new Disk(); ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
        Map<String, String> v = version(login(engine));
        AtomicReference<Map<String, Object>> a = new AtomicReference<>(), b = new AtomicReference<>();
        engine.acquireFetch("A", C, a::set); engine.acquireFetch("B", C, b::set);
        check(a.get() != null && b.get() == null, "OAuth network work has independent cross-engine exclusion.");
        Map<String, Object> deletion = acquire(engine, "ui", "delete", null);
        check(!engine.valid(C, v), "Credential barrier does not wait for held network reservation."); finish(engine, "ui", deletion, "release");
        engine.releaseFetch("A", C, (String)a.get().get("fetchTicket"));
        check(b.get() != null && !engine.validFetch("A", C, (String)a.get().get("fetchTicket")), "Reservation transfers after completion.");
        engine.detach("B"); check(!engine.validFetch("B", C, (String)b.get().get("fetchTicket")), "Detach invalidates network token.");
        Map<String, String> fresh = version(login(engine)); AtomicReference<Exception> rejected = new AtomicReference<>();
        engine.acquire("A", C, "delete", fresh, (String)a.get().get("fetchTicket"), value -> {}, rejected::set);
        check(rejected.get() != null && engine.valid(C, fresh), "Expired fetch token cannot delete a current credential.");
    }
    static void cleanupAcknowledgement() {
        Disk disk = new Disk(); ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
        Map<String, Object> old = login(engine), fresh = login(engine);
        Map<String, Object> read = acquire(engine, "worker", "read", null);
        @SuppressWarnings("unchecked") java.util.List<String> cleanup = (java.util.List<String>)read.get("cleanupSlots");
        check(cleanup.contains(old.get("slot")) && !cleanup.contains(fresh.get("slot")), "Cleanup owns retired exact keys only.");
        disk.fail = true;
        check(!engine.acknowledgeCleanup("worker", C, (String)read.get("lease"), cleanup), "Failed acknowledgement retains durable references.");
        disk.fail = false; finish(engine, "worker", read, "release");
        read = acquire(engine, "worker", "read", null);
        @SuppressWarnings("unchecked") java.util.List<String> retry = (java.util.List<String>)read.get("cleanupSlots");
        check(retry.contains(old.get("slot")), "Fresh acquisition retries unacknowledged deletion.");
        check(engine.acknowledgeCleanup("worker", C, (String)read.get("lease"), retry), "Acknowledged exact-key deletion removes references.");
        finish(engine, "worker", read, "release");
        check(engine.valid(C, version(fresh)), "Cleanup preserves active generation/revision/epoch.");
    }
    static void supersededCancellation() {
        Disk disk = new Disk(); ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
        Map<String, Object> active = login(engine);
        Map<String, Object> a = acquire(engine, "A", "reconnect", null); finish(engine, "A", a, "release");
        Map<String, Object> b = acquire(engine, "B", "reconnect", null);
        @SuppressWarnings("unchecked") java.util.List<String> cleanup = (java.util.List<String>)b.get("cleanupSlots");
        check(!cleanup.contains(active.get("slot")), "Superseded reconnect protects immutable prior ref.");
        finish(engine, "B", b, "release");
        check(Boolean.FALSE.equals(acquire(engine, "A", "complete", version(a)).get("accepted")), "Superseded login cannot select old candidate.");
        Map<String, Object> cancel = acquire(engine, "B", "cancel", version(b));
        Map<String, Object> restored = finish(engine, "B", cancel, "cancel");
        check(active.get("slot").equals(restored.get("slot")) && restored.get("generation").equals(b.get("generation")), "Second cancellation restores prior credential with new generation.");
    }

    static void failedCommitMemoryCannotActivate() {
        class MemoryUpdatingDisk extends Disk {
            @Override public boolean commit(Map<String, String> values) {
                data = new HashMap<>(values); return !fail;
            }
        }
        MemoryUpdatingDisk disk = new MemoryUpdatingDisk(); ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
        Map<String, Object> original = login(engine);
        Map<String, Object> pending = acquire(engine, "ui", "reconnect", null); finish(engine, "ui", pending, "release");
        Map<String, Object> complete = acquire(engine, "ui", "complete", version(pending));
        String uncertainSlot = (String)complete.get("writeSlot");
        disk.fail = true; boolean failed = false;
        try { finish(engine, "ui", complete, "activate"); } catch (IllegalStateException expected) { failed = true; }
        check(failed && !engine.valid(C, version(pending)), "Unknown commit fences memory-visible active state.");
        disk.fail = false;
        Map<String, Object> retry = acquire(engine, "ui", "reconnect", null); finish(engine, "ui", retry, "release");
        Map<String, Object> cancel = acquire(engine, "ui", "cancel", version(retry));
        Map<String, Object> restored = finish(engine, "ui", cancel, "cancel");
        check(original.get("slot").equals(restored.get("slot")) && !uncertainSlot.equals(restored.get("slot")), "Explicit recovery cannot reactivate unknown committed candidate.");
        Map<String, Object> current = login(engine);
        Map<String, Object> secondPending = acquire(engine, "ui", "reconnect", null); finish(engine, "ui", secondPending, "release");
        Map<String, Object> secondComplete = acquire(engine, "ui", "complete", version(secondPending));
        disk.fail = true;
        try { finish(engine, "ui", secondComplete, "activate"); } catch (IllegalStateException expected) { }
        disk.fail = false;
        Map<String, Object> secondRetry = acquire(engine, "ui", "reconnect", null); finish(engine, "ui", secondRetry, "release");
        Map<String, Object> secondCancel = acquire(engine, "ui", "cancel", version(secondRetry));
        Map<String, Object> secondRestored = finish(engine, "ui", secondCancel, "cancel");
        check(current.get("slot").equals(secondRestored.get("slot")) && !original.get("slot").equals(secondRestored.get("slot")), "Second failure recovery uses immediately prior valid state.");

    }

    static void activeBackupCleanupProtection() {
        Disk disk = new Disk(); ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
        Map<String, Object> migration = acquire(engine, "ui", "read", null);
        engine.prepareMigration("ui", C, (String)migration.get("lease")); finish(engine, "ui", migration, "activate");
        Map<String, Object> pending = acquire(engine, "ui", "reconnect", null); finish(engine, "ui", pending, "release");
        Map<String, Object> cancel = acquire(engine, "ui", "cancel", version(pending)); finish(engine, "ui", cancel, "cancel");
        Map<String, Object> read = acquire(engine, "cold", "read", null);
        String legacy = "wardpulse.codex.account-session";
        @SuppressWarnings("unchecked") java.util.List<String> cleanup = (java.util.List<String>)read.get("cleanupSlots");
        check(!cleanup.contains(legacy), "Cancelled reconnect active backup is excluded from cleanup enumeration.");
        engine.acknowledgeCleanup("cold", C, (String)read.get("lease"), java.util.List.of(legacy));
        check(disk.data.get(C + ".retired").contains(legacy), "Acknowledgement cannot remove the protected active backup reference.");
        finish(engine, "cold", read, "release");
    }

    static void timestampPrecisionAndLegacyUpgrade() {
        Disk disk = new Disk(); ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
        Map<String, String> version = version(login(engine));
        check(engine.writeSnapshot(C, version, "newer", 1001), "New microsecond snapshot persists.");
        check(!engine.writeSnapshot(C, version, "older", 1000), "One-microsecond older write is refused.");
        disk.data.remove(C + ".snapshotTimeUnit"); disk.data.put(C + ".snapshotAt", "1");
        check("newer".equals(new ConnectionCacheEngine(disk).readSnapshot(C, version)), "Legacy millisecond records remain readable after restart.");
        check(engine.upgradeSnapshotTimestamp(C, version, "newer", 1001), "Legacy ordering upgrades from parsed original timestamp.");
        check(!engine.writeSnapshot(C, version, "older", 1000), "Legacy upgrade retains submillisecond ordering.");
        engine.writeSnapshot(C, version, "latest", 1002);
        check(!engine.upgradeSnapshotTimestamp(C, version, "newer", 1001), "Delayed metadata upgrade cannot replace newer payload.");
        check("latest".equals(engine.readSnapshot(C, version)), "Metadata upgrade race leaves newer payload intact.");
    }

    static boolean rejection(ConnectionCacheEngine engine, String owner, String connection, Map<String, String> expected, boolean remove) {
        AtomicReference<Map<String, Object>> fetch = new AtomicReference<>(), result = new AtomicReference<>();
        engine.acquireFetch(owner, connection, fetch::set);
        String ticket = (String)fetch.get().get("fetchTicket");
        try {
            engine.acquire(owner, connection, remove ? "rejectDelete" : "reject", expected, ticket,
                result::set, error -> { throw new RuntimeException(error); });
            check(result.get() != null, "Rejection completed under owned fetch.");
            if (result.get().get("lease") instanceof String)
                engine.finish(owner, connection, (String)result.get().get("lease"), "release", null);
            return Boolean.TRUE.equals(result.get().get("accepted"));
        } finally { engine.releaseFetch(owner, connection, ticket); }
    }
    static void rejectionLifecycle() {
        Disk disk = new Disk(); ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
        check(engine.readNotice(C).isEmpty(), "Pristine storage has no inferred rejection.");
        Map<String, Object> login = login(engine);
        disk.data.remove(C + ".committedConnection");
        Map<String, Object> read = acquire(engine, "installed", "read", null);
        login = finish(engine, "installed", read, "confirm");
        check(engine.readNotice(C).isEmpty(), "Initializing an installed identity creates no historical event.");
        Map<String, String> v = version(login);
        String committed = (String)login.get("committedConnection");
        engine.writeSnapshot(C, v, "cached", 1);
        check(rejection(engine, "worker", C, v, false), "Owned retained-credential rejection records.");
        check(engine.valid(C, v) && "cached".equals(engine.readSnapshot(C, v)), "Notice does not retire credential or cache.");
        check(committed.equals(engine.readNotice(C).get("eventId")), "Event belongs to committed connection.");
        check(engine.dismissNotice(C, committed), "Exact event dismisses.");
        check(rejection(engine, "poll", C, v, false), "Repeat failure remains owned.");
        engine = new ConnectionCacheEngine(disk);
        check(Boolean.TRUE.equals(engine.readNotice(C).get("dismissed")), "Dismissal survives repeat and restart.");
        Map<String, Object> refresh = acquire(engine, "worker", "refresh", v);
        Map<String, Object> refreshed = finish(engine, "worker", refresh, "activate");
        check(committed.equals(refreshed.get("committedConnection")), "Ordinary token refresh preserves event eligibility.");
        Map<String, Object> pending = acquire(engine, "ui", "reconnect", null); finish(engine, "ui", pending, "release");
        Map<String, Object> cancel = acquire(engine, "ui", "cancel", version(pending));
        Map<String, Object> restored = finish(engine, "ui", cancel, "cancel");
        check(committed.equals(restored.get("committedConnection")), "Cancelled reconnect keeps committed identity despite new generation.");
        rejection(engine, "poll", C, version(restored), false);
        check(Boolean.TRUE.equals(engine.readNotice(C).get("dismissed")), "Cancellation cannot rearm dismissed rejection.");
        Map<String, Object> next = login(engine);
        check(!committed.equals(next.get("committedConnection")), "Same-principal committed reconnect is new eligibility.");
        check(Boolean.TRUE.equals(engine.readNotice(C).get("dismissed")), "Reconnect alone retains historical tombstone.");
        check(!rejection(engine, "old", C, v, false), "Old rejection cannot replace newer connection event.");
        rejection(engine, "new", C, version(next), true);
        String event = (String)engine.readNotice(C).get("eventId");
        check(!event.equals(committed) && Boolean.FALSE.equals(engine.readNotice(C).get("dismissed")), "New connection failure replaces old dismissal.");
        check(!engine.valid(C, version(next)) && !disk.data.containsKey(C + ".snapshot"), "OAuth rejection atomically retires credentials and cache.");
        check(!engine.dismissNotice(C, committed), "Stale X cannot dismiss replacement.");
        check(!rejection(engine, "old-repeat", C, v, false) && event.equals(engine.readNotice(C).get("eventId")), "Repeated old completion cannot clear or replace newer notice.");
        Map<String, Object> reconnected = login(engine);
        check(event.equals(engine.readNotice(C).get("eventId")), "Successful recovery preserves historical warning.");
        Map<String, Object> deletion = acquire(engine, "ui", "delete", null); finish(engine, "ui", deletion, "release");
        check(event.equals(new ConnectionCacheEngine(disk).readNotice(C).get("eventId")), "Ordinary disconnect and restart preserve warning.");
        check(!rejection(engine, "late", C, version(reconnected), false), "Deleted connection cannot invent a fresh event.");
        disk.data.clear();
        check(new ConnectionCacheEngine(disk).readNotice(C).isEmpty(), "Cleared backing storage removes events and tombstones.");
    }
    static void rejectionOwnership() {
        Disk disk = new Disk(); ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
        Map<String, String> v = version(login(engine));
        Map<String, Object> held = acquire(engine, "reader", "read", null);
        AtomicReference<Map<String, Object>> fetch = new AtomicReference<>(), result = new AtomicReference<>();
        engine.acquireFetch("gone", C, fetch::set);
        engine.acquire("gone", C, "reject", v, (String)fetch.get().get("fetchTicket"), result::set,
            error -> { throw new RuntimeException(error); });
        check(result.get() == null, "Notice queues behind credential ownership.");
        engine.detach("gone"); finish(engine, "reader", held, "release");
        check(engine.readNotice(C).isEmpty() && engine.valid(C, v), "Detached queued notice neither creates evidence nor fences credentials.");
        String sibling = "cursor.plan";
        AtomicReference<Map<String, Object>> answer = new AtomicReference<>();
        engine.acquire("ui", sibling, "reconnect", null, answer::set, error -> { throw new RuntimeException(error); });
        Map<String, Object> pending = answer.get(); engine.finish("ui", sibling, (String)pending.get("lease"), "release", null);
        engine.acquire("ui", sibling, "complete", version(pending), answer::set, error -> { throw new RuntimeException(error); });
        Map<String, Object> active = engine.finish("ui", sibling, (String)answer.get().get("lease"), "activate", ID);
        rejection(engine, "one", C, v, false); rejection(engine, "two", sibling, version(active), false);
        engine.dismissNotice(C, (String)engine.readNotice(C).get("eventId"));
        check(Boolean.FALSE.equals(engine.readNotice(sibling).get("dismissed")), "Independent connection event remains visible.");
        AtomicReference<Exception> failure = new AtomicReference<>();
        engine.acquire("gone", C, "reject", v, (String)fetch.get().get("fetchTicket"), result::set, failure::set);
        check(failure.get() != null && Boolean.TRUE.equals(engine.readNotice(C).get("dismissed")), "Retired fetch cannot revive dismissal.");
    }
    static void noticeFailures() {
        class UncertainDisk extends Disk {
            boolean throwsFailure;
            @Override public boolean commit(Map<String, String> values) {
                data = new HashMap<>(values);
                if (fail && throwsFailure) throw new IllegalStateException("Synthetic storage failure.");
                return !fail;
            }
        }
        UncertainDisk disk = new UncertainDisk();
        ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
        Map<String, String> v = version(login(engine));
        rejection(engine, "worker", C, v, false);
        String event = (String)engine.readNotice(C).get("eventId");
        disk.fail = true; boolean failed = false;
        try { engine.dismissNotice(C, event); } catch (IllegalStateException expected) { failed = true; }
        check(failed && Boolean.FALSE.equals(engine.readNotice(C).get("dismissed")), "Failed dismissal retains confirmed visible view.");
        check(engine.valid(C, v), "Notice-only failure does not fence credentials.");
        disk.fail = false; engine.writeSnapshot(C, v, "confirmed", 10);
        check(Boolean.FALSE.equals(new ConnectionCacheEngine(disk).readNotice(C).get("dismissed")), "Later snapshot write cannot publish failed dismissal.");
        Map<String, String> next = version(login(engine)); disk.fail = true; disk.throwsFailure = true; failed = false;
        try { rejection(engine, "new", C, next, false); } catch (RuntimeException expected) { failed = true; }
        check(failed && event.equals(engine.readNotice(C).get("eventId")) && engine.valid(C, next), "Failed replacement event preserves old notice and valid connection.");
        disk.fail = false; engine.writeSnapshot(C, next, "new-cache", 11);
        check(event.equals(new ConnectionCacheEngine(disk).readNotice(C).get("eventId")), "Whole-map write sanitizes failed event metadata.");
        String knownSlot = disk.data.get(C + ".slot");
        disk.fail = true; failed = false;
        try { rejection(engine, "oauth", C, next, true); } catch (RuntimeException expected) { failed = true; }
        check(failed && !engine.valid(C, next), "Failed OAuth deletion barrier remains fail closed.");
        check(event.equals(engine.readNotice(C).get("eventId")), "Uncommitted OAuth event is never reported as durable.");
        disk.fail = false;
        check(engine.dismissNotice(C, event), "Confirmed older notice remains dismissible after a failed barrier.");
        check(!engine.valid(C, next) && knownSlot.equals(disk.data.get(C + ".slot")), "Notice write preserves fencing and only the known credential reference.");
        login(engine);
        check(Boolean.TRUE.equals(engine.readNotice(C).get("dismissed")), "Explicit recovery cannot restore an older undismissed notice view.");
    }

    static void noticeMetadataValidation() {
        Disk disk = new Disk(); ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
        disk.data.put(C + ".rejectionEvent", "00000000-0000-4000-8000-000000000001");
        for (String flag : new String[]{null, "invalid"}) {
            if (flag != null) disk.data.put(C + ".rejectionDismissed", flag);
            boolean refused = false;
            try { engine.readNotice(C); } catch (IllegalStateException expected) { refused = true; }
            check(refused, "Incomplete or malformed notice metadata cannot invent a visible rejection.");
        }
    }

    static String fetch(ConnectionCacheEngine engine, String owner) {
        AtomicReference<Map<String, Object>> answer = new AtomicReference<>();
        engine.acquireFetch(owner, C, answer::set);
        return (String)answer.get().get("fetchTicket");
    }
    static boolean claim(ConnectionCacheEngine engine, String owner, String ticket, Map<String, String> v, long interval) {
        return Boolean.TRUE.equals(engine.claimAutomatic(owner, C, ticket, v, interval).get("admitted"));
    }
    static void automaticAdmission() {
        Disk disk = new Disk(); long[] now = {1000};
        ConnectionCacheEngine engine = new ConnectionCacheEngine(disk, () -> now[0]);
        Map<String, String> v = version(login(engine));
        String first = fetch(engine, "foreground");
        check(claim(engine, "foreground", first, v, 300000), "First automatic start admitted.");
        AtomicReference<Map<String, Object>> queued = new AtomicReference<>();
        engine.acquireFetch("headless", C, queued::set);
        check(queued.get() == null, "Second engine waits for ownership.");
        engine.releaseFetch("foreground", C, first); now[0]++;
        String second = (String)queued.get().get("fetchTicket");
        Map<String, Object> denial = engine.claimAutomatic("headless", C, second, v, 300000);
        check(Boolean.FALSE.equals(denial.get("admitted")) && Long.valueOf(301000).equals(denial.get("nextEligible"))
            && Long.valueOf(1000).equals(denial.get("automaticAt")), "Queued caller shares exact start anchor.");
        now[0] = 300999;
        check(!claim(engine, "headless", second, v, 300000), "One millisecond before due is denied.");
        now[0]++;
        Map<String, Object> boundary = engine.claimAutomatic("headless", C, second, v, 300000);
        check(Boolean.TRUE.equals(boundary.get("admitted")) && Long.valueOf(301000).equals(boundary.get("automaticAt")), "Exact boundary is admitted with its new anchor.");
        engine.detach("headless");
        engine = new ConnectionCacheEngine(disk, () -> now[0]);
        String cold = fetch(engine, "cold");
        check(!claim(engine, "cold", cold, v, 300000), "Detach/recreated owner retains admitted failed work.");
        Map<String, Object> refresh = acquire(engine, "ui", "refresh", v);
        v = version(finish(engine, "ui", refresh, "activate"));
        check(!claim(engine, "cold", cold, v, 300000), "OAuth revision preserves spacing.");
        engine.clearSnapshot(C, v);
        Map<String, Object> read = acquire(engine, "ui", "read", null);
        v = version(read); finish(engine, "ui", read, "release");
        check(!claim(engine, "cold", cold, v, 300000), "Cache invalidation preserves spacing.");
        now[0] += 300000;
        check(!claim(engine, "cold", cold, v, 3600000), "Current sixty-minute preference is honored.");
        check(claim(engine, "cold", cold, v, 300000), "Reset can use five minutes under hourly preference.");
        now[0] += 300000;
        check(!claim(engine, "cold", cold, v, 3600000), "Reset restarts subsequent periodic spacing.");
        v = version(login(engine));
        check(claim(engine, "cold", cold, v, 300000), "Replacement generation has independent admission.");
        engine.releaseFetch("cold", C, cold);
        boolean rejected = false;
        try { claim(engine, "cold", cold, v, 300000); } catch (IllegalStateException expected) { rejected = true; }
        check(rejected, "Released fetch ticket cannot claim.");
    }
    static void automaticMetadataFailure() {
        class UncertainDisk extends Disk {
            @Override public boolean commit(Map<String, String> values) {
                data = new HashMap<>(values); return !fail;
            }
        }
        UncertainDisk disk = new UncertainDisk(); long[] now = {1000};
        ConnectionCacheEngine engine = new ConnectionCacheEngine(disk, () -> now[0]);
        Map<String, String> v = version(login(engine));
        engine.writeSnapshot(C, v, "retained", 1);
        String ticket = fetch(engine, "worker"); disk.fail = true;
        boolean denied = false;
        try { claim(engine, "worker", ticket, v, 300000); } catch (IllegalStateException expected) { denied = true; }
        check(denied && engine.valid(C, v) && "retained".equals(engine.readSnapshot(C, v)), "Admission storage failure preserves credential and cache.");
        disk.fail = false; engine.writeSnapshot(C, v, "retained", 2);
        check(!disk.data.containsKey(C + ".automaticAt"), "Later whole-map write cannot leak failed admission.");
        check(claim(engine, "worker", ticket, v, 300000), "Failed persistence consumes no attempt.");
        now[0] = 301000; disk.fail = true; denied = false;
        try { claim(engine, "worker", ticket, v, 300000); } catch (IllegalStateException expected) { denied = true; }
        disk.fail = false;
        check(Long.valueOf(1000).equals(engine.claimAutomatic("worker", C, ticket, v, 3600000).get("automaticAt")), "Denial reports only the confirmed anchor.");
        engine.writeSnapshot(C, v, "retained", 3);
        check(denied && "1000".equals(disk.data.get(C + ".automaticAt")), "Failed update preserves confirmed anchor.");
        check(claim(engine, "worker", ticket, v, 300000), "Retry remains eligible after failed update.");
        engine.detach("worker");
    }

    static void automaticWriteCannotActivateCandidate() {
        Disk disk = new Disk() {
            @Override public boolean commit(Map<String, String> values) {
                data = new HashMap<>(values); return !fail;
            }
        };
        ConnectionCacheEngine engine = new ConnectionCacheEngine(disk, () -> 1000L);
        login(engine);
        String sibling = "openai.platform";
        AtomicReference<Map<String, Object>> answer = new AtomicReference<>();
        engine.acquire("ui", sibling, "reconnect", null, answer::set, error -> { throw new RuntimeException(error); });
        Map<String, Object> pending = answer.get();
        engine.finish("ui", sibling, (String)pending.get("lease"), "release", null);
        engine.acquire("ui", sibling, "complete", version(pending), answer::set, error -> { throw new RuntimeException(error); });
        Map<String, String> siblingVersion = version(engine.finish("ui", sibling, (String)answer.get().get("lease"), "activate", ID));
        pending = acquire(engine, "ui", "reconnect", null); finish(engine, "ui", pending, "release");
        Map<String, Object> complete = acquire(engine, "ui", "complete", version(pending));
        disk.fail = true; boolean failed = false;
        try { finish(engine, "ui", complete, "activate"); } catch (IllegalStateException expected) { failed = true; }
        disk.fail = false;
        engine.acquireFetch("worker", sibling, answer::set);
        String ticket = (String)answer.get().get("fetchTicket");
        check(failed && Boolean.TRUE.equals(engine.claimAutomatic("worker", sibling, ticket, siblingVersion, 300000).get("admitted")), "Healthy sibling can claim after another connection's failed credential write.");
        check("pending".equals(disk.data.get(C + ".mode")) && !disk.data.containsKey(C + ".slot"), "Admission write retains only confirmed credential state of a fenced sibling.");
        ConnectionCacheEngine coldEngine = new ConnectionCacheEngine(disk);
        Map<String, Object> cold = acquire(coldEngine, "cold", "read", null);
        check("pending".equals(cold.get("mode")), "Restart cannot select the uncertain activated candidate.");
        finish(coldEngine, "cold", cold, "release");
        engine.releaseFetch("worker", sibling, ticket);
    }

}
