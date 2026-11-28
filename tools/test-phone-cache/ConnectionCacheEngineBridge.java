package app.wardpulse.watchsync;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Base64;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Test-only transport to exercise Dart adapters against the production Java engine. */
public final class ConnectionCacheEngineBridge {
    static final class Disk implements ConnectionCacheEngine.Backend {
        Map<String, String> data = new HashMap<>(); boolean fail;
        public Map<String, String> read() { return new HashMap<>(data); }
        public boolean commit(Map<String, String> values) { if (fail) return false; data = new HashMap<>(values); return true; }
    }
    static final Disk disk = new Disk();
    static final Disk modes = new Disk();
    static boolean mockAllowed = true;
    static long now;
    static ConnectionCacheEngine engine = create();
    static ConnectionCacheEngine create() { return new ConnectionCacheEngine(disk, modes, () -> now, mockAllowed); }
    static Long optionalLong(String value) { return value == null ? null : Long.valueOf(value); }
    static List<String> occurrences(Map<String, String> args) {
        String joined = args.getOrDefault("occurrences", "");
        return joined.isEmpty() ? List.of() : List.of(joined.split("\n"));
    }
    public static void main(String[] unused) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
        String line;
        while ((line = input.readLine()) != null) {
            String[] fields = line.split("\t", -1);
            String id = fields[0], method = fields[1], owner = fields[2];
            Map<String, String> args = new HashMap<>();
            for (int index = 3; index < fields.length; index += 2)
                args.put(fields[index], new String(Base64.getDecoder().decode(fields[index + 1]), StandardCharsets.UTF_8));
            try { dispatch(id, method, owner, args); }
            catch (Exception error) { response(id, null, true); }
        }
    }
    static void dispatch(String id, String method, String owner, Map<String, String> args) {
        String connection = args.get("connection");
        Map<String, String> collected = new HashMap<>();
        args.forEach((key, value) -> { if (key.startsWith("expected.")) collected.put(key.substring(9), value); });
        Map<String, String> expected = collected.isEmpty() ? null : collected;
        switch (method) {
            case "acquire": engine.acquire(owner, connection, args.get("action"), expected, args.get("fetchTicket"),
                optionalLong(args.get("generation")), args.get("settlementLease"),
                value -> response(id, value, false), error -> response(id, null, true)); return;
            case "acquireFetch": engine.acquireFetch(owner, connection, optionalLong(args.get("generation")),
                value -> response(id, value, false), error -> response(id, null, true)); return;
            case "releaseFetch": response(id, engine.releaseFetch(owner, connection, args.get("fetchTicket"),
                optionalLong(args.get("reportAtMillis"))), false); return;
            case "validFetch": response(id, engine.validFetch(owner, connection, args.get("fetchTicket"),
                Boolean.parseBoolean(args.get("forAdmission"))), false); return;
            case "claimAutomatic": response(id, engine.claimAutomatic(owner, connection, args.get("fetchTicket"), expected, Long.parseLong(args.get("intervalMillis")),
                Boolean.parseBoolean(args.get("cacheOnly"))), false); return;
            case "stampFetch": response(id, engine.stampFetch(owner, connection, args.get("fetchTicket"), expected), false); return;
            case "finish": response(id, engine.finish(owner, connection, args.get("lease"), args.get("operation"), args.get("identity")), false); return;
            case "prepareMigration": response(id, engine.prepareMigration(owner, connection, args.get("lease")), false); return;
            case "queueLegacyCleanup": engine.queueLegacyCleanup(owner, connection, args.get("lease")); response(id, null, false); return;
            case "acknowledgeCleanup": response(id, engine.acknowledgeCleanup(owner, connection, args.get("lease"),
                args.getOrDefault("cleaned", "").isEmpty() ? List.of() : List.of(args.get("cleaned").split("\n"))), false); return;
            case "readNotice": response(id, engine.readNotice(connection), false); return;
            case "dismissNotice": response(id, engine.dismissNotice(connection, args.get("eventId")), false); return;
            case "valid": response(id, engine.valid(connection, expected), false); return;
            case "ownsAutomatic": response(id, engine.ownsAutomatic(connection, expected), false); return;
            case "validAll":
                Map<String, Map<String, String>> versions = new HashMap<>();
                Map<String, Long> attemptClockEras = new HashMap<>();
                Map<String, Map<String, Object>> payloadOrders = new HashMap<>();
                Map<String, String> emptyCacheOrders = new HashMap<>();
                String eraPrefix = "attemptClockEras.";
                String payloadPrefix = "payloadOrders.";
                String emptyOrderPrefix = "emptyCacheOrders.";
                args.forEach((key, value) -> {
                    if (key.startsWith(eraPrefix)) {
                        attemptClockEras.put(key.substring(eraPrefix.length()), Long.valueOf(value));
                        return;
                    }
                    if (key.startsWith(payloadPrefix)) {
                        String suffix = key.substring(payloadPrefix.length());
                        int dot = suffix.lastIndexOf('.');
                        String field = suffix.substring(dot + 1);
                        payloadOrders.computeIfAbsent(suffix.substring(0, dot), ignored -> new HashMap<>())
                            .put(field, "rowId".equals(field) ? value : Long.valueOf(value));
                        return;
                    }
                    if (key.startsWith(emptyOrderPrefix)) {
                        emptyCacheOrders.put(key.substring(emptyOrderPrefix.length()), value);
                        return;
                    }
                    if (!key.startsWith("versions.")) return;
                    String suffix = key.substring(9); int dot = suffix.lastIndexOf('.');
                    versions.computeIfAbsent(suffix.substring(0, dot), ignored -> new HashMap<>()).put(suffix.substring(dot + 1), value);
                });
                boolean current = engine.validAll(versions, attemptClockEras, payloadOrders, emptyCacheOrders,
                    optionalLong(args.get("recoveryPreferenceRevision")), optionalLong(args.get("recoveryModeGeneration")));
                response(id, current && !Boolean.parseBoolean(args.get("rejectValidation")), false);
                return;
            case "readSnapshot": {
                boolean ordered = Boolean.parseBoolean(args.get("ordered"));
                Map<String, Object> row = engine.readSnapshotPair(connection, expected,
                    ordered && Boolean.parseBoolean(args.get("forSelection")), optionalLong(args.get("generation")));
                response(id, ordered ? row : row.get("snapshot"), false); return;
            }
            case "writeSnapshot": {
                String snapshot = args.get("snapshot");
                long generatedAt = Long.parseLong(args.get("generatedAt"));
                boolean ordered = Boolean.parseBoolean(args.get("ordered"));
                Map<String, Object> write = engine.writeSnapshotOrdered(owner, connection, expected, snapshot, generatedAt,
                    ordered ? args.get("stamp") : null, optionalLong(args.get("generation")));
                response(id, ordered ? write : "stored".equals(write.get("status")), false); return;
            }
            case "upgradeSnapshotTimestamp": response(id, engine.upgradeSnapshotTimestamp(connection, expected, args.get("snapshot"),
                Long.parseLong(args.get("generatedAt")), optionalLong(args.get("generation"))), false); return;
            case "clearSnapshot": engine.clearSnapshot(connection, expected, optionalLong(args.get("generation")));
                response(id, null, false); return;
            case "beginRecoveryPreferenceWrite": response(id, engine.beginRecoveryPreferenceWrite(owner), false); return;
            case "finishRecoveryPreferenceWrite": engine.finishRecoveryPreferenceWrite(owner, args.get("token"));
                response(id, null, false); return;
            case "readRecoveryPreferenceRevision": response(id, engine.readRecoveryPreferenceRevision(), false); return;
            case "recoveryDeliveryCurrent": response(id, engine.recoveryDeliveryCurrent(Long.parseLong(args.get("revision")),
                optionalLong(args.get("generation"))), false); return;
            case "readUnrecordedRecoveries": response(id, engine.readUnrecordedRecoveries(), false); return;
            case "recordUnrecordedRecoveries": engine.recordUnrecordedRecoveries(occurrences(args)); response(id, null, false); return;
            case "forgetUnrecordedRecoveries": engine.forgetUnrecordedRecoveries(occurrences(args)); response(id, null, false); return;
            case "readMode": response(id, engine.readMode(), false); return;
            case "initializeMode": response(id, engine.initializeMode(Boolean.parseBoolean(args.get("legacyMock"))), false); return;
            case "beginModeImport": engine.beginModeImport(owner, token -> response(id, token, false), error -> response(id, null, true)); return;
            case "finishModeImport":
                engine.finishModeImport(owner, args.get("token"), args.containsKey("legacyMock") ? Boolean.valueOf(args.get("legacyMock")) : null);
                response(id, null, false); return;
            case "beginOperation":
                if (Boolean.parseBoolean(args.get("waitForSwitch"))) {
                    engine.beginAfterSwitch(owner, value -> response(id, value, false), error -> response(id, null, true));
                } else response(id, engine.beginOperation(), false);
                return;
            case "operationCurrent": response(id, engine.operationCurrent(Long.parseLong(args.get("generation"))), false); return;
            case "enterEffect": response(id, engine.enterEffect(owner, Long.parseLong(args.get("generation")),
                Boolean.parseBoolean(args.get("settlement"))), false); return;
            case "exitEffect": engine.exitEffect(owner, args.get("lease"), Boolean.parseBoolean(args.get("unresolved"))); response(id, null, false); return;
            case "switchMode":
                engine.switchMode(owner, args.get("mode"), value -> response(id, value, false), error -> {
                    if (error instanceof ConnectionCacheEngine.ModeWriteFailure) {
                        ConnectionCacheEngine.ModeWriteFailure failure = (ConnectionCacheEngine.ModeWriteFailure) error;
                        Map<String, Object> details = new HashMap<>();
                        details.put("code", "data_mode_write_failed");
                        details.put("details", failure.unresolvedStorageFailure);
                        response(id, details, true);
                    } else response(id, null, true);
                });
                return;
            case "failModeCommit": modes.fail = Boolean.parseBoolean(args.get("value")); response(id, null, false); return;
            // A Profile or Release process: the same records under the production policy.
            case "setMockAllowed": mockAllowed = Boolean.parseBoolean(args.get("value")); engine = create(); response(id, null, false); return;
            case "restart": engine = create(); response(id, null, false); return;
            case "reset": disk.data.clear(); disk.fail = false; modes.data.clear(); modes.fail = false; mockAllowed = true; now = 0;
                engine = create(); response(id, null, false); return;
            case "setClock": now = Long.parseLong(args.get("value")); response(id, null, false); return;
            case "setDisk": disk.data.put(args.get("key"), args.get("value")); response(id, null, false); return;
            case "failCommit": disk.fail = Boolean.parseBoolean(args.get("value")); response(id, null, false); return;
            case "detach": engine.detach(owner); response(id, null, false); return;
            default: throw new IllegalArgumentException("Unknown test method.");
        }
    }
    static synchronized void response(String id, Object value, boolean failed) {
        String json = json(value);
        System.out.println(id + "\t" + (failed ? "error" : "ok") + "\t" + Base64.getEncoder().encodeToString(json.getBytes(StandardCharsets.UTF_8)));
        System.out.flush();
    }
    static String json(Object value) {
        if (value == null) return "null";
        if (value instanceof Boolean || value instanceof Number) return value.toString();
        if (value instanceof Map) {
            List<String> entries = new ArrayList<>();
            ((Map<?, ?>)value).forEach((key, item) -> entries.add(json(key.toString()) + ":" + json(item)));
            return "{" + String.join(",", entries) + "}";
        }
        if (value instanceof Iterable) {
            List<String> items = new ArrayList<>(); for (Object item : (Iterable<?>)value) items.add(json(item));
            return "[" + String.join(",", items) + "]";
        }
        return "\"" + value.toString().replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t") + "\"";
    }
}
