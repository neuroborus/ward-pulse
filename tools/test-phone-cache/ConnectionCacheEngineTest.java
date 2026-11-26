package app.wardpulse.watchsync;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
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
    static class MemoryUpdatingDisk extends Disk {
        @Override public boolean commit(Map<String, String> values) {
            data = new HashMap<>(values); return !fail;
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
        return acquire(engine, owner, C, action, expected);
    }
    static Map<String, Object> acquire(ConnectionCacheEngine engine, String owner, String connection, String action,
            Map<String, String> expected) {
        AtomicReference<Map<String, Object>> answer = new AtomicReference<>();
        engine.acquire(owner, connection, action, expected, answer::set, error -> { throw new RuntimeException(error); });
        if (answer.get() == null) throw new AssertionError("Unexpected queued operation."); return answer.get();
    }
    static Map<String, Object> finish(ConnectionCacheEngine engine, String owner, Map<String, Object> lease, String operation) {
        return engine.finish(owner, C, (String)lease.get("lease"), operation, ID);
    }
    static Map<String, Object> login(ConnectionCacheEngine engine) {
        return login(engine, C);
    }
    static Map<String, Object> login(ConnectionCacheEngine engine, String connection) {
        Map<String, Object> pending = acquire(engine, "ui", connection, "reconnect", null);
        engine.finish("ui", connection, (String) pending.get("lease"), "release", null);
        Map<String, Object> complete = acquire(engine, "ui", connection, "complete", version(pending));
        return engine.finish("ui", connection, (String) complete.get("lease"), "activate", ID);
    }
    public static void main(String[] ignored) {
        automaticAdmission(); automaticMetadataFailure(); automaticWriteCannotActivateCandidate(); absenceOwnership();
        restartPartialAndMonotonic(); deletionAndOAuthRevision(); leaseQueueAndDetach();
        // Runs before other cancellation cases so a lost saved reference fails first.
        cancelledReconnectSurvivesDetach();
        cancellationAndMigration(); corruptionAndFailures(); identityAndAggregate(); fetchExclusion(); cleanupAcknowledgement(); supersededCancellation(); failedCommitMemoryCannotActivate(); siblingWritesCannotActivateCandidate(); emptyPriorStateSurvivesSiblingWrite(); activeBackupCleanupProtection(); timestampPrecisionAndLegacyUpgrade(); rejectionLifecycle(); rejectionOwnership(); noticeFailures(); noticeMetadataValidation();
        verifiedReconnectRetiresNotice(); failedReconnectReportPreservesConfirmedState();
        failedSnapshotTransactionsRetainConfirmedPair();
        failedFirstLegacyCleanupRetainsEmptyState();
        claudePlanRetirement();
        failedClaudePlanRetirementFences();
        dataModeAuthority(); modePolicyWriteFailure(); dataModeFetchFencing(); legacyWatchRefreshAdmission();
        waitingWearResendCapturesSettledMode(); widgetDeliveryRequiresCurrentMode();
        recoveryPreferenceAdmission(); unrecordedRecoveriesSpanEngines();
        scopedCredentialAdmission(); scopedSnapshotMaintenance(); unscopedFetchLeavesModeAbsent();
        automaticOwnershipFollowsCredential(); watchSummaryArrivalOrder(); watchSummaryAdmissionFollowsCredential();
        System.out.println("Connection cache engine: " + assertions + " assertions passed.");
    }
    static void automaticOwnershipFollowsCredential() {
        Disk disk = new Disk(); ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
        Map<String, String> v = version(login(engine));
        check(engine.ownsAutomatic(C, v), "Confirmed credential owns its cadence.");
        engine.clearSnapshot(C, v);
        check(!engine.valid(C, v) && engine.ownsAutomatic(C, v), "Snapshot epoch change keeps cadence ownership.");
        Map<String, String> reconnected = version(login(engine));
        check(!engine.ownsAutomatic(C, v), "Reconnect retires prior cadence.");
        check(engine.ownsAutomatic(C, reconnected), "Reconnected credential owns its cadence.");
        finish(engine, "ui", acquire(engine, "ui", "delete", null), "release");
        check(!engine.ownsAutomatic(C, reconnected), "Deletion retires cadence.");
        check(!new ConnectionCacheEngine(new Disk()).ownsAutomatic(C, reconnected), "Absent credential owns no cadence.");
    }
    static void watchSummaryArrivalOrder() {
        ConnectionCacheEngine engine = new ConnectionCacheEngine(new Disk());
        long older = engine.reserveWatchSummary(), newer = engine.reserveWatchSummary();
        check(engine.claimWatchSummary(newer), "Newest arrival is sent.");
        check(!engine.claimWatchSummary(older), "Late-ready older arrival cannot replace a newer summary.");
        check(!engine.claimWatchSummary(newer), "A summary is sent once.");
        check(engine.claimWatchSummary(engine.reserveWatchSummary()), "A later arrival is sent.");
    }
    static void watchSummaryAdmissionFollowsCredential() {
        ConnectionCacheEngine engine = new ConnectionCacheEngine(new Disk());
        Map<String, String> v = version(login(engine));
        // Dart confirmed this report; the credential is replaced in the same mode generation.
        long confirmed = engine.reserveWatchSummary();
        Map<String, String> reconnected = version(login(engine));
        check(engine.admitWatchSummary(confirmed, Map.of(C, v)) == null, "A retired credential's summary is not sent.");
        check(Boolean.TRUE.equals(engine.admitWatchSummary(confirmed, Map.of(C, reconnected))),
            "A stale proof consumes no arrival, so the current report is sent.");
        long cleared = engine.reserveWatchSummary();
        finish(engine, "ui", acquire(engine, "ui", "delete", null), "release");
        check(engine.admitWatchSummary(cleared, Map.of(C, reconnected)) == null, "Deletion retires the confirmed summary.");
        check(Boolean.TRUE.equals(engine.admitWatchSummary(cleared, null)), "A summary without credential proof keeps arrival order.");
        check(Boolean.FALSE.equals(engine.admitWatchSummary(cleared, Map.of())), "A summary is admitted once.");

        // Dart confirmed a retained report; the same credential then writes a newer row.
        ConnectionCacheEngine cache = new ConnectionCacheEngine(new MemoryUpdatingDisk());
        Map<String, String> current = version(login(cache));
        check(cache.writeSnapshot(C, current, "retained", 1001), "Retained row persists.");
        Map<String, Map<String, Object>> retained = Map.of(C,
            Map.of("era", 0L, "generatedAt", 1001L, "rowId", cache.readSnapshotPair(C, current).get("rowId")));
        Map<String, Map<String, String>> versions = Map.of(C, current);
        check(cache.validAll(versions, Map.of(), retained, Map.of()), "The confirmed row proof is current.");
        long report = cache.reserveWatchSummary();
        check(cache.writeSnapshot(C, current, "replacement", 1002), "A same-credential write replaces the row.");
        check(cache.admitWatchSummary(report, versions, Map.of(), retained, Map.of()) == null,
            "A replaced row's summary is not sent though its credential is current.");
        Map<String, Map<String, Object>> replacement = Map.of(C,
            Map.of("era", 0L, "generatedAt", 1002L, "rowId", cache.readSnapshotPair(C, current).get("rowId")));
        check(Boolean.TRUE.equals(cache.admitWatchSummary(report, versions, Map.of(), replacement, Map.of())),
            "The replacement row's summary is sent.");
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
        engine.detach("B");
        Map<String, Object> deleted = acquire(engine, "cold", "read", null);
        check("deleted".equals(deleted.get("mode")) && version(deleted).equals(version(deletion.get()))
                && deleted.get("cleanupSlots").equals(deletion.get().get("cleanupSlots")),
            "Detaching a committed delete lease retains its generation and cleanup queue.");
        finish(engine, "cold", deleted, "release");
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
        Map<String, Object> restored = acquire(engine, "ui", "cancel", version(reconnect));
        check(active.get("slot").equals(restored.get("slot")), "Cancelled reconnect retains previous credential.");
        check(!active.get("generation").equals(restored.get("generation")), "Cancellation cannot revive old in-flight request.");
        check(Boolean.TRUE.equals(restored.get("accepted")) && !restored.containsKey("lease"), "Cancellation commits without a lease.");
        String legacyKey = "wardpulse.codex.account-session";
        for (boolean migrationStarted : new boolean[]{false, true}) {
            // A failed legacy read or interrupted migration precedes the cancelled reconnect.
            Disk legacyDisk = new Disk(); ConnectionCacheEngine legacyEngine = new ConnectionCacheEngine(legacyDisk);
            Map<String, Object> failedRead = acquire(legacyEngine, "ui", "read", null);
            if (migrationStarted) legacyEngine.prepareMigration("ui", C, (String)failedRead.get("lease"));
            finish(legacyEngine, "ui", failedRead, "release");
            Map<String, Object> legacyPending = acquire(legacyEngine, "ui", "reconnect", null);
            finish(legacyEngine, "ui", legacyPending, "release");
            check("legacy".equals(acquire(legacyEngine, "ui", "cancel", version(legacyPending)).get("mode")), "Cancellation restores legacy recovery.");
            ConnectionCacheEngine coldLegacy = new ConnectionCacheEngine(legacyDisk);
            Map<String, Object> coldRead = acquire(coldLegacy, "cold", "read", null);
            @SuppressWarnings("unchecked") List<String> coldCleanup = (List<String>)coldRead.get("cleanupSlots");
            check("legacy".equals(coldRead.get("mode")) && !coldCleanup.contains(legacyKey), "Cold read keeps the installed session after cancellation.");
            coldLegacy.prepareMigration("cold", C, (String)coldRead.get("lease"));
            check("active".equals(finish(coldLegacy, "cold", coldRead, "activate").get("mode")), "Cold read migrates the installed session after cancellation.");
        }
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

    static void claudePlanRetirement() {
        String claude = "anthropic.plan";
        String session = "wardpulse.claude.account-session";
        String pasted = "wardpulse.anthropic.plan.secret";
        for (boolean alreadyDeleted : new boolean[]{false, true}) {
            Disk disk = new Disk();
            ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
            Map<String, String> sibling = version(login(engine));
            Map<String, Object> read = acquire(engine, "old", claude, "read", null);
            String ticket = (String) read.get("lease");
            String activeSlot = null;
            Map<String, Object> before;
            if (alreadyDeleted) {
                before = engine.finish("old", claude, ticket, "missing", null);
            } else {
                activeSlot = (String) engine.prepareMigration("old", claude, ticket).get("writeSlot");
                before = engine.finish("old", claude, ticket, "activate", ID);
                check(engine.writeSnapshot(claude, version(before), "sanitized-plan", 10),
                    "The migrated session has a warm cache.");
            }

            Map<String, Object> paused = acquire(engine, "ui", claude, "retireClaudePlan", null);
            List<String> expected = alreadyDeleted ? List.of(session, pasted) : List.of(activeSlot, session, pasted);
            check("deleted".equals(paused.get("mode")) && paused.get("cleanupSlots").equals(expected)
                    && paused.get("generation").equals(before.get("generation")) == alreadyDeleted,
                "Retirement durably queues both fixed keys and any active slot without rotating an old deletion.");
            check(!engine.valid(claude, version(before)) && !disk.data.containsKey(claude + ".snapshot")
                    && engine.valid(C, sibling),
                "Only the Claude plan cache and credential are retired.");

            AtomicReference<Map<String, Object>> overlap = new AtomicReference<>();
            engine.acquire("worker", claude, "retireClaudePlan", null, overlap::set,
                error -> { throw new RuntimeException(error); });
            check(overlap.get() == null, "Overlapping retirement waits for the current lease.");
            engine.detach("ui");
            Map<String, Object> retry = overlap.get();
            check("deleted".equals(retry.get("mode")) && version(retry).equals(version(paused))
                    && retry.get("cleanupSlots").equals(expected),
                "Detach releases the waiter with the same barrier and exact queue.");
            String retryTicket = (String) retry.get("lease");
            check(engine.acknowledgeCleanup("worker", claude, retryTicket, expected), "Cleanup is acknowledged.");
            engine.finish("worker", claude, retryTicket, "release", null);
            Map<String, Object> cold = acquire(new ConnectionCacheEngine(disk),
                "cold", claude, "retireClaudePlan", null);
            check(version(cold).equals(version(paused)) && cold.get("cleanupSlots").equals(List.of()),
                "Restart does not requeue acknowledged keys.");
        }
    }

    static void failedClaudePlanRetirementFences() {
        String claude = "anthropic.plan";
        MemoryUpdatingDisk disk = new MemoryUpdatingDisk();
        ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
        Map<String, String> sibling = version(login(engine));
        Map<String, Object> login = login(engine, claude);
        Map<String, String> active = version(login);
        check(engine.writeSnapshot(claude, active, "sanitized-plan", 10), "Claude starts with a warm cache.");
        AtomicReference<Exception> failure = new AtomicReference<>();
        disk.fail = true;
        engine.acquire("ui", claude, "retireClaudePlan", null,
            ignored -> { throw new AssertionError("Retirement lease requires a successful commit."); }, failure::set);
        check(failure.get() instanceof IllegalStateException && !engine.valid(claude, active),
            "Failed retirement cannot grant permission to delete or report.");
        disk.fail = false;
        check(engine.writeSnapshot(C, sibling, "sanitized-sibling", 10)
                && "active".equals(disk.data.get(claude + ".mode"))
                && active.get("generation").equals(disk.data.get(claude + ".generation"))
                && "sanitized-plan".equals(disk.data.get(claude + ".snapshot")),
            "A sibling commit preserves the last confirmed retirement state.");
        failure.set(null);
        engine.acquire("worker", claude, "read", null,
            ignored -> { throw new AssertionError("Ordinary reads must stay fenced after a failed retirement."); },
            failure::set);
        check(failure.get() instanceof IllegalStateException, "Storage recovery alone does not lift the fence.");

        Map<String, Object> retry = acquire(engine, "worker", claude, "retireClaudePlan", null);
        check("deleted".equals(disk.data.get(claude + ".mode"))
                && !active.get("generation").equals(retry.get("generation"))
                && !disk.data.containsKey(claude + ".snapshot") && !engine.valid(claude, active),
            "A retry in the same engine durably retires the prior credential and its cache.");
        List<String> slots = List.of((String) login.get("slot"),
            "wardpulse.claude.account-session", "wardpulse.anthropic.plan.secret");
        List<?> cleanup = (List<?>) retry.get("cleanupSlots");
        check(cleanup.size() == slots.size() && cleanup.containsAll(slots),
            "Only the successful retry grants the cleanup lease for the active slot and both legacy keys.");
        String ticket = (String) retry.get("lease");
        check(engine.acknowledgeCleanup("worker", claude, ticket, slots), "Retry cleanup can be acknowledged.");
        engine.finish("worker", claude, ticket, "release", null);
        Map<String, Object> again = acquire(engine, "worker", claude, "retireClaudePlan", null);
        check(version(again).equals(version(retry)) && List.of().equals(again.get("cleanupSlots")),
            "The same engine retains the retired state and does not requeue acknowledged keys.");
        engine.finish("worker", claude, (String) again.get("lease"), "release", null);
    }
    static void corruptionAndFailures() {
        Disk disk = new Disk(); ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
        Map<String, Object> active = login(engine); Map<String, String> v = version(active);
        engine.writeSnapshot(C, v, "payload", 10); disk.data.put(C + ".snapshotVersion", "future");
        Map<String, Object> selection = engine.readSnapshotPair(C, v, true);
        check(Boolean.TRUE.equals(selection.get("valid")) && selection.get("snapshot") == null
                && "future".equals(disk.data.get(C + ".snapshotVersion")),
            "Selection reads treat unsupported payloads as a miss without clearing the epoch.");
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

    static void failedSnapshotTransactionsRetainConfirmedPair() {
        MemoryUpdatingDisk disk = new MemoryUpdatingDisk();
        long[] now = {86401000};
        ConnectionCacheEngine engine = new ConnectionCacheEngine(disk, () -> now[0]);
        Map<String, String> v = version(login(engine));
        String sibling = "cursor.plan";
        AtomicReference<Map<String, Object>> reply = new AtomicReference<>();
        engine.acquire("ui", sibling, "reconnect", null, reply::set, error -> { throw new RuntimeException(error); });
        Map<String, Object> pending = reply.get();
        engine.finish("ui", sibling, (String) pending.get("lease"), "release", null);
        engine.acquire("ui", sibling, "complete", version(pending), reply::set, error -> { throw new RuntimeException(error); });
        Map<String, String> other = version(engine.finish("ui", sibling, (String) reply.get().get("lease"), "activate", ID));

        String ticket = fetch(engine, "ui");
        String fast = (String) engine.stampFetch("ui", C, ticket, v).get("stamp");
        engine.releaseFetch("ui", C, ticket, now[0] + 1);
        check("stored".equals(engine.writeSnapshotOrdered("ui", C, v, "confirmed", now[0] * 1000L, fast).get("status")),
            "Released fetch can persist the confirmed pair.");
        Map<String, String> confirmed = snapshotFields(disk);
        check(Long.toString(now[0] + 1).equals(confirmed.get(C + ".snapshotClockAt")),
            "The confirmed reference includes a later sample from release.");
        check("older".equals(engine.writeSnapshotOrdered("ui", C, v, "older", now[0] * 1000L - 1, fast).get("status")),
            "An ordered write still compares microseconds within one era.");
        check(!engine.writeSnapshot(C, v, "unstamped", (now[0] + 2) * 1000L),
            "An unstamped write cannot displace an ordered payload.");

        now[0] = 2000;
        ticket = fetch(engine, "worker");
        String corrected = (String) engine.stampFetch("worker", C, ticket, v).get("stamp");
        engine.releaseFetch("worker", C, ticket);
        check("superseded".equals(engine.writeSnapshotOrdered("ui", C, v, "wrong-owner", 2000000, corrected).get("status")),
            "A stamp cannot be borrowed by another owner.");
        disk.fail = true;
        Map<String, Object> failedWrite = engine.writeSnapshotOrdered("worker", C, v, "unconfirmed", 2000000, corrected);
        check("storageFailure".equals(failedWrite.get("status")) && Long.valueOf(1).equals(failedWrite.get("minimumEra")),
            "Failed commit still advances the in-memory write floor.");
        check("unconfirmed".equals(disk.data.get(C + ".snapshot")) && !confirmed.equals(snapshotFields(disk)),
            "Backend exposes failed payload and ordering metadata in memory.");
        Map<String, Object> read = engine.readSnapshotPair(C, v);
        check("confirmed".equals(read.get("snapshot")) && Long.valueOf(0).equals(read.get("era"))
                && Long.valueOf(1).equals(read.get("minimumEra")),
            "Paired read separates the confirmed era from the write floor.");
        disk.fail = false;
        check(engine.writeSnapshot(sibling, other, "sibling-1", 1000) && confirmed.equals(snapshotFields(disk)),
            "A sibling commit cannot make a failed snapshot pair durable.");

        disk.fail = true;
        boolean failed = false;
        try { engine.clearSnapshot(C, v); } catch (IllegalStateException expected) { failed = true; }
        Map<String, String> proposed = new HashMap<>(v);
        proposed.put("epoch", disk.data.get(C + ".epoch"));
        check(failed && !v.get("epoch").equals(proposed.get("epoch")) && !disk.data.containsKey(C + ".snapshot"),
            "Failed clear surfaces the error after exposing the proposed epoch.");
        check(Boolean.FALSE.equals(engine.readSnapshotPair(C, proposed).get("valid"))
                && !engine.writeSnapshot(C, proposed, "wrong-epoch", 90000000),
            "The proposed epoch cannot read or write.");
        check("confirmed".equals(engine.readSnapshot(C, v))
                && Long.valueOf(1).equals(engine.readSnapshotPair(C, v).get("minimumEra")),
            "Failed clear retains the confirmed pair and the live write floor.");
        disk.fail = false;
        check(engine.writeSnapshot(sibling, other, "sibling-2", 2000) && confirmed.equals(snapshotFields(disk)),
            "A sibling commit preserves the original epoch, payload and metadata.");
        ConnectionCacheEngine cold = new ConnectionCacheEngine(disk, () -> now[0]);
        check(cold.valid(C, v) && "confirmed".equals(cold.readSnapshot(C, v))
                && Long.valueOf(0).equals(cold.readSnapshotPair(C, v).get("minimumEra")),
            "A recreated engine loads only the confirmed epoch and pair.");
        cold.clearSnapshot(C, v);
        check(!cold.valid(C, v) && !cold.valid(C, proposed) && snapshotFields(disk).size() == 1,
            "Successful clear retry retires the old epoch and all of its snapshot metadata.");
        Map<String, Object> lease = acquire(cold, "ui", "read", null);
        Map<String, String> cleared = version(finish(cold, "ui", lease, "release"));
        check(cold.valid(C, cleared) && cold.readSnapshot(C, cleared) == null
                && cold.readSnapshotPair(C, cleared).get("minimumEra") == null,
            "The new cache epoch starts with no snapshot or ordering floor.");
        ticket = fetch(cold, "ui");
        String first = (String) cold.stampFetch("ui", C, ticket, cleared).get("stamp");
        cold.releaseFetch("ui", C, ticket);
        disk.fail = true;
        check("storageFailure".equals(cold.writeSnapshotOrdered("ui", C, cleared, "unconfirmed-first", 2000000, first).get("status")),
            "The first ordered commit in the new epoch can fail.");
        read = cold.readSnapshotPair(C, cleared);
        check(read.get("snapshot") == null && Long.valueOf(0).equals(read.get("minimumEra")),
            "The paired read reports the write floor even without a confirmed snapshot.");
    }

    static Map<String, String> snapshotFields(Disk disk) {
        Map<String, String> fields = new HashMap<>();
        disk.data.forEach((key, value) -> {
            if (key.equals(C + ".epoch") || key.startsWith(C + ".snapshot")) fields.put(key, value);
        });
        return fields;
    }

    static void failedFirstLegacyCleanupRetainsEmptyState() {
        MemoryUpdatingDisk disk = new MemoryUpdatingDisk();
        ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
        Map<String, String> version = version(login(engine));
        String legacy = "anthropic.plan";
        AtomicReference<Map<String, Object>> response = new AtomicReference<>();
        engine.acquire("ui", legacy, "read", null, response::set, error -> { throw new RuntimeException(error); });
        String ticket = (String) response.get().get("lease");
        disk.fail = true;
        boolean failed = false;
        try { engine.queueLegacyCleanup("ui", legacy, ticket); } catch (IllegalStateException expected) { failed = true; }
        check(failed && disk.data.containsKey(legacy + ".epoch"), "Failed cleanup exposes a proposed legacy lifecycle.");
        Map<String, Object> released = engine.finish("ui", legacy, ticket, "release", null);
        check("legacy".equals(released.get("mode")) && !released.containsKey("generation"),
            "Cache epoch rollback keeps the whole prior legacy lifecycle readable.");
        disk.fail = false;
        check(engine.writeSnapshot(C, version, "sibling", 1000)
                && disk.data.keySet().stream().noneMatch(key -> key.startsWith(legacy + ".")),
            "A sibling cache commit cannot persist a partial legacy lifecycle.");
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
    static void absenceOwnership() {
        Disk disk = new Disk(); ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
        Map<String, Object> read = acquire(engine, "reader", "read", null);
        Map<String, String> absent = version(finish(engine, "reader", read, "missing"));
        absent.remove("identity"); absent.put("absentRead", "true");
        Map<String, Map<String, String>> all = new HashMap<>(); all.put(C, absent);
        check(engine.validAll(all), "Completed missing read remains current while deletion is unchanged.");
        check(!engine.valid(C, absent) && engine.readSnapshot(C, absent) == null,
            "Absence cannot qualify a positive credential or cached payload.");
        Map<String, String> malformed = new HashMap<>(absent); malformed.put("identity", ID); all.put(C, malformed);
        check(!engine.validAll(all), "Absence cannot contain positive ownership evidence.");
        malformed = new HashMap<>(absent); malformed.put("epoch", ""); all.put(C, malformed);
        check(!engine.validAll(all), "Absence requires a complete matching lifecycle stamp.");
        all.put(C, absent);
        String sibling = "cursor.plan";
        AtomicReference<Map<String, Object>> reply = new AtomicReference<>();
        engine.acquire("B", sibling, "reconnect", null, reply::set, error -> { throw new RuntimeException(error); });
        Map<String, Object> pending = reply.get();
        engine.finish("B", sibling, (String)pending.get("lease"), "release", null);
        engine.acquire("B", sibling, "complete", version(pending), reply::set, error -> { throw new RuntimeException(error); });
        Map<String, String> b = version(engine.finish("B", sibling, (String)reply.get().get("lease"), "activate", ID));
        engine.writeSnapshot(sibling, b, "healthy-B", 77); all.put(sibling, b);
        check(engine.validAll(all), "A absence and healthy B validate together.");
        disk.fail = true;
        try { acquire(engine, "failed", "delete", null); throw new AssertionError("Expected failed barrier."); }
        catch (RuntimeException expected) { /* The native operation actually failed. */ }
        disk.fail = false;
        check(!engine.validAll(all), "Unconfirmed native completion fences absence.");
        login(engine);
        check(!engine.validAll(all), "Activation invalidates the captured absence.");
        check(engine.valid(sibling, b) && "healthy-B".equals(engine.readSnapshot(sibling, b)),
            "Retiring A absence preserves B and its cached report.");
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
        Map<String, Object> restored = acquire(engine, "B", "cancel", version(b));
        check(active.get("slot").equals(restored.get("slot")) && restored.get("generation").equals(b.get("generation")), "Second cancellation restores prior credential with new generation.");
    }
    static void cancelledReconnectSurvivesDetach() {
        Disk disk = new Disk(); ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
        Map<String, Object> active = login(engine);
        Map<String, Object> pending = acquire(engine, "ui", "reconnect", null); finish(engine, "ui", pending, "release");
        Map<String, Object> cancelled = acquire(engine, "ui", "cancel", version(pending));
        engine.detach("ui");
        ConnectionCacheEngine cold = new ConnectionCacheEngine(disk);
        Map<String, Object> read = acquire(cold, "cold", "read", null);
        // Inspect the saved slot before the return contract so a lost reference fails first.
        check(active.get("slot").equals(read.get("slot")) && "active".equals(read.get("mode")), "Detach after cancellation keeps the saved credential.");
        @SuppressWarnings("unchecked") List<String> cleanup = (List<String>)read.get("cleanupSlots");
        check(!cleanup.contains(active.get("slot")) && pending.get("generation").equals(read.get("generation")), "Cold read keeps the restored slot under the reconnect generation.");
        finish(cold, "cold", read, "release");
        check(!cancelled.containsKey("lease") && version(cancelled).equals(version(read)), "Cancellation returns its committed state without a lease.");

        Map<String, Object> successor = acquire(cold, "B", "reconnect", null); finish(cold, "B", successor, "release");
        check(Boolean.FALSE.equals(acquire(cold, "ui", "cancel", version(pending)).get("accepted")), "Stale cancellation replay cannot settle a successor reconnect.");
        Map<String, Object> current = finish(cold, "B", acquire(cold, "B", "complete", version(successor)), "activate");
        check(Boolean.FALSE.equals(acquire(cold, "ui", "cancel", version(pending)).get("accepted")) && cold.valid(C, version(current)), "Stale cancellation replay cannot replace the successor.");

        Map<String, Object> retry = acquire(cold, "ui", "reconnect", null); finish(cold, "ui", retry, "release");
        Map<String, Object> held = acquire(cold, "worker", "read", null);
        AtomicReference<Map<String, Object>> queued = new AtomicReference<>();
        cold.acquire("ui", C, "cancel", version(retry), queued::set, error -> { throw new RuntimeException(error); });
        check(queued.get() == null, "Cancellation waits for a competing owner.");
        finish(cold, "worker", held, "release");
        check(queued.get() != null && current.get("slot").equals(queued.get().get("slot")) && !queued.get().containsKey("lease"), "Queued cancellation commits after the competing owner.");
        cold.detach("ui");
        check("active".equals(acquire(new ConnectionCacheEngine(disk), "cold", "read", null).get("mode")), "Queued cancellation survives detach.");

        Map<String, Object> disconnect = acquire(cold, "settings", "delete", null); finish(cold, "settings", disconnect, "release");
        check(Boolean.FALSE.equals(acquire(cold, "ui", "cancel", version(retry)).get("accepted")), "Cancellation cannot undo an intentional disconnect.");
        check("deleted".equals(acquire(new ConnectionCacheEngine(disk), "cold", "read", null).get("mode")), "Intentional disconnect stays deleted.");
    }

    static void failedCommitMemoryCannotActivate() {
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
        Map<String, Object> restored = acquire(engine, "ui", "cancel", version(retry));
        check(original.get("slot").equals(restored.get("slot")) && !uncertainSlot.equals(restored.get("slot")), "Explicit recovery cannot reactivate unknown committed candidate.");
        Map<String, Object> current = login(engine);
        Map<String, Object> secondPending = acquire(engine, "ui", "reconnect", null); finish(engine, "ui", secondPending, "release");
        Map<String, Object> secondComplete = acquire(engine, "ui", "complete", version(secondPending));
        disk.fail = true;
        try { finish(engine, "ui", secondComplete, "activate"); } catch (IllegalStateException expected) { }
        disk.fail = false;
        Map<String, Object> secondRetry = acquire(engine, "ui", "reconnect", null); finish(engine, "ui", secondRetry, "release");
        Map<String, Object> secondRestored = acquire(engine, "ui", "cancel", version(secondRetry));
        check(current.get("slot").equals(secondRestored.get("slot")) && !original.get("slot").equals(secondRestored.get("slot")), "Second failure recovery uses immediately prior valid state.");

    }

    static void siblingWritesCannotActivateCandidate() {
        for (String write : new String[]{"snapshot", "timestamp", "clear", "lifecycle"}) {
            MemoryUpdatingDisk disk = new MemoryUpdatingDisk(); ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
            Map<String, Object> original = login(engine);
            String sibling = "openai.platform";
            AtomicReference<Map<String, Object>> answer = new AtomicReference<>();
            engine.acquire("ui", sibling, "reconnect", null, answer::set, error -> { throw new RuntimeException(error); });
            Map<String, Object> siblingPending = answer.get();
            engine.finish("ui", sibling, (String)siblingPending.get("lease"), "release", null);
            engine.acquire("ui", sibling, "complete", version(siblingPending), answer::set, error -> { throw new RuntimeException(error); });
            Map<String, Object> siblingActive = engine.finish("ui", sibling, (String)answer.get().get("lease"), "activate", ID);
            Map<String, String> siblingVersion = version(siblingActive);
            check(engine.writeSnapshot(sibling, siblingVersion, "retained", 1001), "Healthy sibling starts with a cache.");
            if ("timestamp".equals(write)) {
                disk.data.remove(sibling + ".snapshotTimeUnit"); disk.data.put(sibling + ".snapshotAt", "1");
            }
            Map<String, Object> pending = acquire(engine, "ui", "reconnect", null); finish(engine, "ui", pending, "release");
            Map<String, Object> complete = acquire(engine, "ui", "complete", version(pending));
            String uncertainSlot = (String)complete.get("writeSlot");
            disk.fail = true; boolean failed = false;
            try { finish(engine, "ui", complete, "activate"); } catch (IllegalStateException expected) { failed = true; }
            check(failed && "active".equals(disk.data.get(C + ".mode")) && uncertainSlot.equals(disk.data.get(C + ".slot")), "Failed activation leaves the attempted candidate visible in memory.");
            disk.fail = false;
            if ("snapshot".equals(write)) {
                check(engine.writeSnapshot(sibling, siblingVersion, "updated", 2002), "Healthy sibling snapshot write succeeds.");
            } else if ("timestamp".equals(write)) {
                check(engine.upgradeSnapshotTimestamp(sibling, siblingVersion, "retained", 1001), "Healthy sibling legacy timestamp upgrade succeeds.");
            } else if ("clear".equals(write)) {
                engine.clearSnapshot(sibling, siblingVersion);
            } else {
                engine.acquire("ui", sibling, "refresh", siblingVersion, answer::set, error -> { throw new RuntimeException(error); });
                Map<String, Object> refresh = answer.get();
                engine.finish("ui", sibling, (String)refresh.get("lease"), "release", null);
                check(disk.data.get(sibling + ".retired").contains((String)refresh.get("writeSlot")), "Healthy sibling lifecycle write persists its cleanup reference.");
            }
            boolean fenced = false;
            try { acquire(engine, "ui", "read", null); } catch (RuntimeException expected) { fenced = true; }
            check(fenced, "Sibling " + write + " write does not clear the failed connection's fence.");
            ConnectionCacheEngine coldEngine = new ConnectionCacheEngine(disk);
            Map<String, Object> cold = acquire(coldEngine, "cold", "read", null);
            check("pending".equals(cold.get("mode")) && !cold.containsKey("slot") && uncertainSlot.equals(cold.get("pendingSlot")), "Restart after sibling " + write + " write cannot select the candidate.");
            check(pending.get("generation").equals(cold.get("generation")) && pending.get("revision").equals(cold.get("revision"))
                && original.get("slot").equals(cold.get("previousSlot")) && original.get("identity").equals(cold.get("previousIdentity")), "Restart retains the confirmed pending barrier and prior credential.");
            finish(coldEngine, "cold", cold, "release");
            coldEngine.acquire("cold", sibling, "read", null, answer::set, error -> { throw new RuntimeException(error); });
            Map<String, Object> coldSibling = answer.get();
            check(siblingActive.get("slot").equals(coldSibling.get("slot")) && siblingVersion.get("generation").equals(coldSibling.get("generation"))
                && siblingVersion.get("revision").equals(coldSibling.get("revision")) && ID.equals(coldSibling.get("identity")), "Sibling credential survives restart unchanged.");
            if ("clear".equals(write)) {
                check(!coldEngine.valid(sibling, siblingVersion) && !coldSibling.containsKey("snapshotAt")
                    && coldEngine.readSnapshot(sibling, version(coldSibling)) == null, "Sibling clear persists and invalidates the old cache epoch.");
            } else {
                check(coldEngine.valid(sibling, siblingVersion) && ("snapshot".equals(write) ? "updated" : "retained").equals(coldEngine.readSnapshot(sibling, siblingVersion)), "Sibling cache survives restart with its original version.");
                check(("snapshot".equals(write) ? "2002" : "1001").equals(coldSibling.get("snapshotAt"))
                    && "microseconds".equals(coldSibling.get("snapshotTimeUnit")), "Sibling success timestamp survives restart exactly.");
            }
            coldEngine.finish("cold", sibling, (String)coldSibling.get("lease"), "release", null);
            Map<String, Object> retry = acquire(engine, "ui", "reconnect", null); finish(engine, "ui", retry, "release");
            check(original.get("slot").equals(acquire(engine, "ui", "cancel", version(retry)).get("slot")), "Explicit recovery after a sibling write preserves the confirmed prior credential.");
            check(engine.valid(C, version(login(engine))), "Successful reconnect remains usable after sibling-write recovery.");
        }
    }

    static void emptyPriorStateSurvivesSiblingWrite() {
        MemoryUpdatingDisk disk = new MemoryUpdatingDisk(); ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
        Map<String, String> v = version(login(engine));
        String empty = "cursor.plan";
        AtomicReference<Map<String, Object>> answer = new AtomicReference<>(); AtomicReference<Exception> failure = new AtomicReference<>();
        disk.fail = true;
        engine.acquire("ui", empty, "reconnect", null, answer::set, failure::set);
        check(failure.get() != null && "pending".equals(disk.data.get(empty + ".mode")), "First failed barrier is visible in memory over an empty prior namespace.");
        disk.fail = false;
        check(engine.writeSnapshot(C, v, "retained", 1001), "Healthy sibling writes beside an empty fenced namespace.");
        check(disk.data.keySet().stream().noneMatch(key -> key.startsWith(empty + ".")), "Sibling write preserves an empty prior namespace without a synthetic legacy record.");
        ConnectionCacheEngine coldEngine = new ConnectionCacheEngine(disk);
        coldEngine.acquire("cold", empty, "read", null, answer::set, error -> { throw new RuntimeException(error); });
        check("legacy".equals(answer.get().get("mode")), "Empty namespace retains the ordinary legacy default after restart.");
        coldEngine.finish("cold", empty, (String)answer.get().get("lease"), "release", null);
    }

    static void activeBackupCleanupProtection() {
        Disk disk = new Disk(); ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
        Map<String, Object> migration = acquire(engine, "ui", "read", null);
        engine.prepareMigration("ui", C, (String)migration.get("lease"));
        Map<String, Object> migrated = finish(engine, "ui", migration, "activate");
        Map<String, Object> pending = acquire(engine, "ui", "reconnect", null); finish(engine, "ui", pending, "release");
        Map<String, Object> restored = acquire(engine, "ui", "cancel", version(pending));
        String legacy = "wardpulse.codex.account-session";
        check("active".equals(restored.get("mode")) && migrated.get("slot").equals(restored.get("slot"))
                && pending.get("generation").equals(restored.get("generation")) && legacy.equals(restored.get("backupKey"))
                && restored.get("slot").equals(restored.get("backupSlot")) && pending.get("generation").equals(restored.get("backupGeneration"))
                && restored.get("revision").equals(restored.get("backupRevision")),
            "Cancellation reply restores the slot and guarded backup under the reconnect generation.");
        Map<String, Object> read = acquire(engine, "cold", "read", null);
        @SuppressWarnings("unchecked") java.util.List<String> cleanup = (java.util.List<String>)read.get("cleanupSlots");
        check(!cleanup.contains(legacy), "Cancelled reconnect active backup is excluded from cleanup enumeration.");
        engine.acknowledgeCleanup("cold", C, (String)read.get("lease"), java.util.List.of(legacy));
        check(disk.data.get(C + ".retired").contains(legacy), "Acknowledgement cannot remove the protected active backup reference.");
        finish(engine, "cold", read, "release");
    }

    static void timestampPrecisionAndLegacyUpgrade() {
        Disk disk = new MemoryUpdatingDisk(); ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
        Map<String, String> version = version(login(engine));
        check(engine.writeSnapshot(C, version, "newer", 1001), "New microsecond snapshot persists.");
        check(!engine.writeSnapshot(C, version, "older", 1000), "One-microsecond older write is refused.");
        disk.data.remove(C + ".snapshotTimeUnit"); disk.data.put(C + ".snapshotAt", "1");
        disk.data.remove(C + ".snapshotWriteId");
        Map<String, Object> legacy = engine.readSnapshotPair(C, version);
        Map<String, Map<String, Object>> legacyPayload = Map.of(C,
            Map.of("era", 0L, "generatedAt", 1001L, "rowId", legacy.get("rowId")));
        Map<String, Map<String, String>> versions = Map.of(C, version);
        check("newer".equals(new ConnectionCacheEngine(disk).readSnapshot(C, version)), "Legacy millisecond records remain readable after restart.");
        check(engine.upgradeSnapshotTimestamp(C, version, "newer", 1001), "Legacy ordering upgrades from parsed original timestamp.");
        check(legacy.get("order").equals(engine.readSnapshotPair(C, version).get("order"))
                && engine.validAll(versions, Map.of(), legacyPayload, Map.of()),
            "Timestamp precision upgrades retain the same paired payload identity.");
        check(!engine.writeSnapshot(C, version, "older", 1000)
                && engine.validAll(versions, Map.of(), legacyPayload, Map.of()),
            "Legacy upgrade retains submillisecond ordering and the confirmed row proof.");
        disk.fail = true;
        check(!engine.writeSnapshot(C, version, "unconfirmed", 1001)
                && engine.validAll(versions, Map.of(), legacyPayload, Map.of()),
            "A failed equal-time write leaves the confirmed legacy row current.");
        disk.fail = false;
        check(engine.writeSnapshot(C, version, "equal-time replacement", 1001)
                && !engine.validAll(versions, Map.of(), legacyPayload, Map.of()),
            "A committed equal-time write retires the earlier row proof.");
        Map<String, Map<String, Object>> replacement = Map.of(C,
            Map.of("era", 0L, "generatedAt", 1001L, "rowId", engine.readSnapshotPair(C, version).get("rowId")));
        ConnectionCacheEngine cold = new ConnectionCacheEngine(disk);
        check(cold.validAll(versions, Map.of(), replacement, Map.of())
                && !cold.validAll(versions, Map.of(), legacyPayload, Map.of()),
            "The new row proof survives recreation within the same cache epoch.");
        engine.writeSnapshot(C, version, "latest", 1002);
        check(!engine.upgradeSnapshotTimestamp(C, version, "newer", 1001), "Delayed metadata upgrade cannot replace newer payload.");
        check("latest".equals(engine.readSnapshot(C, version)), "Metadata upgrade race leaves newer payload intact.");
        Map<String, Map<String, Object>> latest = Map.of(C,
            Map.of("era", 0L, "generatedAt", 1002L, "rowId", engine.readSnapshotPair(C, version).get("rowId")));
        check(engine.validAll(versions, Map.of(), latest, Map.of()), "The latest row validates before clearing.");
        engine.clearSnapshot(C, version);
        check(!engine.validAll(versions, Map.of(), latest, Map.of()),
            "A successful clear retires row proofs from the previous epoch.");
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
        Map<String, Object> restored = acquire(engine, "ui", "cancel", version(pending));
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
        check(Map.of("eventId", event, "dismissed", false).equals(engine.readNotice(C)), "Reconnect alone preserves the visible warning.");
        Map<String, Object> deletion = acquire(engine, "ui", "delete", null); finish(engine, "ui", deletion, "release");
        check(Map.of("eventId", event, "dismissed", false).equals(new ConnectionCacheEngine(disk).readNotice(C)),
            "Ordinary disconnect and restart preserve the visible warning.");
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
    private static final class UncertainDisk extends MemoryUpdatingDisk {
        boolean throwsFailure;
        @Override public boolean commit(Map<String, String> values) {
            boolean committed = super.commit(values);
            if (!committed && throwsFailure) throw new IllegalStateException("Synthetic storage failure.");
            return committed;
        }
    }
    static void noticeFailures() {
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

    static void verifiedReconnectRetiresNotice() {
        Disk disk = new Disk();
        ConnectionCacheEngine engine = new ConnectionCacheEngine(disk, () -> 1000L);
        Map<String, String> old = version(login(engine));
        String oldStamp = releasedStamp(engine, "worker", old);
        check(rejection(engine, "worker", C, old, false), "Original rejection is recorded.");
        Map<String, Object> previousNotice = engine.readNotice(C);
        String event = (String) previousNotice.get("eventId");
        check(event != null && Boolean.FALSE.equals(previousNotice.get("dismissed")), "Original notice is visible.");
        String sibling = "cursor.plan";
        check(rejection(engine, "worker", sibling, version(login(engine, sibling)), false), "Sibling rejection is recorded.");
        Map<String, Object> siblingNotice = engine.readNotice(sibling);

        Map<String, Object> replacement = login(engine);
        Map<String, String> current = version(replacement);
        check(!event.equals(replacement.get("committedConnection")), "Reconnect commits a new identity for the same principal.");
        check(previousNotice.equals(engine.readNotice(C)), "Reconnect alone leaves the earlier notice visible.");
        check("superseded".equals(engine.writeSnapshotOrdered("worker", C, old, "retired", 1000000L, oldStamp).get("status"))
                && "superseded".equals(engine.writeSnapshotOrdered("worker", C, current, "stale-stamp", 1000000L, oldStamp).get("status")),
            "A retired credential and its stamp cannot write for the replacement.");
        check(engine.writeSnapshot(C, current, "unstamped", 1000000L)
                && "unstamped".equals(engine.readSnapshot(C, current)) && previousNotice.equals(engine.readNotice(C)),
            "An unstamped write and cache read leave the earlier notice visible.");
        String stamp = releasedStamp(engine, "worker", current);
        check("older".equals(engine.writeSnapshotOrdered("worker", C, current, "older", 999999L, stamp).get("status"))
                && previousNotice.equals(engine.readNotice(C)), "An older stamped report leaves the earlier notice visible.");
        check("stored".equals(engine.writeSnapshotOrdered("worker", C, current, "verified", 1000000L, stamp).get("status")),
            "The replacement's stamped report is stored.");
        ConnectionCacheEngine cold = new ConnectionCacheEngine(disk);
        check("verified".equals(cold.readSnapshot(C, current)), "A cold read sees the replacement snapshot.");
        check(Map.of("eventId", event, "dismissed", true).equals(cold.readNotice(C)),
            "The stored replacement report retires the earlier notice and preserves its event ID.");
        check(siblingNotice.equals(cold.readNotice(sibling)), "The sibling notice stays visible.");

        String lateStamp = releasedStamp(engine, "worker", current);
        check(rejection(engine, "worker", C, current, false), "The replacement can record a new rejection.");
        String newEvent = (String) replacement.get("committedConnection");
        check("stored".equals(engine.writeSnapshotOrdered("worker", C, current, "late", 1000001L, lateStamp).get("status")),
            "A late report for the same committed connection can still update its cache.");
        check(Map.of("eventId", newEvent, "dismissed", false).equals(engine.readNotice(C)) && !engine.dismissNotice(C, event),
            "Neither a report for the rejected identity nor an old X can hide the new rejection.");
        check(engine.dismissNotice(C, newEvent), "Manual X still dismisses the current event.");
        check("stored".equals(engine.writeSnapshotOrdered("worker", C, current, "after-x", 1000002L, lateStamp).get("status"))
                && Map.of("eventId", newEvent, "dismissed", true).equals(new ConnectionCacheEngine(disk).readNotice(C)),
            "A later write preserves the manual dismissal after restart.");
    }

    static void failedReconnectReportPreservesConfirmedState() {
        for (boolean throwsFailure : new boolean[]{false, true}) {
            UncertainDisk disk = new UncertainDisk();
            ConnectionCacheEngine engine = new ConnectionCacheEngine(disk, () -> 1000L);
            check(rejection(engine, "worker", C, version(login(engine)), false), "Original rejection is recorded.");
            Map<String, Object> notice = engine.readNotice(C);
            Map<String, String> current = version(login(engine));
            String sibling = "cursor.plan";
            Map<String, String> siblingVersion = version(login(engine, sibling));
            check(engine.writeSnapshot(C, current, "confirmed", 1000000L), "An unstamped cache row is confirmed.");
            Map<String, String> confirmed = snapshotFields(disk);
            String stamp = releasedStamp(engine, "worker", current);

            disk.throwsFailure = throwsFailure;
            disk.fail = true;
            check("storageFailure".equals(engine.writeSnapshotOrdered("worker", C, current, "unconfirmed", 1000001L, stamp).get("status")),
                "The replacement report can fail at the backend commit.");
            check("unconfirmed".equals(disk.data.get(C + ".snapshot")) && "true".equals(disk.data.get(C + ".rejectionDismissed")),
                "The failed whole-map write exposed both proposed fields in backend memory.");
            check("confirmed".equals(engine.readSnapshot(C, current)) && notice.equals(engine.readNotice(C)),
                "The live engine exposes only the confirmed snapshot and notice after failure.");

            disk.fail = false;
            check(engine.writeSnapshot(sibling, siblingVersion, "sibling", 1000000L), "A sibling can still commit.");
            ConnectionCacheEngine cold = new ConnectionCacheEngine(disk);
            check(confirmed.equals(snapshotFields(disk)) && "confirmed".equals(cold.readSnapshot(C, current))
                    && notice.equals(cold.readNotice(C)) && "sibling".equals(cold.readSnapshot(sibling, siblingVersion)),
                "A sibling commit persists neither part of the failed write across restart.");
        }
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
    private static String releasedStamp(ConnectionCacheEngine engine, String owner, Map<String, String> version) {
        String ticket = fetch(engine, owner);
        String stamp = (String) engine.stampFetch(owner, C, ticket, version).get("stamp");
        engine.releaseFetch(owner, C, ticket);
        return stamp;
    }
    static String boundFetch(ConnectionCacheEngine engine, String owner, long generation) {
        AtomicReference<Map<String, Object>> answer = new AtomicReference<>();
        engine.acquireFetch(owner, C, generation, answer::set, error -> { throw new AssertionError(error); });
        return (String)answer.get().get("fetchTicket");
    }
    /** A committed switch, or `null` while admitted effects still drain. */
    static Map<String, Object> switchMode(ConnectionCacheEngine engine, String owner, String mode) {
        AtomicReference<Map<String, Object>> answer = new AtomicReference<>();
        engine.switchMode(owner, mode, answer::set, error -> { throw new AssertionError(error); });
        return answer.get();
    }
    static void dataModeAuthority() {
        Disk modes = new Disk(); long[] now = {1000};
        ConnectionCacheEngine engine = new ConnectionCacheEngine(new Disk(), modes, () -> now[0], true);
        check(Boolean.FALSE.equals(engine.readMode().get("initialized")), "A fresh install has no mode record.");
        boolean closed = false;
        try { engine.beginOperation(); } catch (IllegalStateException expected) { closed = true; }
        check(closed, "Operations wait for the mode record.");
        Map<String, Object> first = engine.initializeMode(true);
        check("mock".equals(first.get("mode")) && Long.valueOf(0).equals(first.get("generation")), "Debug migrates a legacy Mock choice.");
        Map<String, Object> again = engine.initializeMode(false);
        check(first.get("installId").equals(again.get("installId")) && "mock".equals(again.get("mode")),
            "Migration runs only while the record is absent.");
        check(!engine.beginOperation().get("requestId").equals(engine.beginOperation().get("requestId")),
            "Every operation has its own request ID.");

        ConnectionCacheEngine release = new ConnectionCacheEngine(new Disk(), new Disk(), () -> now[0], false);
        check("live".equals(release.initializeMode(true).get("mode")), "Production startup ignores a legacy Mock key.");
        boolean rejected = false;
        try { release.switchMode("ui", "mock", ignored -> {}, ignored -> {}); } catch (IllegalArgumentException expected) { rejected = true; }
        check(rejected, "Production rejects Mock.");

        // Both isolates share one monitor: a held OAuth rotation settles before the switch.
        String held = engine.enterEffect("headless", 0L);
        check(held != null, "The current generation admits a short effect.");
        AtomicReference<Map<String, Object>> switched = new AtomicReference<>();
        engine.switchMode("foreground", "live", switched::set, error -> { throw new AssertionError(error); });
        check(switched.get() == null && "mock".equals(engine.readMode().get("mode")), "A switch waits for an admitted effect.");
        check(engine.enterEffect("headless", 0L) == null && !engine.operationCurrent(0L), "Admission closes before the switch.");
        boolean draining = false;
        try { engine.beginOperation(); } catch (IllegalStateException expected) { draining = true; }
        check(draining, "No operation begins while a switch drains.");
        Map<String, String> version = version(login(engine));
        String ticket = fetch(engine, "legacy");
        check(claim(engine, "legacy", ticket, version, 300000), "A scoped switch leaves unscoped cadence available.");
        engine.releaseFetch("legacy", C, ticket);
        engine.exitEffect("headless", held, true);
        check("live".equals(switched.get().get("mode")) && Long.valueOf(1).equals(switched.get().get("generation")),
            "The settled effect lets the switch commit.");
        check(Boolean.TRUE.equals(switched.get().get("unresolved")), "Unresolved rotation storage reaches the switch.");

        // Live -> synthetic -> Live retires every earlier generation.
        check(Long.valueOf(2).equals(switchMode(engine, "foreground", "demo").get("generation")), "Demo advances the generation.");
        Map<String, Object> live = switchMode(engine, "foreground", "live");
        check(Long.valueOf(3).equals(live.get("generation")) && Boolean.FALSE.equals(live.get("unresolved")),
            "Returning to Live advances again without stale failures.");
        check(!engine.operationCurrent(1L) && engine.operationCurrent(3L), "Earlier Live operations stay retired.");
        check(Long.valueOf(3).equals(switchMode(engine, "foreground", "live").get("generation")), "The same mode keeps its generation.");

        modes.fail = true;
        AtomicReference<Exception> failed = new AtomicReference<>();
        engine.switchMode("foreground", "mock", ignored -> { throw new AssertionError("Failed write committed."); }, failed::set);
        modes.fail = false;
        check(failed.get() != null && "live".equals(engine.readMode().get("mode")) && engine.operationCurrent(3L),
            "A failed mode write keeps the old record and generation.");

        ConnectionCacheEngine restarted = new ConnectionCacheEngine(new Disk(), modes, () -> now[0], true);
        Map<String, Object> view = restarted.readMode();
        check(first.get("installId").equals(view.get("installId")) && "live".equals(view.get("mode"))
            && Long.valueOf(3).equals(view.get("generation")), "Restart keeps install, mode and generation.");

        String stranded = engine.enterEffect("headless", 3L);
        check(stranded != null && switchMode(engine, "foreground", "mock") == null, "A detached isolate's effect holds the switch.");
        engine.detach("headless");
        check("mock".equals(engine.readMode().get("mode")), "Detach drains a dead isolate's effects.");

        check(Boolean.FALSE.equals(switchMode(engine, "foreground", "live").get("unresolved")),
            "A dropped short effect is not an unresolved rotation.");
        // A detached isolate's sent OAuth refresh can no longer store its rotation.
        check(engine.enterEffect("headless", 5L, true) != null, "A sent refresh holds a settlement lease.");
        AtomicReference<Map<String, Object>> dropped = new AtomicReference<>();
        engine.switchMode("foreground", "demo", dropped::set, error -> { throw new AssertionError(error); });
        engine.detach("headless");
        check(Boolean.TRUE.equals(dropped.get().get("unresolved")), "A dropped settlement is reported unresolved.");
    }
    static void modePolicyWriteFailure() {
        MemoryUpdatingDisk modes = new MemoryUpdatingDisk();
        ConnectionCacheEngine debug = new ConnectionCacheEngine(new Disk(), modes, () -> 1000L, true);
        Map<String, Object> mock = debug.initializeMode(true);
        ConnectionCacheEngine production = new ConnectionCacheEngine(new Disk(), modes, () -> 1000L, false);

        modes.fail = true;
        boolean failed = false;
        try { production.beginOperation(); } catch (IllegalStateException expected) { failed = true; }
        check(failed && "live".equals(modes.data.get("mode")), "A failed migration may expose Live in storage memory only.");
        failed = false;
        try { production.initializeMode(false); } catch (IllegalStateException expected) { failed = true; }
        check(failed, "Initialization cannot adopt the unconfirmed Live record or replace the install.");

        modes.fail = false;
        Map<String, Object> live = production.beginOperation();
        check("live".equals(live.get("mode")) && mock.get("installId").equals(live.get("installId"))
            && Long.valueOf(1).equals(live.get("generation")), "Only a successful write admits the next generation.");
        check(!production.operationCurrent(0L), "The migrated record retires the original Mock generation.");
    }
    static void legacyWatchRefreshAdmission() {
        ConnectionCacheEngine engine = new ConnectionCacheEngine(new Disk());
        byte[] empty = new byte[0];
        check(engine.captureLegacyWatchRefresh(empty) == null, "An uninitialized phone resends only.");
        Map<String, Object> initial = engine.initializeMode(false);
        check(engine.captureLegacyWatchRefresh(new byte[]{1}) == null, "An unknown payload resends only.");
        Map<String, Object> tap = engine.captureLegacyWatchRefresh(empty);
        check(initial.get("installId").equals(tap.get("installId")) && Long.valueOf(0).equals(tap.get("generation"))
            && tap.get("requestId") instanceof String, "An owned empty tap captures its operation before launch.");
        String held = engine.enterEffect("headless", 0L);
        check(held != null && switchMode(engine, "foreground", "mock") == null, "A held effect delays the switch.");
        check(engine.captureLegacyWatchRefresh(empty) == null, "Draining admission makes a tap resend-only.");
        engine.exitEffect("headless", held, false);
        switchMode(engine, "foreground", "live");
        check(engine.captureLegacyWatchRefresh(empty) == null && !engine.operationCurrent(0L),
            "Returning to Live cannot renew legacy refresh authority.");
    }

    static void waitingWearResendCapturesSettledMode() {
        ConnectionCacheEngine engine = new ConnectionCacheEngine(new Disk());
        engine.initializeMode(false);
        String lease = engine.enterEffect("headless", 0L);
        switchMode(engine, "foreground", "mock");
        switchMode(engine, "foreground", "live");
        AtomicReference<Map<String, Object>> result = new AtomicReference<>();
        engine.beginAfterSwitch("watch", result::set, error -> { throw new AssertionError(error); });
        engine.beginAfterSwitch("detaching", ignored -> { throw new AssertionError("Detached wait was delivered."); },
            error -> { throw new AssertionError(error); });
        engine.detach("detaching");
        check(result.get() == null, "A resend waits through the drain.");
        engine.exitEffect("headless", lease, false);
        check("live".equals(result.get().get("mode")) && Long.valueOf(2L).equals(result.get().get("generation")),
            "Queued admission captures the generation after both switches settle.");
    }

    static void widgetDeliveryRequiresCurrentMode() {
        ConnectionCacheEngine engine = new ConnectionCacheEngine(new Disk());
        Map<String, Object> mode = engine.initializeMode(false);
        String install = (String) mode.get("installId");
        AtomicReference<String> delivered = new AtomicReference<>();
        engine.deliverWidgetIfModeCurrent(install, 0L, () -> delivered.set("initial"));
        check("initial".equals(delivered.get()), "Current launcher rows can be delivered.");
        switchMode(engine, "foreground", "mock");
        switchMode(engine, "foreground", "live");
        engine.deliverWidgetIfModeCurrent(install, 0L, () -> delivered.set("retired"));
        engine.deliverWidgetIfModeCurrent("other-install", 2L, () -> delivered.set("unowned"));
        check("initial".equals(delivered.get()), "Retired rendered rows cannot reach the launcher.");
        engine.deliverWidgetIfModeCurrent(install, 2L, () -> delivered.set("replacement"));
        check("replacement".equals(delivered.get()), "Current replacement reaches the launcher.");
        String lease = engine.enterEffect("headless", 2L);
        AtomicReference<Map<String, Object>> switched = new AtomicReference<>();
        engine.switchMode("foreground", "mock", switched::set, error -> { throw new AssertionError(error); });
        engine.deliverWidgetIfModeCurrent(install, 2L, () -> delivered.set("draining"));
        check(switched.get() == null && "replacement".equals(delivered.get()),
            "A redraw during a held drain cannot publish the outgoing generation.");
        engine.exitEffect("headless", lease, false);
        check(Long.valueOf(3L).equals(switched.get().get("generation")), "The drained switch commits.");
        engine.deliverWidgetIfModeCurrent(install, 3L, () -> delivered.set("settled"));
        check("settled".equals(delivered.get()), "A current redraw after the switch settles reaches the launcher.");
    }
    static void recoveryPreferenceAdmission() {
        ConnectionCacheEngine engine = new ConnectionCacheEngine(new Disk());
        Map<String, String> v = version(login(engine));
        Map<String, Map<String, String>> all = new HashMap<>(); all.put(C, v);
        Map<String, Long> eras = new HashMap<>();
        Map<String, Map<String, Object>> payloads = new HashMap<>();
        Map<String, String> empty = new HashMap<>();
        Long settled = engine.readRecoveryPreferenceRevision();
        check(settled != null && engine.validAll(all, eras, payloads, empty, settled, null),
            "A settled recovery choice admits with current provenance.");
        String save = engine.beginRecoveryPreferenceWrite("foreground");
        check(engine.readRecoveryPreferenceRevision() == null, "A save in flight has no readable revision.");
        check(!engine.validAll(all, eras, payloads, empty, settled, null), "A save in flight refuses admission.");
        engine.finishRecoveryPreferenceWrite("headless", save);
        check(engine.readRecoveryPreferenceRevision() == null, "Only the saving engine finishes its save.");
        engine.finishRecoveryPreferenceWrite("foreground", save);
        Long saved = engine.readRecoveryPreferenceRevision();
        check(saved != null && !saved.equals(settled) && !engine.validAll(all, eras, payloads, empty, settled, null),
            "A finished save retires an earlier read.");
        check(engine.validAll(all, eras, payloads, empty, saved, null) && engine.recoveryDeliveryCurrent(saved, null),
            "A read after the save admits.");
        Map<String, String> wrong = new HashMap<>(v); wrong.put("identity", "b".repeat(64)); all.put(C, wrong);
        check(!engine.validAll(all, eras, payloads, empty, saved, null), "Retired provenance refuses a current choice.");
        engine.beginRecoveryPreferenceWrite("foreground");
        engine.detach("foreground");
        Long detached = engine.readRecoveryPreferenceRevision();
        check(detached != null && !detached.equals(saved), "A detached save releases readers with a new revision.");
        all.put(C, v);
        engine.initializeMode(false);
        check(engine.validAll(all, eras, payloads, empty, detached, 0L), "The current Live generation admits.");
        String lease = engine.enterEffect("headless", 0L);
        AtomicReference<Map<String, Object>> switched = new AtomicReference<>();
        engine.switchMode("foreground", "mock", switched::set, error -> { throw new AssertionError(error); });
        check(!engine.validAll(all, eras, payloads, empty, detached, 0L)
                && !engine.recoveryDeliveryCurrent(detached, 0L),
            "A switch draining the batch lease refuses a new recovery post.");
        check(engine.validAll(all, eras, payloads, empty, detached, null),
            "Provenance alone is unchanged by the switch.");
        engine.exitEffect("headless", lease, false);
        check(switched.get() != null && !engine.validAll(all, eras, payloads, empty, detached, 1L),
            "A synthetic generation refuses recovery posts.");
        switchMode(engine, "foreground", "live");
        check(!engine.validAll(all, eras, payloads, empty, detached, 0L)
                && engine.validAll(all, eras, payloads, empty, detached, 2L),
            "Only the new Live generation admits.");
    }
    static void unrecordedRecoveriesSpanEngines() {
        ConnectionCacheEngine engine = new ConnectionCacheEngine(new Disk());
        engine.recordUnrecordedRecoveries(List.of("first", "second"));
        engine.detach("foreground");
        check(engine.readUnrecordedRecoveries().containsAll(List.of("first", "second")),
            "Unrecorded posts outlive the engine that submitted them.");
        engine.forgetUnrecordedRecoveries(List.of("first"));
        check(engine.readUnrecordedRecoveries().equals(List.of("second")), "A recorded occurrence is forgotten alone.");
    }
    static void dataModeFetchFencing() {
        long[] now = {1000};
        ConnectionCacheEngine engine = new ConnectionCacheEngine(new Disk(), new Disk(), () -> now[0], true);
        engine.initializeMode(false);
        Map<String, String> v = version(login(engine));
        String ticket = boundFetch(engine, "foreground", 0L);
        Map<String, Object> cacheOnly = engine.claimAutomatic("foreground", C, ticket, v, 300000, true);
        check(Boolean.FALSE.equals(cacheOnly.get("admitted")) && !cacheOnly.containsKey("automaticAt"),
            "Cache-only startup neither admits nor anchors a poll.");
        check(claim(engine, "foreground", ticket, v, 300000), "Cache-only startup leaves cadence available.");
        // The admitted attempt failed to connect; it still counts.
        engine.releaseFetch("foreground", C, ticket, null); now[0]++;
        ticket = boundFetch(engine, "headless", 0L);
        Map<String, Object> denied = engine.claimAutomatic("headless", C, ticket, v, 300000, false);
        check(Boolean.FALSE.equals(denied.get("admitted")) && Long.valueOf(301000).equals(denied.get("nextEligible")),
            "Cadence denial follows an admitted connection failure.");
        // Cache-only, admitted and denied claims share one native observation order.
        check((Long) cacheOnly.get("sample") < (Long) denied.get("sample") - 1L,
            "Native cadence samples follow claim order.");
        engine.releaseFetch("headless", C, ticket, null);

        now[0] += 300000;
        ticket = boundFetch(engine, "foreground", 0L);
        check(claim(engine, "foreground", ticket, v, 300000), "A due poll is admitted.");
        Map<String, Object> stamp = engine.stampFetch("foreground", C, ticket, v);
        // Retirement during transport setup.
        check(switchMode(engine, "ui", "mock") != null, "No send was initiated, so the switch commits.");
        check(!engine.validFetch("foreground", C, ticket) && engine.enterEffect("foreground", 0L) == null,
            "A retired fetch cannot initiate its send after setup.");
        boolean superseded = false;
        try { engine.stampFetch("foreground", C, ticket, v); } catch (IllegalStateException expected) { superseded = true; }
        check(superseded, "A retired fetch cannot stamp.");
        AtomicReference<Exception> rejection = new AtomicReference<>();
        engine.acquire("foreground", C, "reject", v, ticket, ignored -> {}, rejection::set);
        check(rejection.get() != null && engine.readNotice(C).isEmpty(), "A retired fetch cannot reject its credential.");
        // Retirement before native release.
        check("superseded".equals(engine.writeSnapshotOrdered("foreground", C, v, "late", 2000000L,
            (String)stamp.get("stamp")).get("status")), "A retired stamp cannot publish.");
        engine.releaseFetch("foreground", C, ticket, 999999999L);
        boolean retired = false;
        try { boundFetch(engine, "foreground", 0L); } catch (IllegalStateException expected) { retired = true; }
        check(retired, "A retired generation cannot acquire a fetch.");
        ticket = fetch(engine, "foreground");
        check(ticket != null, "The retired fetch released its reservation.");
        engine.releaseFetch("foreground", C, ticket, null);
        boolean synthetic = false;
        try { boundFetch(engine, "foreground", 1L); } catch (IllegalStateException expected) { synthetic = true; }
        check(synthetic, "Synthetic modes never acquire a provider fetch.");

        switchMode(engine, "ui", "live");
        ticket = boundFetch(engine, "foreground", 2L);
        AtomicReference<Map<String, Object>> queued = new AtomicReference<>();
        AtomicReference<Exception> retiredQueue = new AtomicReference<>();
        engine.acquireFetch("headless", C, 2L, queued::set, retiredQueue::set);
        check(queued.get() == null, "A second engine's fetch waits for ownership.");
        switchMode(engine, "ui", "demo");
        switchMode(engine, "ui", "live");
        engine.releaseFetch("foreground", C, ticket, null);
        check(queued.get() == null && retiredQueue.get() != null, "A queued fetch retired by a switch is failed, not granted.");
        ticket = boundFetch(engine, "headless", 4L);
        check(ticket != null, "Current work acquires after the retired queue.");
        engine.releaseFetch("headless", C, ticket, null);

        ticket = boundFetch(engine, "foreground", 4L);
        Map<String, Object> fresh = engine.stampFetch("foreground", C, ticket, v);
        check("stored".equals(engine.writeSnapshotOrdered("foreground", C, v, "fresh", 3000L,
            (String)fresh.get("stamp")).get("status")), "A current Live stamp publishes.");
        engine.releaseFetch("foreground", C, ticket, 3L);
    }
    static void scopedCredentialAdmission() {
        ConnectionCacheEngine engine = new ConnectionCacheEngine(new Disk());
        engine.initializeMode(false);
        String ticket = boundFetch(engine, "worker", 0L);
        AtomicReference<Map<String, Object>> read = new AtomicReference<>();
        engine.acquire("worker", C, "read", null, ticket, read::set, error -> { throw new AssertionError(error); });
        check(read.get() != null, "A scoped read can enter secure storage in Live.");

        AtomicReference<Map<String, Object>> queued = new AtomicReference<>();
        AtomicReference<Exception> retired = new AtomicReference<>();
        engine.acquire("worker", C, "read", null, ticket, queued::set, retired::set);
        check(queued.get() == null && retired.get() == null, "The second read waits for credential ownership.");
        AtomicReference<Map<String, Object>> queuedCapture = new AtomicReference<>();
        AtomicReference<Exception> retiredCapture = new AtomicReference<>();
        engine.acquire("cache", C, "read", null, null, 0L, null, queuedCapture::set, retiredCapture::set);
        check(queuedCapture.get() == null && retiredCapture.get() == null, "Cache capture also waits for credential ownership.");
        AtomicReference<Map<String, Object>> switched = new AtomicReference<>();
        engine.switchMode("ui", "demo", switched::set, error -> { throw new AssertionError(error); });
        check(switched.get() == null, "The switch waits for the admitted storage transaction.");

        finish(engine, "worker", read.get(), "release");
        check(switched.get() != null && "demo".equals(switched.get().get("mode")),
            "Finishing storage drains the switch while the fetch is still held.");
        check(queued.get() == null && retired.get() != null, "A queued read rechecks ownership before touching storage.");
        check(queuedCapture.get() == null && retiredCapture.get() != null,
            "A queued cache capture rechecks its generation without a fetch ticket.");
        finish(engine, "ui", acquire(engine, "ui", "read", null), "release");
        check(!engine.releaseFetch("worker", C, ticket, null), "The retired fetch can still release its reservation.");

        switchMode(engine, "ui", "live");
        String nextTicket = boundFetch(engine, "worker", 2L);
        read.set(null);
        engine.acquire("worker", C, "read", null, nextTicket, read::set, error -> { throw new AssertionError(error); });
        check(read.get() != null && switchMode(engine, "ui", "demo") == null,
            "An admitted read holds the mode switch until its engine detaches.");
        engine.detach("worker");
        check("demo".equals(engine.readMode().get("mode")), "Detach releases the scoped storage lease.");
    }
    static void scopedSnapshotMaintenance() {
        Disk disk = new Disk();
        ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
        engine.initializeMode(false);
        Map<String, String> version = version(login(engine));
        engine.writeSnapshot(C, version, "retained", 1000L);
        disk.data.remove(C + ".snapshotTimeUnit");
        disk.data.put(C + ".snapshotAt", "1");
        switchMode(engine, "ui", "demo");
        switchMode(engine, "ui", "live");

        Map<String, String> legacy = snapshotFields(disk);
        check(!engine.upgradeSnapshotTimestamp(C, version, "retained", 1000L, 0L),
            "A retired scope cannot upgrade timestamp metadata even for identical bytes.");
        check("superseded".equals(engine.writeSnapshotOrdered("worker", C, version, "late", 2000L, null, 0L).get("status"))
                && legacy.equals(snapshotFields(disk)), "A retired scope cannot overwrite an unstamped cache row.");
        check(engine.upgradeSnapshotTimestamp(C, version, "retained", 1000L, 2L),
            "Current Live can still upgrade legacy timestamp precision.");

        disk.data.put(C + ".snapshotVersion", "future");
        Map<String, String> unsupported = snapshotFields(disk);
        check(Boolean.FALSE.equals(engine.readSnapshotPair(C, version, false, 0L).get("valid"))
                && unsupported.equals(snapshotFields(disk)) && engine.valid(C, version),
            "A retired read cannot implicitly purge unsupported data or change its epoch.");
        check(Boolean.FALSE.equals(engine.readSnapshotPair(C, version, false, 2L).get("valid"))
                && !disk.data.containsKey(C + ".snapshot") && !engine.valid(C, version),
            "Current Live still purges unsupported payloads and advances the epoch.");
    }
    static void unscopedFetchLeavesModeAbsent() {
        long[] now = {1000};
        Disk modes = new Disk() {
            @Override public Map<String, String> read() { throw new AssertionError("Unscoped work read the mode record."); }
        };
        ConnectionCacheEngine engine = new ConnectionCacheEngine(new Disk(), modes, () -> now[0], true);
        Map<String, String> v = version(login(engine));
        AtomicReference<Map<String, Object>> answer = new AtomicReference<>();
        engine.acquireFetch("ui", C, answer::set);
        String ticket = (String)answer.get().get("fetchTicket");
        check(engine.validFetch("ui", C, ticket) && claim(engine, "ui", ticket, v, 300000),
            "An unscoped poll is admitted without a mode record.");
        Map<String, Object> stamp = engine.stampFetch("ui", C, ticket, v);
        check("stored".equals(engine.writeSnapshotOrdered("ui", C, v, "unscoped", 2000L, (String)stamp.get("stamp")).get("status")),
            "An unscoped stamp publishes.");
        engine.releaseFetch("ui", C, ticket, 2L);
        String forged = "1:" + ticket + ":" + UUID.randomUUID();
        check("superseded".equals(engine.writeSnapshotOrdered("ui", C, v, "forged", 3000L, forged).get("status")),
            "An invalid unscoped stamp is rejected without reading the mode record.");
        check(modes.data.isEmpty(), "Unscoped work never creates the mode record.");

        // A failed first write that stays visible in memory is never adopted.
        MemoryUpdatingDisk leaky = new MemoryUpdatingDisk(); leaky.fail = true;
        ConnectionCacheEngine first = new ConnectionCacheEngine(new Disk(), leaky, () -> now[0], true);
        boolean failed = false;
        try { first.initializeMode(true); } catch (IllegalStateException expected) { failed = true; }
        check(failed && Boolean.FALSE.equals(first.readMode().get("initialized")), "A failed import leaves the record absent.");
        check(!first.operationCurrent(0L) && first.enterEffect("ui", 0L) == null,
            "The unconfirmed first generation admits no effects.");
        leaky.fail = false;
        check("live".equals(first.initializeMode(false).get("mode")), "A later start retries the import.");
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

        long correctedAt = now[0];
        long deadline = correctedAt + 900000;
        now[0] += 86400000;
        first = fetch(engine, "foreground");
        check(claim(engine, "foreground", first, v, 900000), "Automatic start is recorded a day ahead.");
        engine.releaseFetch("foreground", C, first);
        now[0] = correctedAt;
        second = fetch(engine, "headless");
        denial = engine.claimAutomatic("headless", C, second, v, 900000);
        check(Boolean.FALSE.equals(denial.get("admitted")) && Long.valueOf(deadline).equals(denial.get("nextEligible"))
            && Long.valueOf(correctedAt).equals(denial.get("automaticAt")), "Clock rollback denies with the corrected anchor and deadline.");
        engine.detach("headless");

        engine = new ConnectionCacheEngine(disk, () -> now[0]);
        cold = fetch(engine, "cold");
        now[0] = deadline - 1;
        denial = engine.claimAutomatic("cold", C, cold, v, 900000);
        check(Boolean.FALSE.equals(denial.get("admitted")) && Long.valueOf(deadline).equals(denial.get("nextEligible"))
            && Long.valueOf(correctedAt).equals(denial.get("automaticAt")), "Restart preserves the corrected anchor one millisecond before the deadline.");
        now[0] = deadline;
        check(claim(engine, "cold", cold, v, 900000), "Automatic work resumes at the corrected deadline.");
    }
    static void automaticMetadataFailure() {
        MemoryUpdatingDisk disk = new MemoryUpdatingDisk();
        long confirmedAt = 86401000;
        long[] now = {confirmedAt};
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
        now[0] = confirmedAt + 300000; disk.fail = true; denied = false;
        try { claim(engine, "worker", ticket, v, 300000); } catch (IllegalStateException expected) { denied = true; }
        disk.fail = false;
        check(Long.valueOf(confirmedAt).equals(engine.claimAutomatic("worker", C, ticket, v, 3600000).get("automaticAt")), "Denial reports only the confirmed anchor.");
        engine.writeSnapshot(C, v, "retained", 3);
        check(denied && Long.toString(confirmedAt).equals(disk.data.get(C + ".automaticAt")), "Failed update preserves confirmed anchor.");
        check(claim(engine, "worker", ticket, v, 300000), "Retry remains eligible after failed update.");

        long beforeRollback = now[0];
        now[0] -= 86400000;
        disk.fail = true; denied = false;
        try { claim(engine, "worker", ticket, v, 900000); } catch (IllegalStateException expected) { denied = true; }
        check(denied && engine.valid(C, v), "Failed rebase denies automatic work and preserves the credential.");
        check(Long.toString(now[0]).equals(disk.data.get(C + ".automaticAt")), "Backend exposes the failed rebase in memory.");
        disk.fail = false;
        check(engine.writeSnapshot(C, v, "retained", 4), "Later whole-map write succeeds.");
        check(Long.toString(beforeRollback).equals(disk.data.get(C + ".automaticAt")), "Whole-map write retains only the confirmed anchor.");
        now[0]++;
        Map<String, Object> retry = engine.claimAutomatic("worker", C, ticket, v, 900000);
        check(Boolean.FALSE.equals(retry.get("admitted")) && Long.valueOf(now[0]).equals(retry.get("automaticAt")),
            "Retry persists its own corrected sample after the failed rebase.");
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
