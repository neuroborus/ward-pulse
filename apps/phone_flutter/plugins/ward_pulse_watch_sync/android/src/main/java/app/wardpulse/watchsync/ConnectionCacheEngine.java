package app.wardpulse.watchsync;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.util.ArrayDeque;
import java.util.Arrays;
import java.util.Collections;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.function.Consumer;
import java.util.function.LongSupplier;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/** Process-wide credential leases and durable snapshot CAS; no credential values enter Java. */
public final class ConnectionCacheEngine {
    public interface Backend {
        Map<String, String> read();
        boolean commit(Map<String, String> values);
    }
    private static final Set<String> CONNECTIONS = new HashSet<>(Arrays.asList(
        "openai.plan", "openai.platform", "anthropic.plan", "anthropic.platform", "cursor.plan", "cursor.platform"));
    private static final List<String> NOTICE_KEYS = Arrays.asList("committedConnection", "rejectionEvent", "rejectionDismissed");
    private static final List<String> SNAPSHOT_KEYS = Arrays.asList(
        "snapshot", "snapshotAt", "snapshotVersion", "snapshotTimeUnit", "snapshotEra", "snapshotClockAt",
        "snapshotWriteId");
    private final Backend backend;
    private final LongSupplier clock;
    private final Map<String, Lease> leases = new HashMap<>();
    private final Map<String, ArrayDeque<Pending>> queues = new HashMap<>();
    private final Set<String> fenced = new HashSet<>();
    private final Map<String, Map<String, String>> failedCommitPriorState = new HashMap<>();
    private final Set<String> abandonedSlots = new HashSet<>();
    private final Map<String, FetchLease> fetches = new HashMap<>();
    private final Map<String, ArrayDeque<FetchPending>> fetchQueues = new HashMap<>();
    private final Map<String, ClockOrder> clockOrders = new HashMap<>();
    private final Mac stampMac = newStampMac();
    private static final List<String> MODES = Arrays.asList("live", "demo", "mock");
    private final Backend modeBackend;
    private final boolean mockAllowed;
    private Map<String, String> confirmedModeRecord;
    private final ArrayDeque<ModeImport> modeImports = new ArrayDeque<>();
    private ModeImport activeModeImport;
    private final Map<String, ModeLease> modeLeases = new HashMap<>();
    private final ArrayDeque<ModeSwitch> modeSwitches = new ArrayDeque<>();
    private final ArrayDeque<ModeAdmission> modeAdmissions = new ArrayDeque<>();
    private boolean unresolvedModeEffect;
    // A failed first mode write can stay visible in SharedPreferences memory; never adopt it.
    private boolean modeUnconfirmed;
    // SharedPreferences can expose failed commits in memory. Keep the whole
    // confirmed map so a sibling commit cannot persist any part of a failed write.
    private Map<String, String> confirmedAfterFailure;
    // Plan recovery switch saves, by token and owner. Each start and finish
    // advances the revision, so a reader in any engine can prove its choice.
    private final Map<String, String> recoveryPreferenceWrites = new HashMap<>();
    private long recoveryPreferenceRevision;
    // Recovery occurrences Android accepted before their history write failed.
    private final Set<String> unrecordedRecoveries = new HashSet<>();
    // Watch summaries by arrival: the newest reserved and the newest sent.
    private long watchSummaryReserved;
    private long watchSummarySent;
    private long automaticSamples;

    public ConnectionCacheEngine(Backend backend) { this(backend, System::currentTimeMillis); }
    public ConnectionCacheEngine(Backend backend, LongSupplier clock) { this(backend, new MemoryBackend(), clock, true); }
    public ConnectionCacheEngine(Backend backend, Backend modeBackend, LongSupplier clock, boolean mockAllowed) {
        this.backend = backend; this.modeBackend = modeBackend; this.clock = clock; this.mockAllowed = mockAllowed;
    }

    /** One data-mode authority shared by every engine in this process. */
    private Map<String, String> modeRecord() {
        if (confirmedModeRecord == null) {
            if (modeUnconfirmed) return null;
            Map<String, String> stored = modeBackend.read();
            try {
                UUID.fromString(stored.get("installId"));
                if (!MODES.contains(stored.get("mode")) || Long.parseLong(stored.get("generation")) < 0L) return null;
            } catch (RuntimeException invalid) { return null; }
            confirmedModeRecord = new LinkedHashMap<>(stored);
        }
        // Retire Debug Mock durably before exposing Live. Retain the confirmed
        // source record so a failed commit cannot admit its in-memory candidate.
        if (!mockAllowed && "mock".equals(confirmedModeRecord.get("mode"))
                && !commitModeChange(confirmedModeRecord, "live")) {
            throw new IllegalStateException("Data mode storage failed.");
        }
        return confirmedModeRecord;
    }
    private Long modeGeneration() {
        Map<String, String> record = modeRecord();
        return record == null ? null : Long.parseLong(record.get("generation"));
    }
    private boolean generationCurrent(Long generation) {
        return generation == null || generation.equals(modeGeneration());
    }
    public synchronized Map<String, Object> readMode() {
        Map<String, String> record = modeRecord();
        Map<String, Object> view = new LinkedHashMap<>();
        view.put("initialized", record != null);
        view.put("mockAllowed", mockAllowed);
        view.put("switching", !modeSwitches.isEmpty());
        if (record != null) {
            view.put("installId", record.get("installId"));
            view.put("mode", record.get("mode"));
            view.put("generation", Long.parseLong(record.get("generation")));
        }
        return view;
    }
    /** Writes the first record once; [legacyMock] is honored only where Mock is allowed. */
    public synchronized Map<String, Object> initializeMode(boolean legacyMock) {
        if (modeRecord() == null) {
            Map<String, String> record = new LinkedHashMap<>();
            record.put("installId", unique());
            record.put("mode", legacyMock && mockAllowed ? "mock" : "live");
            record.put("generation", "0");
            if (!commitMode(record)) throw new IllegalStateException("Data mode storage failed.");
        }
        return readMode();
    }
    /** Serializes the secure-storage read as well as the first mode write. */
    public synchronized void beginModeImport(String owner, Consumer<String> ready, Consumer<Exception> failure) {
        modeImports.addLast(new ModeImport(owner, ready, failure));
        advanceModeImport();
    }

    public synchronized void finishModeImport(String owner, String token, Boolean legacyMock) {
        if (activeModeImport == null || !activeModeImport.owner.equals(owner)
                || !activeModeImport.token.equals(token)) {
            throw new IllegalStateException("Data mode import unavailable.");
        }
        try {
            if (legacyMock != null) initializeMode(legacyMock);
        } finally {
            activeModeImport = null;
            advanceModeImport();
        }
    }

    private void advanceModeImport() {
        while (activeModeImport == null && !modeImports.isEmpty()) {
            ModeImport request = modeImports.removeFirst();
            try {
                if (modeRecord() != null) {
                    request.ready.accept(null);
                } else if (!mockAllowed) {
                    initializeMode(false);
                    request.ready.accept(null);
                } else {
                    activeModeImport = request;
                    request.ready.accept(request.token);
                }
            } catch (RuntimeException error) {
                activeModeImport = null;
                request.failure.accept(error);
            }
        }
    }
    private boolean commitMode(Map<String, String> record) {
        boolean committed;
        try { committed = modeBackend.commit(record); } catch (RuntimeException error) { committed = false; }
        if (committed) { confirmedModeRecord = new LinkedHashMap<>(record); modeUnconfirmed = false; }
        else if (confirmedModeRecord == null) modeUnconfirmed = true;
        return committed;
    }
    private boolean commitModeChange(Map<String, String> record, String mode) {
        long generation = Long.parseLong(record.get("generation"));
        if (generation == Long.MAX_VALUE) return false;
        Map<String, String> next = new LinkedHashMap<>(record);
        next.put("mode", mode);
        next.put("generation", Long.toString(generation + 1));
        return commitMode(next);
    }
    /** Captures one operation's mode; admission is closed while a switch drains. */
    public synchronized Map<String, Object> beginOperation() {
        if (modeRecord() == null || !modeSwitches.isEmpty()) throw new IllegalStateException("Data mode unavailable.");
        Map<String, Object> view = readMode();
        view.put("requestId", unique());
        return view;
    }

