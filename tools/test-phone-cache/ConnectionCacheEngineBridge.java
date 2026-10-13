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
    static ConnectionCacheEngine engine = new ConnectionCacheEngine(disk);
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
                value -> response(id, value, false), error -> response(id, null, true)); return;
            case "acquireFetch": engine.acquireFetch(owner, connection, value -> response(id, value, false)); return;
            case "releaseFetch": engine.releaseFetch(owner, connection, args.get("fetchTicket")); response(id, null, false); return;
            case "validFetch": response(id, engine.validFetch(owner, connection, args.get("fetchTicket")), false); return;
            case "finish": response(id, engine.finish(owner, connection, args.get("lease"), args.get("operation"), args.get("identity")), false); return;
            case "prepareMigration": response(id, engine.prepareMigration(owner, connection, args.get("lease")), false); return;
            case "queueLegacyCleanup": engine.queueLegacyCleanup(owner, connection, args.get("lease")); response(id, null, false); return;
            case "acknowledgeCleanup": response(id, engine.acknowledgeCleanup(owner, connection, args.get("lease"),
                args.getOrDefault("cleaned", "").isEmpty() ? List.of() : List.of(args.get("cleaned").split("\n"))), false); return;
            case "valid": response(id, engine.valid(connection, expected), false); return;
            case "validAll":
                Map<String, Map<String, String>> versions = new HashMap<>();
                args.forEach((key, value) -> {
                    if (!key.startsWith("versions.")) return;
                    String suffix = key.substring(9); int dot = suffix.lastIndexOf('.');
                    versions.computeIfAbsent(suffix.substring(0, dot), ignored -> new HashMap<>()).put(suffix.substring(dot + 1), value);
                });
                response(id, engine.validAll(versions), false); return;
            case "readSnapshot": response(id, engine.readSnapshot(connection, expected), false); return;
            case "writeSnapshot": response(id, engine.writeSnapshot(connection, expected, args.get("snapshot"), Long.parseLong(args.get("generatedAt"))), false); return;
            case "upgradeSnapshotTimestamp": response(id, engine.upgradeSnapshotTimestamp(connection, expected, args.get("snapshot"), Long.parseLong(args.get("generatedAt"))), false); return;
            case "clearSnapshot": engine.clearSnapshot(connection, expected); response(id, null, false); return;
            case "restart": engine = new ConnectionCacheEngine(disk); response(id, null, false); return;
            case "reset": disk.data.clear(); disk.fail = false; engine = new ConnectionCacheEngine(disk); response(id, null, false); return;
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
