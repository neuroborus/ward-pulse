package app.wardpulse.watchsync;

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

/** Process-wide credential leases and durable snapshot CAS; no credential values enter Java. */
public final class ConnectionCacheEngine {
    public interface Backend {
        Map<String, String> read();
        boolean commit(Map<String, String> values);
    }
    private static final Set<String> CONNECTIONS = new HashSet<>(Arrays.asList(
        "openai.plan", "openai.platform", "anthropic.plan", "anthropic.platform", "cursor.plan", "cursor.platform"));
    private final Backend backend;
    private final Map<String, Lease> leases = new HashMap<>();
    private final Map<String, ArrayDeque<Pending>> queues = new HashMap<>();
    private final Set<String> fenced = new HashSet<>();
    private final Map<String, Map<String, String>> failedCommitPriorState = new HashMap<>();
    private final Set<String> abandonedSlots = new HashSet<>();
    private final Map<String, FetchLease> fetches = new HashMap<>();
    private final Map<String, ArrayDeque<FetchPending>> fetchQueues = new HashMap<>();

    public ConnectionCacheEngine(Backend backend) { this.backend = backend; }
    private static String unique() { return UUID.randomUUID().toString(); }
    private static void requireConnection(String connection) {
        if (!CONNECTIONS.contains(connection)) throw new IllegalArgumentException("Invalid connection.");
    }
    private Map<String, String> state(String connection) {
        requireConnection(connection);
        Map<String, String> all = backend.read();
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
        Map<String, String> prior = backend.read();
        Map<String, String> all = new LinkedHashMap<>(prior);
        String prefix = connection + ".";
        all.keySet().removeIf(key -> key.startsWith(prefix));
        state.forEach((key, value) -> all.put(prefix + key, value));
        if (!backend.commit(all)) {
            fenced.add(connection);
            if (!failedCommitPriorState.containsKey(connection)) {
                Map<String, String> safe = new LinkedHashMap<>();
                prior.forEach((key, value) -> { if (key.startsWith(prefix)) safe.put(key.substring(prefix.length()), value); });
                if (safe.isEmpty()) safe.put("mode", "legacy");
                failedCommitPriorState.put(connection, safe);
            }
            throw new IllegalStateException("Credential lifecycle storage failed.");
        }
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
        state.remove("snapshot"); state.remove("snapshotAt"); state.remove("snapshotVersion"); state.remove("snapshotTimeUnit");
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
    private static boolean same(Map<String, String> state, Map<String, String> expected, boolean credentialRevision) {
        return "active".equals(state.get("mode")) && expected != null
            && state.get("generation").equals(expected.get("generation"))
            && state.get("identity").equals(expected.get("identity"))
            && (credentialRevision ? state.get("revision").equals(expected.get("revision"))
                : state.get("epoch").equals(expected.get("epoch")));
    }
    private static Map<String, Object> view(Map<String, String> state) { return new LinkedHashMap<>(state); }

    /** Network exclusion is separate: user credential barriers never wait for it. */
    public synchronized void acquireFetch(String owner, String connection, Consumer<Map<String, Object>> success) {
        requireConnection(connection);
        FetchPending pending = new FetchPending(owner, connection, success);
        if (fetches.containsKey(connection)) fetchQueues.computeIfAbsent(connection, ignored -> new ArrayDeque<>()).add(pending);
        else startFetch(pending);
    }
    private void startFetch(FetchPending pending) {
        FetchLease lease = new FetchLease(pending.owner, unique()); fetches.put(pending.connection, lease);
        pending.success.accept(Collections.singletonMap("fetchTicket", lease.ticket));
    }
    public synchronized boolean validFetch(String owner, String connection, String ticket) {
        FetchLease lease = fetches.get(connection);
        return lease != null && lease.owner.equals(owner) && lease.ticket.equals(ticket);
    }
    public synchronized void releaseFetch(String owner, String connection, String ticket) {
        if (!validFetch(owner, connection, ticket)) return;
        fetches.remove(connection);
        ArrayDeque<FetchPending> queue = fetchQueues.get(connection);
        if (queue != null && !queue.isEmpty()) startFetch(queue.removeFirst()); else fetchQueues.remove(connection);
    }

    /** Queue only secure-storage operations; the caller releases before network work. */
    public synchronized void acquire(String owner, String connection, String action,
            Map<String, String> expected, Consumer<Map<String, Object>> success, Consumer<Exception> failure) {
        acquire(owner, connection, action, expected, null, success, failure);
    }
    public synchronized void acquire(String owner, String connection, String action,
            Map<String, String> expected, String fetchTicket, Consumer<Map<String, Object>> success, Consumer<Exception> failure) {
        requireConnection(connection);
        Pending pending = new Pending(owner, connection, action, expected, fetchTicket, success, failure);
        if (leases.containsKey(connection)) queues.computeIfAbsent(connection, ignored -> new ArrayDeque<>()).add(pending);
        else start(pending);
    }
    private void start(Pending pending) {
        String connection = pending.connection;
        try {
            if (pending.fetchTicket != null && !validFetch(pending.owner, connection, pending.fetchTicket))
                throw new IllegalStateException("Account fetch superseded.");
            if (fenced.contains(connection) && !"reconnect".equals(pending.action))
                throw new IllegalStateException("Credential lifecycle unavailable.");
            Map<String, String> state = fenced.contains(connection) && failedCommitPriorState.containsKey(connection)
                ? new LinkedHashMap<>(failedCommitPriorState.get(connection)) : state(connection);
            boolean pendingAction = "complete".equals(pending.action) || "cancel".equals(pending.action);
            boolean matches = pendingAction
                ? "pending".equals(state.get("mode")) && pending.expected != null
                    && state.get("generation").equals(pending.expected.get("generation"))
                    && state.get("revision").equals(pending.expected.get("revision"))
                : same(state, pending.expected, true);
            if (pending.expected != null && !matches) {
                pending.success.accept(Collections.singletonMap("accepted", false)); next(connection); return;
            }
            Lease lease = new Lease(pending.owner, connection, unique(), pending.action, pending.fetchTicket);
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
                lease.slot = state.get("pendingSlot");
            } else if ("delete".equals(pending.action)) {
                retire(state, state.get("slot")); retire(state, legacyKey(connection));
                if ("openai.plan".equals(connection)) retire(state, "wardpulse.codex-companion.config");
                if ("anthropic.plan".equals(connection)) retire(state, "wardpulse.anthropic.plan.secret");
                barrier(state, "deleted"); state.remove("slot"); state.remove("identity");
                state.remove("previousSlot"); state.remove("previousIdentity"); state.remove("previousMode"); state.remove("pendingSlot"); state.remove("previousBackupKey"); removeBackup(state); persist(connection, state);
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
                state.remove("previousSlot"); state.remove("previousIdentity"); state.remove("previousMode"); state.remove("pendingSlot"); state.remove("previousBackupKey"); persist(connection, state);
            } else if ("cancel".equals(operation)) {
                if (!"cancel".equals(lease.action)) throw new IllegalStateException("Invalid cancellation.");
                String previous = state.remove("previousSlot"); String previousIdentity = state.remove("previousIdentity");
                String previousMode = state.remove("previousMode"); String backup = state.remove("previousBackupKey");
                if (backup != null) state.put("backupKey", backup);
                state.remove("pendingSlot"); state.put("mode", previous != null ? "active" : "legacy".equals(previousMode) ? "legacy" : "deleted");
                if (previous != null) { state.put("slot", previous); state.put("identity", previousIdentity); bindBackup(state); }
                persist(connection, state);
            } else if ("missing".equals(operation) || ("confirm".equals(operation) && !identity.equals(state.get("identity")))) {
                retire(state, state.get("slot")); barrier(state, "deleted");
                state.remove("slot"); state.remove("identity"); removeBackup(state); persist(connection, state);
            } else if (!"release".equals(operation) && !"confirm".equals(operation)) {
                throw new IllegalArgumentException("Invalid credential completion.");
            }
            return view(state);
        } finally { leases.remove(connection); next(connection); }
    }
    public synchronized void queueLegacyCleanup(String owner, String connection, String ticket) {
        lease(owner, connection, ticket);
        if (!"anthropic.plan".equals(connection) && !"openai.plan".equals(connection))
            throw new IllegalArgumentException("Invalid legacy cleanup.");
        Map<String, String> state = state(connection);
        if (!state.containsKey("generation")) barrier(state, "legacy");
        retire(state, "wardpulse." + connection + ".secret");
        Map<String, String> all = new LinkedHashMap<>(backend.read()); String prefix = connection + ".";
        state.forEach((key, value) -> all.put(prefix + key, value));
        if (!backend.commit(all)) throw new IllegalStateException("Cleanup storage failed.");
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
        Map<String, String> all = new LinkedHashMap<>(backend.read());
        all.put(connection + ".retired", state.get("retired"));
        return backend.commit(all);
    }
    public synchronized void detach(String owner) {
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
            if (!"read".equals(lease.action)) {
                try {
                    Map<String, String> state = state(connection);
                    retire(state, state.get("slot")); barrier(state, "pending");
                    state.remove("slot"); state.remove("identity");
                    state.remove("previousSlot"); state.remove("previousIdentity"); state.remove("previousMode"); state.remove("pendingSlot"); persist(connection, state);
                } catch (Exception ignored) { fenced.add(connection); }
            }
            leases.remove(connection); next(connection);
        }
    }
    public synchronized boolean valid(String connection, Map<String, String> expected) {
        return !fenced.contains(connection) && same(state(connection), expected, false);
    }
    public synchronized boolean validAll(Map<String, Map<String, String>> versions) {
        for (Map.Entry<String, Map<String, String>> entry : versions.entrySet()) {
            if (!valid(entry.getKey(), entry.getValue())) return false;
        }
        return true;
    }
    public synchronized String readSnapshot(String connection, Map<String, String> expected) {
        if (!valid(connection, expected)) return null;
        Map<String, String> state = state(connection);
        if (state.containsKey("snapshot") && !"1".equals(state.get("snapshotVersion"))) {
            clearSnapshot(connection, expected); return null;
        }
        if (!"1".equals(state.get("snapshotVersion"))) return null;
        return state.get("snapshot");
    }
    public synchronized boolean writeSnapshot(String connection, Map<String, String> expected, String snapshot, long generatedAt) {
        if (!valid(connection, expected)) return false;
        Map<String, String> state = state(connection);
        long oldAt = Long.MIN_VALUE;
        try {
            if (state.containsKey("snapshotAt")) {
                oldAt = Long.parseLong(state.get("snapshotAt"));
                if (!"microseconds".equals(state.get("snapshotTimeUnit"))) oldAt = Math.multiplyExact(oldAt, 1000L);
            }
        } catch (NumberFormatException | ArithmeticException ignored) { oldAt = Long.MIN_VALUE; }
        if (generatedAt < oldAt) return false;
        state.put("snapshot", snapshot); state.put("snapshotAt", Long.toString(generatedAt)); state.put("snapshotVersion", "1"); state.put("snapshotTimeUnit", "microseconds");
        // Payload persistence is best effort and must not fence valid credentials.
        Map<String, String> all = new LinkedHashMap<>(backend.read()); String prefix = connection + ".";
        state.forEach((key, value) -> all.put(prefix + key, value)); return backend.commit(all);
    }
    /** Upgrade legacy millisecond ordering without rewriting or racing a newer payload. */
    public synchronized boolean upgradeSnapshotTimestamp(String connection, Map<String, String> expected, String snapshot, long generatedAt) {
        if (!valid(connection, expected)) return false;
        Map<String, String> state = state(connection);
        if (!snapshot.equals(state.get("snapshot"))) return false;
        if ("microseconds".equals(state.get("snapshotTimeUnit"))) return true;
        state.put("snapshotAt", Long.toString(generatedAt)); state.put("snapshotTimeUnit", "microseconds");
        Map<String, String> all = new LinkedHashMap<>(backend.read()); String prefix = connection + ".";
        state.forEach((key, value) -> all.put(prefix + key, value)); return backend.commit(all);
    }
    public synchronized void clearSnapshot(String connection, Map<String, String> expected) {
        Map<String, String> state = state(connection);
        if (expected != null && !same(state, expected, false)) return;
        if ("legacy".equals(state.get("mode"))) return;
        state.put("epoch", unique()); state.remove("snapshot"); state.remove("snapshotAt"); state.remove("snapshotVersion"); state.remove("snapshotTimeUnit");
        Map<String, String> all = new LinkedHashMap<>(backend.read());
        String prefix = connection + ".";
        all.keySet().removeIf(key -> key.startsWith(prefix));
        state.forEach((key, value) -> all.put(prefix + key, value));
        if (!backend.commit(all)) throw new IllegalStateException("Snapshot storage failed.");
    }
    private static final class FetchLease {
        final String owner, ticket;
        FetchLease(String owner, String ticket) { this.owner = owner; this.ticket = ticket; }
    }
    private static final class FetchPending {
        final String owner, connection; final Consumer<Map<String, Object>> success;
        FetchPending(String owner, String connection, Consumer<Map<String, Object>> success) {
            this.owner = owner; this.connection = connection; this.success = success;
        }
    }
    private static final class Lease {
        final String owner, connection, ticket, action, fetchTicket; String slot;
        Lease(String owner, String connection, String ticket, String action, String fetchTicket) {
            this.owner = owner; this.connection = connection; this.ticket = ticket; this.action = action; this.fetchTicket = fetchTicket;
        }
    }
    private static final class Pending {
        final String owner, connection, action, fetchTicket; final Map<String, String> expected;
        final Consumer<Map<String, Object>> success; final Consumer<Exception> failure;
        Pending(String owner, String connection, String action, Map<String, String> expected, String fetchTicket,
                Consumer<Map<String, Object>> success, Consumer<Exception> failure) {
            this.owner = owner; this.connection = connection; this.action = action; this.expected = expected; this.fetchTicket = fetchTicket;
            this.success = success; this.failure = failure;
        }
    }
}