    public synchronized void beginAfterSwitch(String owner, Consumer<Map<String, Object>> success,
            Consumer<Exception> failure) {
        modeAdmissions.addLast(new ModeAdmission(owner, success, failure));
        admitWaitingOperations();
    }

    private void admitWaitingOperations() {
        while (modeSwitches.isEmpty() && !modeAdmissions.isEmpty()) {
            ModeAdmission request = modeAdmissions.removeFirst();
            try {
                request.success.accept(beginOperation());
            } catch (RuntimeException error) {
                request.failure.accept(error);
            }
        }
    }

    /** v9 has no ownership fields. Only its empty tap in the initial mode may refresh. */
    public synchronized Map<String, Object> captureLegacyWatchRefresh(byte[] payload) {
        if (payload == null || payload.length != 0 || !modeSwitches.isEmpty()) return null;
        Long generation = modeGeneration();
        if (generation == null || generation != 0L) return null;
        return beginOperation();
    }
    public synchronized boolean operationCurrent(long generation) {
        return modeSwitches.isEmpty() && generationCurrent(generation);
    }

    /** Orders a launcher delivery against the durable mode write; a draining switch closes it. */
    public synchronized void deliverWidgetIfModeCurrent(String installId, Long generation, Runnable deliver) {
        Map<String, String> record = modeRecord();
        if (!modeSwitches.isEmpty()) return;
        if (record == null ? installId == null && generation == null
                : record.get("installId").equals(installId) && Long.valueOf(record.get("generation")).equals(generation)) {
            deliver.run();
        }
    }
    /** Scoped provider work runs only in the current Live generation. */
    private boolean liveCurrent(Long generation) {
        return generation == null || operationCurrent(generation) && "live".equals(confirmedModeRecord.get("mode"));
    }
    /** A short effect (send initiation, OAuth settlement) that a switch waits for. */
    public synchronized String enterEffect(String owner, long generation) {
        return enterEffect(owner, generation, false);
    }
    /** A [settlement] lease covers a sent OAuth refresh until its rotation is stored. */
    public synchronized String enterEffect(String owner, long generation, boolean settlement) {
        if (!operationCurrent(generation) || modeRecord() == null) return null;
        String lease = unique();
        modeLeases.put(lease, new ModeLease(owner, generation, settlement));
        return lease;
    }
    public synchronized void exitEffect(String owner, String lease, boolean unresolved) {
        ModeLease held = modeLeases.get(lease);
        if (held == null || !held.owner.equals(owner)) return;
        modeLeases.remove(lease);
        if (unresolved) unresolvedModeEffect = true;
        advanceModeSwitch();
    }
    public synchronized void switchMode(String owner, String mode, Consumer<Map<String, Object>> success,
            Consumer<Exception> failure) {
        if (!MODES.contains(mode) || ("mock".equals(mode) && !mockAllowed))
            throw new IllegalArgumentException("Invalid data mode.");
        if (modeRecord() == null) throw new IllegalStateException("Data mode unavailable.");
        modeSwitches.add(new ModeSwitch(owner, mode, success, failure));
        advanceModeSwitch();
    }
    private void advanceModeSwitch() {
        while (!modeSwitches.isEmpty() && modeLeases.isEmpty()
                && leases.values().stream().noneMatch(lease -> lease.scoped)) {
            ModeSwitch request = modeSwitches.removeFirst();
            boolean unresolved = unresolvedModeEffect;
            unresolvedModeEffect = false;
            Map<String, String> record = modeRecord();
            if (!request.mode.equals(record.get("mode")) && !commitModeChange(record, request.mode)) {
                // The old record and generation stay authoritative, and a
                // drained storage failure stays pending for the next switch.
                unresolvedModeEffect |= unresolved;
                request.failure.accept(new ModeWriteFailure(unresolved));
                continue;
            }
            Map<String, Object> view = readMode();
            view.put("unresolved", unresolved);
            request.success.accept(view);
        }
        admitWaitingOperations();
    }

    public static final class ModeWriteFailure extends IllegalStateException {
        public final boolean unresolvedStorageFailure;

        ModeWriteFailure(boolean unresolvedStorageFailure) {
            super("Data mode storage failed.");
            this.unresolvedStorageFailure = unresolvedStorageFailure;
        }
    }

    private Map<String, String> readAll() {
        Map<String, String> all = new LinkedHashMap<>(
            confirmedAfterFailure == null ? backend.read() : confirmedAfterFailure);
        retainConfirmedCredentials(all);
        return all;
    }
    private boolean commit(Map<String, String> values) {
        Map<String, String> prior = readAll();
        boolean committed;
        try { committed = backend.commit(values); } catch (RuntimeException error) { committed = false; }
        confirmedAfterFailure = committed ? null : prior;
        return committed;
    }
    private void persistNotice(String connection, Map<String, String> state) {
        Map<String, String> all = readAll();
        for (String key : NOTICE_KEYS) {
            all.remove(connection + "." + key);
            if (state.containsKey(key)) all.put(connection + "." + key, state.get(key));
        }
        if (!commit(all)) throw new IllegalStateException("Connection notice storage failed.");
    }
    private void retainConfirmedCredentials(Map<String, String> all) {
        // Restore fenced credentials before caller mutations so sibling writes
        // cannot make an uncertain candidate durable.
        failedCommitPriorState.forEach((fencedConnection, prior) -> {
            if (!fenced.contains(fencedConnection)) return;
            String prefix = fencedConnection + ".";
            all.keySet().removeIf(key -> key.startsWith(prefix) && !NOTICE_KEYS.contains(key.substring(prefix.length())));
            prior.forEach((key, value) -> { if (!NOTICE_KEYS.contains(key)) all.put(prefix + key, value); });
        });
    }
    public synchronized Map<String, Object> readNotice(String connection) {
        requireConnection(connection);
        Map<String, String> all = readAll();
        Map<String, Object> notice = new LinkedHashMap<>();
        String event = all.get(connection + ".rejectionEvent");
        if (event != null) {
            UUID.fromString(event);
            String dismissed = all.get(connection + ".rejectionDismissed");
            if (!"true".equals(dismissed) && !"false".equals(dismissed))
                throw new IllegalStateException("Connection notice unavailable.");
            notice.put("eventId", event);
            notice.put("dismissed", "true".equals(dismissed));
        }
        return notice;
    }
    public synchronized boolean dismissNotice(String connection, String event) {
        Map<String, String> state = state(connection);
        if (!event.equals(state.get("rejectionEvent"))) return false;
        if ("true".equals(state.get("rejectionDismissed"))) return true;
        state.put("rejectionDismissed", "true"); persistNotice(connection, state); return true;
    }
    private static void reject(Map<String, String> state) {
        String identity = state.get("committedConnection");
        if (identity == null) { identity = unique(); state.put("committedConnection", identity); }
        if (!identity.equals(state.get("rejectionEvent"))) {
            state.put("rejectionEvent", identity); state.put("rejectionDismissed", "false");
        }
    }

    private static String unique() { return UUID.randomUUID().toString(); }
    private static void requireConnection(String connection) {
        if (!CONNECTIONS.contains(connection)) throw new IllegalArgumentException("Invalid connection.");
    }
    private Map<String, String> state(String connection) {
        requireConnection(connection);
        Map<String, String> all = readAll();
        Map<String, String> state = new LinkedHashMap<>();
        String prefix = connection + ".";
        all.forEach((key, value) -> { if (key.startsWith(prefix)) state.put(key.substring(prefix.length()), value); });
        if (state.isEmpty()) { state.put("mode", "legacy"); return state; }
        if (!"1".equals(state.get("lifecycleVersion")) || !state.containsKey("generation")
                || !state.containsKey("revision") || !state.containsKey("epoch")
                || !Arrays.asList("active", "pending", "migration", "deleted", "legacy").contains(state.get("mode"))) {
            throw new IllegalStateException("Credential lifecycle unavailable.");
        }
        if ("active".equals(state.get("mode")) && (!state.containsKey("slot") || !state.containsKey("identity"))) {
            throw new IllegalStateException("Credential lifecycle unavailable.");
        }
        return state;
    }
    private void persist(String connection, Map<String, String> state) {
        Map<String, String> prior = readAll();
        Map<String, String> all = new LinkedHashMap<>(prior);
        String prefix = connection + ".";
        all.keySet().removeIf(key -> key.startsWith(prefix));
        state.forEach((key, value) -> all.put(prefix + key, value));
        if (!commit(all)) {
            fenced.add(connection);
            if (!failedCommitPriorState.containsKey(connection)) {
                // Preserve emptiness; only state() supplies the legacy default.
                Map<String, String> safe = new LinkedHashMap<>();
                prior.forEach((key, value) -> { if (key.startsWith(prefix)) safe.put(key.substring(prefix.length()), value); });
                failedCommitPriorState.put(connection, safe);
            }
            throw new IllegalStateException("Credential lifecycle storage failed.");
        }
        ClockOrder order = clockOrders.get(connection);
        if (order != null && !same(state, order.version, false)) clockOrders.remove(connection);
    }
    private static String legacyKey(String connection) {
        if ("openai.plan".equals(connection)) return "wardpulse.codex.account-session";
        if ("anthropic.plan".equals(connection)) return "wardpulse.claude.account-session";
        if ("openai.platform".equals(connection)) return "wardpulse.openai.admin-api-key";
        return "wardpulse." + connection + ".secret";
    }
    private static boolean validBackup(Map<String, String> state, String connection) {
        return "active".equals(state.get("mode")) && legacyKey(connection).equals(state.get("backupKey"))
            && state.get("slot").equals(state.get("backupSlot"))
            && state.get("generation").equals(state.get("backupGeneration"))
            && state.get("revision").equals(state.get("backupRevision"));
    }
    private static void removeBackup(Map<String, String> state) {
        state.remove("backupKey"); state.remove("backupSlot"); state.remove("backupGeneration"); state.remove("backupRevision");
    }
    private static void bindBackup(Map<String, String> state) {
        if (!state.containsKey("backupKey")) return;
        state.put("backupSlot", state.get("slot")); state.put("backupGeneration", state.get("generation"));
        state.put("backupRevision", state.get("revision"));
    }
    private static void barrier(Map<String, String> state, String mode) {
        state.put("lifecycleVersion", "1");
        state.put("generation", unique());
        state.put("revision", unique());
        state.put("epoch", unique());
        state.put("mode", mode);
        state.remove("claudePlanRetired");
        SNAPSHOT_KEYS.forEach(state::remove);
    }
    private static void retire(Map<String, String> state, String slot) {
        if (slot == null || slot.isEmpty()) return;
        List<String> slots = retired(state);
        if (!slots.contains(slot)) slots.add(slot);
        state.put("retired", joinSlots(slots));
    }
    private static String joinSlots(List<String> slots) {
        StringBuilder result = new StringBuilder();
        for (String slot : slots) { if (result.length() > 0) result.append("\n"); result.append(slot); }
        return result.toString();
    }
    private static List<String> retired(Map<String, String> state) {
        String slots = state.get("retired");
        return slots == null || slots.isEmpty() ? new ArrayList<>() : new ArrayList<>(Arrays.asList(slots.split("\n")));
    }
    private static void retireLegacyKeys(String connection, Map<String, String> state) {
        retire(state, legacyKey(connection));
        if ("openai.plan".equals(connection)) retire(state, "wardpulse.codex-companion.config");
        if ("anthropic.plan".equals(connection)) retire(state, "wardpulse.anthropic.plan.secret");
    }
    private static void deleteCredential(String connection, Map<String, String> state) {
        for (String key : Arrays.asList("slot", "previousSlot", "pendingSlot", "backupKey", "previousBackupKey"))
            retire(state, state.get(key));
        retireLegacyKeys(connection, state);
        barrier(state, "deleted");
        Arrays.asList("slot", "identity", "previousSlot", "previousIdentity", "previousMode",
                "pendingSlot", "previousBackupKey").forEach(state::remove);
        removeBackup(state);
    }
    private static boolean same(Map<String, String> state, Map<String, String> expected, boolean credentialRevision) {
        return "active".equals(state.get("mode")) && expected != null
            && !expected.containsKey("absentRead") && !expected.containsKey("conflict")
            && state.get("generation").equals(expected.get("generation"))
            && state.get("identity").equals(expected.get("identity"))
            && (credentialRevision ? state.get("revision").equals(expected.get("revision"))
                : state.get("epoch").equals(expected.get("epoch")));
    }
    private static Map<String, Object> view(Map<String, String> state) { return new LinkedHashMap<>(state); }

    /** Network exclusion is separate: user credential barriers never wait for it. */
    public synchronized void acquireFetch(String owner, String connection, Consumer<Map<String, Object>> success) {
        // Unscoped requests never retire, so they never fail when granted.
        acquireFetch(owner, connection, null, success, ignored -> {});
    }
    /**
     * A non-null [generation] binds the fetch to one Live data-mode operation.
     * A queued request whose generation retires is failed instead of granted.
     */
    public synchronized void acquireFetch(String owner, String connection, Long generation,
            Consumer<Map<String, Object>> success, Consumer<Exception> failure) {
        requireConnection(connection);
        if (!liveCurrent(generation)) throw new IllegalStateException("Data mode retired.");
        FetchPending pending = new FetchPending(owner, connection, generation, success, failure);
        if (fetches.containsKey(connection)) fetchQueues.computeIfAbsent(connection, ignored -> new ArrayDeque<>()).add(pending);
        else startFetch(pending);
    }
    private void startFetch(FetchPending pending) {
        FetchLease lease = new FetchLease(pending.owner, unique(), pending.generation); fetches.put(pending.connection, lease);
        pending.success.accept(Collections.singletonMap("fetchTicket", lease.ticket));
    }
    public synchronized boolean validFetch(String owner, String connection, String ticket) {
        return validFetch(owner, connection, ticket, false);
    }
    public synchronized boolean validFetch(String owner, String connection, String ticket, boolean forAdmission) {
        if (!ownsFetch(owner, connection, ticket)) return false;
        Long generation = fetches.get(connection).generation;
        return forAdmission ? liveCurrent(generation) : generationCurrent(generation);
    }
    private boolean ownsFetch(String owner, String connection, String ticket) {
        FetchLease lease = fetches.get(connection);
        return lease != null && lease.owner.equals(owner) && lease.ticket.equals(ticket);
    }
    /** Persist automatic polling cadence independently of credential/cache transactions. */
    public synchronized Map<String, Object> claimAutomatic(String owner, String connection, String ticket,
            Map<String, String> expected, long intervalMillis) {
        return claimAutomatic(owner, connection, ticket, expected, intervalMillis, false);
    }
    /** [cacheOnly] reports cadence without admitting, so the caller never opens a transport. */
    public synchronized Map<String, Object> claimAutomatic(String owner, String connection, String ticket,
            Map<String, String> expected, long intervalMillis, boolean cacheOnly) {
        requireConnection(connection);
        Map<String, String> state = state(connection);
        if (!ownsFetch(owner, connection, ticket) || !liveCurrent(fetches.get(connection).generation) || fenced.contains(connection)
                || !same(state, expected, true) || !same(state, expected, false))
            throw new IllegalStateException("Automatic fetch superseded.");
        if (intervalMillis < 300000L || intervalMillis > 3600000L)
            throw new IllegalArgumentException("Invalid automatic interval.");
        long now = clock.getAsLong();
        Map<String, Object> result = new LinkedHashMap<>();
        // Orders competing loads' cadence observations by when this engine made them.
        result.put("sample", ++automaticSamples);
        // Both decisions report the confirmed anchor that reset wakes count from.
        boolean anchored = state.get("generation").equals(state.get("automaticGeneration"))
                && state.get("identity").equals(state.get("automaticIdentity"));
        if (cacheOnly) {
            long anchor = anchored ? Long.parseLong(state.get("automaticAt")) : now;
            result.put("admitted", false);
            result.put("nextEligible", Math.max(now, Math.addExact(Math.min(anchor, now), intervalMillis)));
            if (anchored) result.put("automaticAt", Math.min(anchor, now));
            result.put("order", cacheOrder(state, minimumEra(connection, state, confirmedEra(state))));
            return result;
        }
        if (anchored) {
            long previousAnchor = Long.parseLong(state.get("automaticAt"));
            long anchor = Math.min(previousAnchor, now);
            long due = Math.addExact(anchor, intervalMillis);
            if (now < due) {
                // Persist the first corrected sample so later calls keep the same anchor.
                if (anchor != previousAnchor) persistAutomaticAnchor(connection, state, anchor);
                result.put("admitted", false); result.put("nextEligible", due); result.put("automaticAt", anchor);
                Long confirmed = confirmedEra(state);
                result.put("order", cacheOrder(state, minimumEra(connection, state, confirmed)));
                return result;
            }
        }
        persistAutomaticAnchor(connection, state, now);
        result.put("admitted", true); result.put("automaticAt", now); return result;
    }
    /**
     * Whether cadence claimed under [expected] still belongs to the confirmed credential.
     * Like the claim's own anchor, it follows generation and identity, so a snapshot epoch
     * change keeps it. Unreadable or fenced state throws instead of proving retirement.
     */
    public synchronized boolean ownsAutomatic(String connection, Map<String, String> expected) {
        if (fenced.contains(connection)) throw new IllegalStateException("Credential lifecycle unavailable.");
        Map<String, String> state = state(connection);
        return state.get("identity") != null && state.get("generation").equals(expected.get("generation"))
            && state.get("identity").equals(expected.get("identity"));
    }
    /** Orders watch summaries by arrival across engines in this process. */
    public synchronized long reserveWatchSummary() {
        return ++watchSummaryReserved;
    }
    /** Whether [ticket] may still be sent; a later arrival that was already sent supersedes it. */
    public synchronized boolean claimWatchSummary(long ticket) {
        if (ticket <= watchSummarySent) return false;
        watchSummarySent = ticket;
        return true;
    }
    public synchronized Boolean admitWatchSummary(long ticket, Map<String, Map<String, String>> versions) {
        return admitWatchSummary(ticket, versions, Collections.emptyMap(), Collections.emptyMap(), Collections.emptyMap());
    }
    /**
     * Admits the send of [ticket] in the same step that proves its report or failure selection,
     * as {@link #validAll} would, so a credential retirement or cache write in this mode
     * generation orders before or after the send. Null [versions] carry no selection proof,
     * leaving arrival order alone; null means the proof is stale, and consumes no ticket.
     */
    public synchronized Boolean admitWatchSummary(long ticket, Map<String, Map<String, String>> versions,
            Map<String, Long> attemptClockEras, Map<String, ? extends Map<String, ?>> payloadOrders,
            Map<String, String> emptyCacheOrders) {
        if (versions != null && !validAll(versions, attemptClockEras, payloadOrders, emptyCacheOrders)) return null;
        return claimWatchSummary(ticket);
    }
    private void persistAutomaticAnchor(String connection, Map<String, String> state, long anchor) {
        Map<String, String> all = readAll();
        all.put(connection + ".automaticGeneration", state.get("generation"));
        all.put(connection + ".automaticIdentity", state.get("identity"));
        all.put(connection + ".automaticAt", Long.toString(anchor));
        // A failed metadata write denies network work but never fences credentials.
        if (!commit(all)) throw new IllegalStateException("Automatic polling storage failed.");
    }
    public synchronized void releaseFetch(String owner, String connection, String ticket) {
        releaseFetch(owner, connection, ticket, null);
    }
    /** Returns whether the reservation was still current when released. */
    public synchronized boolean releaseFetch(String owner, String connection, String ticket, Long generatedAtMillis) {
        if (!ownsFetch(owner, connection, ticket)) return false;
        FetchLease lease = fetches.remove(connection);
        try {
            boolean current = generationCurrent(lease.generation);
            // A retired operation releases its reservation without observing its report.
            if (current && generatedAtMillis != null && lease.order != null && valid(connection, lease.order.version))
                lease.order.observe(lease.era, generatedAtMillis);
            return current;
        } finally {
            grantNextFetch(connection);
        }
    }
    private void grantNextFetch(String connection) {
        ArrayDeque<FetchPending> queue = fetchQueues.get(connection);
        while (queue != null && !queue.isEmpty()) {
            FetchPending next = queue.removeFirst();
            if (liveCurrent(next.generation)) { startFetch(next); return; }
            // Requested before a mode switch: retire it so current work goes first.
            next.failure.accept(new IllegalStateException("Data mode retired."));
        }
        fetchQueues.remove(connection);
    }

    /** Capture the wall clock while this credential still owns the fetch. */
    public synchronized Map<String, Object> stampFetch(String owner, String connection, String ticket,
            Map<String, String> expected) {
        if (!validFetch(owner, connection, ticket) || !valid(connection, expected))
            throw new IllegalStateException("Account fetch superseded.");
        ClockOrder order = clockOrder(connection, state(connection));
        FetchLease lease = fetches.get(connection);
        if (lease.order == null) {
            lease.era = order.admit(clock.getAsLong());
            lease.order = order;
        } else if (lease.order != order) {
            throw new IllegalStateException("Account fetch superseded.");
        }
        Map<String, Object> stamp = new LinkedHashMap<>();
        stamp.put("era", lease.era);
        stamp.put("stamp", fetchStamp(owner, connection, ticket, order.version, lease.era, lease.generation));
        return stamp;
    }

    // A released fetch can still write. Authenticate its stamp without keeping
    // a ticket for every completed request or accepting stamps after recreation.
    private static Mac newStampMac() {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(unique().getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return mac;
        } catch (GeneralSecurityException error) {
            throw new IllegalStateException("Snapshot ordering unavailable.", error);
        }
    }
    /** A scoped stamp also carries its data-mode generation; unscoped stamps keep three fields. */
    private String fetchStamp(String owner, String connection, String ticket, Map<String, String> version, long era,
            Long generation) {
        String body = era + ":" + ticket + (generation == null ? "" : ":" + generation);
        String binding = connection + "\n" + owner + "\n" + version.get("generation")
            + "\n" + version.get("epoch") + "\n" + version.get("identity") + "\n" + body;
        ByteBuffer digest = ByteBuffer.wrap(stampMac.doFinal(binding.getBytes(StandardCharsets.UTF_8)));
        return body + ":" + new UUID(digest.getLong(), digest.getLong());
    }
    private Long stampedEra(String owner, String connection, Map<String, String> version, String stamp) {
        String[] fields = stamp.split(":", -1);
        if (fields.length != 3 && fields.length != 4) return null;
        try {
            long era = Long.parseLong(fields[0]);
            Long generation = fields.length == 4 ? Long.valueOf(fields[2]) : null;
            if (!stamp.equals(fetchStamp(owner, connection, fields[1], version, era, generation))) return null;
            // Only the current data mode's stamps publish; unscoped ones never read the mode record.
            return generation == null || generation.equals(modeGeneration()) ? era : null;
        } catch (NumberFormatException invalid) { return null; }
    }

    /** Serialize storage and rejection commits; never hold a storage lease during network work. */
    public synchronized void acquire(String owner, String connection, String action,
            Map<String, String> expected, Consumer<Map<String, Object>> success, Consumer<Exception> failure) {
        acquire(owner, connection, action, expected, null, success, failure);
    }
    public synchronized void acquire(String owner, String connection, String action,
            Map<String, String> expected, String fetchTicket, Consumer<Map<String, Object>> success, Consumer<Exception> failure) {
        acquire(owner, connection, action, expected, fetchTicket, null, null, success, failure);
    }
    public synchronized void acquire(String owner, String connection, String action,
            Map<String, String> expected, String fetchTicket, Long readGeneration, String settlementLease,
            Consumer<Map<String, Object>> success, Consumer<Exception> failure) {
        requireConnection(connection);
        if (readGeneration != null && !"read".equals(action))
            throw new IllegalArgumentException("Generation is only accepted for credential reads.");
        Pending pending = new Pending(owner, connection, action, expected, fetchTicket, readGeneration, settlementLease,
            success, failure);
        if (leases.containsKey(connection)) queues.computeIfAbsent(connection, ignored -> new ArrayDeque<>()).add(pending);
        else start(pending);
    }
    private void start(Pending pending) {
        String connection = pending.connection;
        try {
            boolean rejection = "reject".equals(pending.action) || "rejectDelete".equals(pending.action);
            if (rejection && (pending.expected == null || pending.fetchTicket == null))
                throw new IllegalArgumentException("Rejection ownership required.");
            // Cache capture can read a credential before the provider acquires a fetch ticket.
            Long generation = pending.readGeneration;
            if (pending.fetchTicket != null) {
                if (!validFetch(pending.owner, connection, pending.fetchTicket))
                    throw new IllegalStateException("Account fetch superseded.");
                Long fetchGeneration = fetches.get(connection).generation;
                if (generation != null && !generation.equals(fetchGeneration))
                    throw new IllegalStateException("Account fetch superseded.");
                generation = fetchGeneration;
            }
            if (generation != null && !liveCurrent(generation)) {
                // Only the owner of an already-sent rotation may start storage while draining.
                ModeLease settlement = modeLeases.get(pending.settlementLease);
                if (!"refresh".equals(pending.action) || settlement == null || !settlement.settlement
                        || settlement.generation != generation || !settlement.owner.equals(pending.owner))
                    throw new IllegalStateException("Account fetch superseded.");
            }
            boolean retireClaudePlan = "retireClaudePlan".equals(pending.action);
            if (retireClaudePlan && !"anthropic.plan".equals(connection))
                throw new IllegalArgumentException("Invalid retirement.");
            boolean storageFenced = fenced.contains(connection);
            if (storageFenced && !"reconnect".equals(pending.action) && !retireClaudePlan)
                throw new IllegalStateException("Credential lifecycle unavailable.");
            Map<String, String> state = state(connection);
            boolean pendingAction = "complete".equals(pending.action) || "cancel".equals(pending.action);
            boolean matches = pendingAction
                ? "pending".equals(state.get("mode")) && pending.expected != null
                    && state.get("generation").equals(pending.expected.get("generation"))
                    && state.get("revision").equals(pending.expected.get("revision"))
                : same(state, pending.expected, true);
            if (pending.expected != null && !matches) {
                pending.success.accept(Collections.singletonMap("accepted", false)); next(connection); return;
            }
            if (rejection) reject(state);
            if ("reject".equals(pending.action)) {
                persistNotice(connection, state);
                pending.success.accept(Collections.singletonMap("accepted", true)); next(connection); return;
            }
            Lease lease = new Lease(pending.owner, connection, unique(), pending.action, pending.fetchTicket,
                generation != null);
            if ("reconnect".equals(pending.action)) {
                if ("active".equals(state.get("mode"))) {
                    state.put("previousSlot", state.get("slot"));
                    state.put("previousIdentity", state.get("identity")); state.put("previousMode", "active");
                    if (validBackup(state, connection)) state.put("previousBackupKey", state.get("backupKey"));
                    else state.remove("previousBackupKey");
                } else if ("legacy".equals(state.get("mode")) || "migration".equals(state.get("mode"))) {
                    state.remove("previousSlot"); state.remove("previousIdentity"); state.put("previousMode", "legacy");
                } else if (!"pending".equals(state.get("mode"))) {
                    state.remove("previousSlot"); state.remove("previousIdentity"); state.remove("previousMode");
                }
                retire(state, state.get("slot")); retire(state, legacyKey(connection));
                barrier(state, "pending"); state.remove("slot"); state.remove("identity"); removeBackup(state);
                lease.slot = "wardpulse.connection." + connection + "." + unique();
                retire(state, lease.slot); state.put("pendingSlot", lease.slot); persist(connection, state); fenced.remove(connection); failedCommitPriorState.remove(connection);
            } else if (pendingAction) {
                if (!matches) throw new IllegalStateException("Reconnect superseded.");
                if ("cancel".equals(pending.action)) {
                    // Commit without a lease so a detached owner cannot strand the prior reference.
                    restoreCancelled(state); persist(connection, state);
                    Map<String, Object> answer = view(state); answer.put("accepted", true);
                    pending.success.accept(answer); next(connection); return;
                }
                lease.slot = state.get("pendingSlot");
            } else if (retireClaudePlan) {
                boolean alreadyRetired = "true".equals(state.get("claudePlanRetired"));
                if (!alreadyRetired) {
                    if ("deleted".equals(state.get("mode"))) {
                        // Older deletions may have left the fixed keys unqueued.
                        retireLegacyKeys(connection, state);
                    } else {
                        deleteCredential(connection, state);
                    }
                    state.put("claudePlanRetired", "true");
                }
                if (storageFenced || !alreadyRetired) {
                    // state() supplies the last confirmed data while fenced. Commit before
                    // clearing the fence or granting the secure-storage cleanup lease.
                    persist(connection, state);
                    fenced.remove(connection);
                    failedCommitPriorState.remove(connection);
                }
            } else if ("delete".equals(pending.action) || "rejectDelete".equals(pending.action)) {
                deleteCredential(connection, state);
                persist(connection, state);
            } else if ("refresh".equals(pending.action)) {
                if (!"active".equals(state.get("mode"))) throw new IllegalStateException("Credential changed.");
                lease.slot = "wardpulse.connection." + connection + "." + unique();
                retire(state, lease.slot); persist(connection, state);
            } else if (!"read".equals(pending.action)) throw new IllegalArgumentException("Invalid credential operation.");
            leases.put(connection, lease);
            Map<String, Object> answer = view(state);
            if (!validBackup(state, connection)) answer.remove("backupKey");
            answer.put("accepted", true); answer.put("lease", lease.ticket);
            List<String> cleanup = retired(state);
            cleanup.removeIf(slot -> slot.equals(state.get("slot")) || slot.equals(state.get("previousSlot"))
                || slot.equals(lease.slot) || slot.equals(state.get("previousBackupKey")) || abandonedSlots.contains(slot)
                || (slot.equals(state.get("backupKey")) && validBackup(state, connection))
                || (slot.equals(legacyKey(connection)) && ("legacy".equals(state.get("mode")) || "migration".equals(state.get("mode")) || "legacy".equals(state.get("previousMode")))));
            answer.put("cleanupSlots", cleanup);
            if (lease.slot != null) answer.put("writeSlot", lease.slot);
            pending.success.accept(answer);
        } catch (Exception error) { pending.failure.accept(error); next(connection); }
    }
    /** Restore the confirmed prior connection under the reconnect generation. */
    private static void restoreCancelled(Map<String, String> state) {
        String previous = state.remove("previousSlot"); String previousIdentity = state.remove("previousIdentity");
        String previousMode = state.remove("previousMode"); String backup = state.remove("previousBackupKey");
        if (backup != null) state.put("backupKey", backup);
        state.remove("pendingSlot"); state.put("mode", previous != null ? "active" : "legacy".equals(previousMode) ? "legacy" : "deleted");
        if (previous != null) { state.put("slot", previous); state.put("identity", previousIdentity); bindBackup(state); }
    }
    private void next(String connection) {
        ArrayDeque<Pending> queue = queues.get(connection);
        if (queue != null && !queue.isEmpty()) start(queue.removeFirst());
        else queues.remove(connection);
    }
    private Lease lease(String owner, String connection, String ticket) {
        Lease lease = leases.get(connection);
        if (lease == null || !lease.owner.equals(owner) || !lease.ticket.equals(ticket))
            throw new IllegalStateException("Credential operation superseded.");
        return lease;
    }
    public synchronized Map<String, Object> prepareMigration(String owner, String connection, String ticket) {
        Lease lease = lease(owner, connection, ticket);
        Map<String, String> state = state(connection);
        if (!"read".equals(lease.action) || (!Arrays.asList("legacy", "migration").contains(state.get("mode"))
                && !validBackup(state, connection)))
            throw new IllegalStateException("Credential changed.");
        if (!"active".equals(state.get("mode"))) barrier(state, "migration");
        lease.slot = "wardpulse.connection." + connection + "." + unique();
        retire(state, lease.slot); persist(connection, state);
        Map<String, Object> result = view(state); result.put("writeSlot", lease.slot); return result;
    }
    public synchronized Map<String, Object> finish(String owner, String connection, String ticket, String operation, String identity) {
        Lease lease = lease(owner, connection, ticket);
        try {
            if (lease.fetchTicket != null && !validFetch(owner, connection, lease.fetchTicket))
                throw new IllegalStateException("Account fetch superseded.");
            Map<String, String> state = state(connection);
            if ("activate".equals(operation)) {
                if (lease.slot == null || identity == null || identity.length() != 64)
                    throw new IllegalArgumentException("Invalid credential identity.");
                if (("refresh".equals(lease.action) || "active".equals(state.get("mode"))) && !identity.equals(state.get("identity"))) {
                    barrier(state, "deleted"); retire(state, state.get("slot"));
                    state.remove("slot"); state.remove("identity"); removeBackup(state); persist(connection, state);
                    throw new IllegalStateException("Credential identity changed.");
                }
                if ("migration".equals(state.get("mode"))) state.put("backupKey", legacyKey(connection));
                if ("complete".equals(lease.action) || "refresh".equals(lease.action)) {
                    retire(state, state.get("backupKey")); removeBackup(state);
                }
                retire(state, state.get("slot"));
                state.put("slot", lease.slot); state.put("identity", identity);
                state.put("revision", unique()); state.put("mode", "active"); bindBackup(state);
                if ("complete".equals(lease.action) || !state.containsKey("committedConnection"))
                    state.put("committedConnection", unique());
                state.remove("previousSlot"); state.remove("previousIdentity"); state.remove("previousMode"); state.remove("pendingSlot"); state.remove("previousBackupKey"); persist(connection, state);
            } else if ("missing".equals(operation) || ("confirm".equals(operation) && !identity.equals(state.get("identity")))) {
                retire(state, state.get("slot")); barrier(state, "deleted");
                state.remove("slot"); state.remove("identity"); removeBackup(state); persist(connection, state);
            } else if ("confirm".equals(operation) && !state.containsKey("committedConnection")) {
                state.put("committedConnection", unique()); persistNotice(connection, state);
            } else if (!"release".equals(operation) && !"confirm".equals(operation)) {
                throw new IllegalArgumentException("Invalid credential completion.");
            }
            return view(state);
        } finally { releaseCredentialLease(lease); }
    }
    private void releaseCredentialLease(Lease lease) {
        leases.remove(lease.connection);
        // A waiting switch takes precedence over the next scoped transaction.
        if (lease.scoped) advanceModeSwitch();
        next(lease.connection);
    }
    public synchronized void queueLegacyCleanup(String owner, String connection, String ticket) {
        lease(owner, connection, ticket);
        if (!"anthropic.plan".equals(connection) && !"openai.plan".equals(connection))
            throw new IllegalArgumentException("Invalid legacy cleanup.");
        Map<String, String> state = state(connection);
        if (!state.containsKey("generation")) barrier(state, "legacy");
        retire(state, "wardpulse." + connection + ".secret");
        Map<String, String> all = new LinkedHashMap<>(readAll()); String prefix = connection + ".";
        state.forEach((key, value) -> all.put(prefix + key, value));
        if (!commit(all)) throw new IllegalStateException("Cleanup storage failed.");
    }
    public synchronized boolean acknowledgeCleanup(String owner, String connection, String ticket, List<String> cleaned) {
        Lease lease = lease(owner, connection, ticket);
        Map<String, String> state = state(connection);
        List<String> slots = retired(state);
        slots.removeIf(slot -> cleaned.contains(slot) && !slot.equals(state.get("slot"))
            && !slot.equals(state.get("previousSlot")) && !slot.equals(lease.slot) && !slot.equals(state.get("previousBackupKey")) && !abandonedSlots.contains(slot)
            && !(slot.equals(state.get("backupKey")) && validBackup(state, connection))
            && !(slot.equals(legacyKey(connection)) && ("legacy".equals(state.get("mode")) || "migration".equals(state.get("mode")) || "legacy".equals(state.get("previousMode")))));
        state.put("retired", joinSlots(slots));
        Map<String, String> all = new LinkedHashMap<>(readAll());
        all.put(connection + ".retired", state.get("retired"));
        return commit(all);
    }
    public synchronized String beginRecoveryPreferenceWrite(String owner) {
        String token = UUID.randomUUID().toString();
        recoveryPreferenceWrites.put(token, owner);
        recoveryPreferenceRevision++;
        return token;
    }
    public synchronized void finishRecoveryPreferenceWrite(String owner, String token) {
        if (!owner.equals(recoveryPreferenceWrites.get(token))) return;
        recoveryPreferenceWrites.remove(token);
        recoveryPreferenceRevision++;
    }
    /** Null while a save is in flight: its outcome is not yet readable. */
    public synchronized Long readRecoveryPreferenceRevision() {
        return recoveryPreferenceWrites.isEmpty() ? recoveryPreferenceRevision : null;
    }
    public synchronized boolean recoveryDeliveryCurrent(long revision, Long generation) {
        return recoveryPreferenceWrites.isEmpty() && recoveryPreferenceRevision == revision && liveCurrent(generation);
    }
    public synchronized List<String> readUnrecordedRecoveries() { return new ArrayList<>(unrecordedRecoveries); }
    public synchronized void recordUnrecordedRecoveries(List<String> occurrences) { unrecordedRecoveries.addAll(occurrences); }
    public synchronized void forgetUnrecordedRecoveries(List<String> occurrences) { unrecordedRecoveries.removeAll(occurrences); }
    public synchronized void detach(String owner) {
        // A detached engine's save can no longer finish; its outcome is unknown.
        if (recoveryPreferenceWrites.values().removeIf(owner::equals)) recoveryPreferenceRevision++;
        modeAdmissions.removeIf(request -> request.owner.equals(owner));
        modeImports.removeIf(request -> request.owner.equals(owner));
        if (activeModeImport != null && activeModeImport.owner.equals(owner)) {
            activeModeImport = null;
            advanceModeImport();
        }
        modeSwitches.removeIf(request -> request.owner.equals(owner));
        // A detached engine's sent OAuth refresh can no longer store its rotation.
        modeLeases.values().removeIf(lease -> {
            if (!lease.owner.equals(owner)) return false;
            if (lease.settlement) unresolvedModeEffect = true;
            return true;
        });
        advanceModeSwitch();
        for (ArrayDeque<FetchPending> queue : fetchQueues.values()) queue.removeIf(pending -> pending.owner.equals(owner));
        for (String connection : new ArrayList<>(fetches.keySet())) {
            FetchLease lease = fetches.get(connection);
            if (lease.owner.equals(owner)) releaseFetch(owner, connection, lease.ticket);
        }
        for (ArrayDeque<Pending> queue : queues.values()) queue.removeIf(pending -> pending.owner.equals(owner));
        for (String connection : new ArrayList<>(leases.keySet())) {
            Lease lease = leases.get(connection);
            if (!lease.owner.equals(owner)) continue;
            if (lease.slot != null) abandonedSlots.add(lease.slot);
            // Deletion is already durable when the lease is granted.
            if (!Arrays.asList("read", "delete", "rejectDelete", "retireClaudePlan").contains(lease.action)) {
                try {
                    Map<String, String> state = state(connection);
                    retire(state, state.get("slot")); barrier(state, "pending");
                    state.remove("slot"); state.remove("identity");
                    state.remove("previousSlot"); state.remove("previousIdentity"); state.remove("previousMode"); state.remove("pendingSlot"); persist(connection, state);
                } catch (Exception ignored) { fenced.add(connection); }
            }
            releaseCredentialLease(lease);
        }
    }
    public synchronized boolean valid(String connection, Map<String, String> expected) {
        return !fenced.contains(connection) && same(state(connection), expected, false);
    }
    public synchronized boolean validAll(Map<String, Map<String, String>> versions) {
        return validAll(versions, Collections.emptyMap(), Collections.emptyMap(), Collections.emptyMap());
    }
    /**
     * Also admits a recovery post, when {@code recoveryPreferenceRevision} is given: the saved
     * choice must be settled at that revision and {@code recoveryModeGeneration}, if given, the
     * Live generation with admission open.
     */
    public synchronized boolean validAll(Map<String, Map<String, String>> versions,
            Map<String, Long> attemptClockEras, Map<String, ? extends Map<String, ?>> payloadOrders,
            Map<String, String> emptyCacheOrders, Long recoveryPreferenceRevision, Long recoveryModeGeneration) {
        if (recoveryPreferenceRevision != null
                && !recoveryDeliveryCurrent(recoveryPreferenceRevision, recoveryModeGeneration)) return false;
        return validAll(versions, attemptClockEras, payloadOrders, emptyCacheOrders);
    }
    public synchronized boolean validAll(Map<String, Map<String, String>> versions,
            Map<String, Long> attemptClockEras, Map<String, ? extends Map<String, ?>> payloadOrders,
            Map<String, String> emptyCacheOrders) {
        if (!versions.keySet().containsAll(attemptClockEras.keySet())
                || !versions.keySet().containsAll(payloadOrders.keySet())
                || !versions.keySet().containsAll(emptyCacheOrders.keySet())) return false;
        for (Map.Entry<String, Map<String, String>> entry : versions.entrySet()) {
            String connection = entry.getKey();
            Map<String, String> expected = entry.getValue();
            if (expected == null || expected.containsKey("conflict") || fenced.contains(connection)) return false;
            try {
                Map<String, String> state = state(connection);
                Long attemptEra = attemptClockEras.get(connection);
                Map<String, ?> payload = payloadOrders.get(connection);
                String emptyOrder = emptyCacheOrders.get(connection);
                if (!expected.containsKey("absentRead")) {
                    if (!same(state, expected, false)) return false;
                    if (attemptEra != null || payload != null || emptyOrder != null) {
                        Long confirmed = confirmedEra(state);
                        Long floor = minimumEra(connection, state, confirmed);
                        if (attemptEra != null && floor != null && attemptEra < floor) return false;
                        if (payload != null) {
                            Object eraValue = payload.get("era"), timeValue = payload.get("generatedAt");
                            if (!(eraValue instanceof Number) || !(timeValue instanceof Number)) return false;
                            Number era = (Number) eraValue, generatedAt = (Number) timeValue;
                            long payloadEra = era.longValue();
                            if (floor != null && payloadEra < floor) return false;
                            if (payload.containsKey("rowId") && (!hasSnapshot(state)
                                    || !snapshotRowId(state).equals(payload.get("rowId")))) return false;
                            // Legacy rows compare by timestamp with unstamped live data.
                            long confirmedOrder = confirmed == null ? 0L : confirmed;
                            boolean comparable = confirmedOrder == payloadEra || (confirmed == null && payloadEra == -1L);
                            if (hasSnapshot(state) && comparable
                                    && snapshotMicros(state) > generatedAt.longValue()) return false;
                        }
                        if (emptyOrder != null && !emptyOrder.equals(cacheOrder(state, floor))) return false;
                    }
                    continue;
                }
                if (attemptEra != null || payload != null || emptyOrder != null || !"true".equals(expected.get("absentRead"))
                        || expected.size() != 4) return false;
                if (!"deleted".equals(state.get("mode")) || state.containsKey("slot")
                        || state.containsKey("identity")) return false;
                for (String key : Arrays.asList("generation", "revision", "epoch")) {
                    String value = expected.get(key);
                    if (value == null || value.trim().isEmpty() || !value.equals(state.get(key))) return false;
                }
            } catch (IllegalArgumentException | IllegalStateException unavailable) { return false; }
        }
        return true;
    }
    public synchronized String readSnapshot(String connection, Map<String, String> expected) {
        return (String) readSnapshotPair(connection, expected).get("snapshot");
    }
    public synchronized Map<String, Object> readSnapshotPair(String connection, Map<String, String> expected) {
        return readSnapshotPair(connection, expected, false);
    }
    public synchronized Map<String, Object> readSnapshotPair(String connection, Map<String, String> expected,
            boolean forSelection) {
        return readSnapshotPair(connection, expected, forSelection, null);
    }
    public synchronized Map<String, Object> readSnapshotPair(String connection, Map<String, String> expected,
            boolean forSelection, Long generation) {
        // A regular read can also purge an unsupported payload and advance its epoch.
        if (!liveCurrent(generation) || !valid(connection, expected)) return Collections.singletonMap("valid", false);
        Map<String, String> state = state(connection);
        // Selection must see the floor without attempting another storage write.
        if (!forSelection && state.containsKey("snapshot") && !"1".equals(state.get("snapshotVersion"))) {
            clearSnapshot(connection, expected);
            return Collections.singletonMap("valid", false);
        }
        Long confirmedEra = confirmedEra(state);
        Long floor = minimumEra(connection, state, confirmedEra);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("valid", true);
        result.put("minimumEra", floor);
        result.put("order", cacheOrder(state, floor));
        if (hasSnapshot(state)) {
            result.put("snapshot", state.get("snapshot"));
            result.put("rowId", snapshotRowId(state));
            if (confirmedEra != null) result.put("era", confirmedEra);
            result.put("legacyTimestamp", !"microseconds".equals(state.get("snapshotTimeUnit")));
        }
        return result;
    }
    private static boolean hasSnapshot(Map<String, String> state) {
        return "1".equals(state.get("snapshotVersion")) && state.containsKey("snapshot");
    }
    private static String cacheOrder(Map<String, String> state, Long floor) {
        // A write replaces the payload identity even at an equal timestamp.
        // Upgrading timestamp precision leaves the confirmed payload in place.
        return floor + ":" + (hasSnapshot(state) ? snapshotRowId(state) : "none");
    }
    private static String snapshotRowId(Map<String, String> state) {
        return state.getOrDefault("snapshotWriteId", "legacy");
    }
    public synchronized boolean writeSnapshot(String connection, Map<String, String> expected, String snapshot, long generatedAt) {
        return "stored".equals(writeSnapshotOrdered(null, connection, expected, snapshot, generatedAt, null).get("status"));
    }
    public synchronized Map<String, Object> writeSnapshotOrdered(String owner, String connection, Map<String, String> expected,
            String snapshot, long generatedAt, String stamp) {
        return writeSnapshotOrdered(owner, connection, expected, snapshot, generatedAt, stamp, null);
    }
    public synchronized Map<String, Object> writeSnapshotOrdered(String owner, String connection, Map<String, String> expected,
            String snapshot, long generatedAt, String stamp, Long generation) {
        if (!liveCurrent(generation) || !valid(connection, expected)) return writeResult("superseded", null);
        Map<String, String> state = state(connection);
        Long confirmedEra = confirmedEra(state);
        Long minimumEra = minimumEra(connection, state, confirmedEra);
        if (snapshot == null) return writeResult("superseded", minimumEra);
        Long era = null;
        ClockOrder order = null;
        if (stamp != null) {
            era = stampedEra(owner, connection, state, stamp);
            if (era == null || (minimumEra != null && era < minimumEra))
                return writeResult("superseded", minimumEra);
            order = clockOrder(connection, state);
            if (!order.references.containsKey(era)) return writeResult("superseded", minimumEra);
            // Advance before attempting storage. A failed commit cannot let
            // an earlier era publish a successful result later.
            order.fence(era);
            minimumEra = era;
            order.observe(era, generatedAt / 1000L);
        } else if (minimumEra != null) {
            return writeResult("superseded", minimumEra);
        }
        long oldEra = confirmedEra == null ? 0L : confirmedEra;
        if ((era == null ? 0L : era) == oldEra && generatedAt < snapshotMicros(state))
            return writeResult("older", minimumEra);
        state.put("snapshot", snapshot);
        state.put("snapshotWriteId", unique());
        state.put("snapshotAt", Long.toString(generatedAt));
        state.put("snapshotVersion", "1");
        state.put("snapshotTimeUnit", "microseconds");
        if (order != null) {
            state.put("snapshotEra", Long.toString(era));
            state.put("snapshotClockAt", Long.toString(order.references.get(era)));
        }
        // Payload persistence is best effort and must not fence valid credentials.
        if (!commitSnapshot(connection, state, era != null)) return writeResult("storageFailure", minimumEra);
        if (era == null) observeLegacyTimestamp(connection, state, generatedAt);
        return writeResult("stored", minimumEra);
    }
    private static Map<String, Object> writeResult(String status, Long minimumEra) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("status", status);
        result.put("minimumEra", minimumEra);
        return result;
    }
    private static Long confirmedEra(Map<String, String> state) {
        Long era = snapshotNumber(state.get("snapshotEra"));
        return era != null && era >= 0 ? era : null;
    }
    private static Long snapshotNumber(String value) {
        if (value == null) return null;
        try { return Long.valueOf(value); }
        catch (NumberFormatException invalid) { return null; }
    }
    private Long minimumEra(String connection, Map<String, String> state, Long confirmedEra) {
        ClockOrder order = clockOrders.get(connection);
        return order != null && same(state, order.version, false) ? order.minimumEra : confirmedEra;
    }
    private ClockOrder clockOrder(String connection, Map<String, String> state) {
        ClockOrder order = clockOrders.get(connection);
        if (order == null || !same(state, order.version, false)) {
            order = new ClockOrder(state);
            clockOrders.put(connection, order);
        }
        return order;
    }
    private static long snapshotMicros(Map<String, String> state) {
        try {
            String timestamp = state.get("snapshotAt");
            if (timestamp == null) return Long.MIN_VALUE;
            long value = Long.parseLong(timestamp);
            return "microseconds".equals(state.get("snapshotTimeUnit")) ? value : Math.multiplyExact(value, 1000L);
        } catch (NumberFormatException | ArithmeticException invalid) { return Long.MIN_VALUE; }
    }
    private void observeLegacyTimestamp(String connection, Map<String, String> state, long generatedAt) {
        ClockOrder order = clockOrders.get(connection);
        if (order != null && same(state, order.version, false)) order.observe(0L, generatedAt / 1000L);
    }
    private boolean commitSnapshot(String connection, Map<String, String> state, boolean verifiedLiveReport) {
        Map<String, String> all = readAll();
        String prefix = connection + ".";
        for (String key : SNAPSHOT_KEYS) {
            if (state.containsKey(key)) all.put(prefix + key, state.get(key));
            else all.remove(prefix + key);
        }
        all.put(prefix + "epoch", state.get("epoch"));
        String committed = state.get("committedConnection");
        String event = state.get("rejectionEvent");
        if (verifiedLiveReport && committed != null && event != null && !committed.equals(event)
                && "false".equals(state.get("rejectionDismissed"))) {
            all.put(prefix + "rejectionDismissed", "true");
        }
        return commit(all);
    }
    /** Upgrade legacy millisecond ordering without rewriting or racing a newer payload. */
    public synchronized boolean upgradeSnapshotTimestamp(String connection, Map<String, String> expected, String snapshot, long generatedAt) {
        return upgradeSnapshotTimestamp(connection, expected, snapshot, generatedAt, null);
    }
    public synchronized boolean upgradeSnapshotTimestamp(String connection, Map<String, String> expected, String snapshot,
            long generatedAt, Long generation) {
        if (!liveCurrent(generation) || !valid(connection, expected)) return false;
        Map<String, String> state = state(connection);
        if (!snapshot.equals(state.get("snapshot"))) return false;
        if ("microseconds".equals(state.get("snapshotTimeUnit"))) return true;
        state.put("snapshotAt", Long.toString(generatedAt)); state.put("snapshotTimeUnit", "microseconds");
        if (!commitSnapshot(connection, state, false)) return false;
        if (confirmedEra(state) == null) observeLegacyTimestamp(connection, state, generatedAt);
        return true;
    }
    public synchronized void clearSnapshot(String connection, Map<String, String> expected) {
        clearSnapshot(connection, expected, null);
    }
    public synchronized void clearSnapshot(String connection, Map<String, String> expected, Long generation) {
        if (!liveCurrent(generation)) return;
        Map<String, String> state = state(connection);
        if (expected != null && !same(state, expected, false)) return;
        if ("legacy".equals(state.get("mode"))) return;
        state.put("epoch", unique());
        SNAPSHOT_KEYS.forEach(state::remove);
        if (!commitSnapshot(connection, state, false)) throw new IllegalStateException("Snapshot storage failed.");
        Map<String, String> prior = failedCommitPriorState.get(connection);
        if (prior != null) {
            // Keep a successful cache clear when the credential remains fenced.
            prior.put("epoch", state.get("epoch"));
            SNAPSHOT_KEYS.forEach(prior::remove);
        }
        clockOrders.remove(connection);
    }
    private static final class ClockOrder {
        final Map<String, String> version = new HashMap<>();
        // A released fetch can still finish in an earlier era until a newer
        // candidate advances the write floor.
        final Map<Long, Long> references = new HashMap<>();
        long era;
        Long minimumEra;
        ClockOrder(Map<String, String> state) {
            for (String key : Arrays.asList("generation", "identity", "epoch")) version.put(key, state.get(key));
            minimumEra = confirmedEra(state);
            era = minimumEra == null ? 0L : minimumEra;
            long micros = snapshotMicros(state);
            long millis = micros == Long.MIN_VALUE ? Long.MIN_VALUE : micros / 1000L;
            Long reference = minimumEra == null ? null : snapshotNumber(state.get("snapshotClockAt"));
            references.put(era, reference == null ? millis : Math.max(reference, millis));
        }
        long admit(long now) {
            if (now < references.get(era)) era = Math.incrementExact(era);
            references.put(era, now);
            return era;
        }
        void observe(long observedEra, long sample) {
            references.computeIfPresent(observedEra, (ignored, previous) -> Math.max(previous, sample));
        }
        void fence(long candidateEra) {
            minimumEra = candidateEra;
            references.keySet().removeIf(prior -> prior < candidateEra);
        }
    }
    private static final class FetchLease {
        final String owner, ticket; final Long generation;
        ClockOrder order;
        long era;
        FetchLease(String owner, String ticket, Long generation) {
            this.owner = owner; this.ticket = ticket; this.generation = generation;
        }
    }
    private static final class FetchPending {
        final String owner, connection; final Long generation; final Consumer<Map<String, Object>> success;
        final Consumer<Exception> failure;
        FetchPending(String owner, String connection, Long generation, Consumer<Map<String, Object>> success,
                Consumer<Exception> failure) {
            this.owner = owner; this.connection = connection; this.generation = generation; this.success = success;
            this.failure = failure;
        }
    }
    private static final class ModeImport {
        final String owner;
        final String token = unique();
        final Consumer<String> ready;
        final Consumer<Exception> failure;
        ModeImport(String owner, Consumer<String> ready, Consumer<Exception> failure) {
            this.owner = owner; this.ready = ready; this.failure = failure;
        }
    }

    private static final class ModeLease {
        final String owner;
        final long generation;
        final boolean settlement;
        ModeLease(String owner, long generation, boolean settlement) {
            this.owner = owner; this.generation = generation; this.settlement = settlement;
        }
    }
    private static final class ModeAdmission {
        final String owner;
        final Consumer<Map<String, Object>> success;
        final Consumer<Exception> failure;
        ModeAdmission(String owner, Consumer<Map<String, Object>> success, Consumer<Exception> failure) {
            this.owner = owner; this.success = success; this.failure = failure;
        }
    }

    private static final class ModeSwitch {
        final String owner, mode; final Consumer<Map<String, Object>> success; final Consumer<Exception> failure;
        ModeSwitch(String owner, String mode, Consumer<Map<String, Object>> success, Consumer<Exception> failure) {
            this.owner = owner; this.mode = mode; this.success = success; this.failure = failure;
        }
    }
    /** Process-local mode storage for hosts without a durable mode backend. */
    private static final class MemoryBackend implements Backend {
        private Map<String, String> values = Collections.emptyMap();
        @Override public Map<String, String> read() { return values; }
        @Override public boolean commit(Map<String, String> next) { values = new LinkedHashMap<>(next); return true; }
    }
    private static final class Lease {
        final String owner, connection, ticket, action, fetchTicket;
        final boolean scoped;
        String slot;
        Lease(String owner, String connection, String ticket, String action, String fetchTicket, boolean scoped) {
            this.owner = owner; this.connection = connection; this.ticket = ticket; this.action = action; this.fetchTicket = fetchTicket;
            this.scoped = scoped;
        }
    }
    private static final class Pending {
        final String owner, connection, action, fetchTicket, settlementLease; final Map<String, String> expected;
        final Long readGeneration;
        final Consumer<Map<String, Object>> success; final Consumer<Exception> failure;
        Pending(String owner, String connection, String action, Map<String, String> expected, String fetchTicket,
                Long readGeneration, String settlementLease, Consumer<Map<String, Object>> success, Consumer<Exception> failure) {
            this.owner = owner; this.connection = connection; this.action = action; this.expected = expected; this.fetchTicket = fetchTicket;
            this.readGeneration = readGeneration; this.settlementLease = settlementLease;
            this.success = success; this.failure = failure;
        }
    }
}
