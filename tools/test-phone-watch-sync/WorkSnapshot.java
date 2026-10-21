import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteException;
import android.os.Build;
import android.os.ParcelFileDescriptor;
import android.os.Process;
import android.os.SystemClock;
import android.system.Os;
import android.system.OsConstants;
import android.system.StructStat;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileDescriptor;
import java.io.FileInputStream;
import java.io.InputStreamReader;
import java.nio.channels.FileLock;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

/** Standalone, fixed-query acceptance reader. Never loads the application or WorkManager. */
public final class WorkSnapshot {
    // Inspected in work-runtime 2.11.2 WorkDatabase_Impl / WorkTypeConverters.
    private static final String IDENTITY = "08b926448d86528e697981ddd30459f7";
    private static final String WORKER = "dev.fluttercommunity.workmanager.BackgroundWorker";
    private static final String NAME = "androidx.work.workdb";
    // SQLite's default Unix VFS lock bytes, not database contents. Guard the
    // entire range so both RESERVED writers and direct EXCLUSIVE mode changes
    // conflict, including a WAL-to-rollback transition during header inspection.
    // WAL writers use SHM locks instead; SQLite's read transaction pins that snapshot.
    private static final long PENDING_BYTE = 0x40000000L;
    private static final long RESERVED_BYTE = PENDING_BYTE + 1;
    private static final long SHARED_FIRST = RESERVED_BYTE + 1;
    private static final long SHARED_LAST = SHARED_FIRST + 509;
    private static final String COLUMNS =
            "initial_delay interval_duration flex_duration run_attempt_count backoff_policy "
            + "backoff_delay_duration last_enqueue_time schedule_requested_at period_count generation "
            + "next_schedule_time_override next_schedule_time_override_generation stop_reason "
            + "required_network_type requires_charging requires_device_idle requires_battery_not_low "
            + "requires_storage_not_low trigger_content_update_delay trigger_max_content_delay "
            + "backoff_on_system_interruptions";
    private static final long START = SystemClock.elapsedRealtime();

    private WorkSnapshot() {}

    private static final class Hold extends RuntimeException {
        Hold(String category) { super(category); }
    }

    private static void require(boolean value, String category) {
        if (!value) throw new Hold(category);
        if (SystemClock.elapsedRealtime() - START > 4000) throw new Hold("READER_DEADLINE");
    }

    private static String identity() throws Exception {
        String stat;
        try (BufferedReader in = new BufferedReader(new InputStreamReader(
                new FileInputStream("/proc/self/stat"), StandardCharsets.US_ASCII))) {
            stat = in.readLine();
        }
        String[] fields = stat.substring(stat.lastIndexOf(") ") + 2).split(" ");
        return Process.myPid() + " " + Long.parseLong(fields[19]);
    }

    private static void installedVersion(String apk) throws Exception {
        require(apk.matches("/data/app/[A-Za-z0-9_./=+~\\-]+/base\\.apk")
                && !apk.contains("/../"), "INSTALLED_APK_LAYOUT");
        try (ZipFile zip = new ZipFile(apk)) {
            ZipEntry entry = zip.getEntry("META-INF/androidx.work_work-runtime.version");
            require(entry != null && entry.getSize() > 0 && entry.getSize() <= 32,
                    "INSTALLED_LIBRARY_IDENTITY");
            try (java.io.InputStream in = zip.getInputStream(entry)) {
                byte[] bytes = new byte[33];
                int count = 0, n;
                while (count < bytes.length && (n = in.read(bytes, count, bytes.length - count)) > 0) {
                    count += n;
                }
                require(count <= 32 && new String(bytes, 0, count, StandardCharsets.US_ASCII)
                        .trim().equals("2.11.2"), "INSTALLED_LIBRARY_IDENTITY");
            }
        }
    }

    private static File database() throws Exception {
        File root = new File(".").getCanonicalFile();
        require(root.getPath().matches("/data/user/[0-9]+/app\\.wardpulse"), "APP_DATA_LOCATION");
        File current = new File(root, "no_backup/" + NAME);
        File historical = new File(root, "databases/" + NAME);
        require(current.exists() != historical.exists(), "DATABASE_MISSING_OR_AMBIGUOUS");
        File selected = current.exists() ? current : historical;
        require(selected.equals(selected.getCanonicalFile()) && selected.isFile(), "DATABASE_LOCATION");
        return selected;
    }

    private static void noSidecar(File file, String suffix) {
        require(!Files.exists(new File(file.getPath() + suffix).toPath(),
                LinkOption.NOFOLLOW_LINKS), "UNEXPECTED_JOURNAL_OR_SIDECAR");
    }

    private static boolean walMode(File file, FileInputStream input) throws Exception {
        require(input.getChannel().size() >= 100
                && input.getChannel().size() <= 64 * 1024 * 1024, "DATABASE_SIZE");
        noSidecar(file, "-journal");
        byte[] header = new byte[100];
        // Never open/close another descriptor for this inode while guarding it:
        // POSIX locks belong to the process, and any such close releases them.
        input.getChannel().position(0);
        int offset = 0, n;
        while (offset < header.length
                && (n = input.read(header, offset, header.length - offset)) > 0) {
            offset += n;
        }
        require(offset == header.length, "DATABASE_HEADER");
        require(new String(header, 0, 15, StandardCharsets.US_ASCII)
                .equals("SQLite format 3") && header[15] == 0, "DATABASE_HEADER");
        require((header[18] == 1 && header[19] == 1)
                || (header[18] == 2 && header[19] == 2), "JOURNAL_MODE_UNSUPPORTED");
        return header[18] == 2;
    }

    private static StructStat sameFile(File file, FileDescriptor fd) throws Exception {
        StructStat held = Os.fstat(fd), path = Os.stat(file.getPath());
        require(file.equals(file.getCanonicalFile())
                && held.st_dev == path.st_dev && held.st_ino == path.st_ino
                && held.st_uid == Process.myUid() && OsConstants.S_ISREG(held.st_mode),
                "DATABASE_IDENTITY");
        require((Os.fcntlInt(fd, OsConstants.F_GETFL, 0) & OsConstants.O_ACCMODE)
                == OsConstants.O_RDONLY, "READ_ONLY_DESCRIPTOR_REQUIRED");
        return held;
    }

    private static ParcelFileDescriptor sidecar(File file, String suffix, boolean wal)
            throws Exception {
        if (!wal) {
            noSidecar(file, suffix);
            return null;
        }
        File path = new File(file.getPath() + suffix);
        require(path.equals(path.getCanonicalFile()) && path.isFile(), "WAL_SIDECAR_REQUIRED");
        ParcelFileDescriptor descriptor = ParcelFileDescriptor.open(path,
                ParcelFileDescriptor.MODE_READ_ONLY);
        try {
            sidecarIdentity(file, suffix, descriptor);
            return descriptor;
        } catch (Exception failure) {
            descriptor.close();
            throw failure;
        }
    }

    private static void sidecarIdentity(File file, String suffix, ParcelFileDescriptor descriptor)
            throws Exception {
        if (descriptor == null) {
            noSidecar(file, suffix);
        } else {
            StructStat s = sameFile(new File(file.getPath() + suffix), descriptor.getFileDescriptor());
            require(s.st_size >= 0 && s.st_size <= (suffix.equals("-shm") ? 4194304 : 67108864),
                    "WAL_SIDECAR_SIZE");
        }
    }

    private static void requireStableJournalMode(File file, ParcelFileDescriptor descriptor,
            FileLock guard, boolean reading) throws Exception {
        require(guard != null && guard.isValid() && guard.isShared(), "JOURNAL_LOCK_UNAVAILABLE");
        StructStat held = sameFile(file, descriptor.getFileDescriptor());
        // isValid() is a Java bookkeeping check, not proof that SQLite has not
        // released a process-associated lock. Inspect only this owned FD's kernel
        // lock records, before open, after open/BEGIN, and during the read transaction.
        byte[] bytes = new byte[4097];
        int count = 0, n;
        try (FileInputStream in = new FileInputStream("/proc/self/fdinfo/" + descriptor.getFd())) {
            while (count < bytes.length && (n = in.read(bytes, count, bytes.length - count)) > 0) {
                count += n;
            }
        }
        require(count > 0 && count < bytes.length, "JOURNAL_LOCK_EVIDENCE_BOUND");
        boolean inode = false, pending = false, reserved = false, shared = false;
        for (String line : new String(bytes, 0, count, StandardCharsets.US_ASCII).split("\n")) {
            String[] fields = line.trim().split("\\s+");
            if (fields[0].equals("ino:")) {
                require(fields.length == 2 && fields[1].equals(Long.toString(held.st_ino)),
                        "JOURNAL_LOCK_IDENTITY");
                inode = true;
            } else if (fields[0].equals("lock:")) {
                require(fields.length == 9 && fields[2].equals("POSIX")
                        && fields[3].equals("ADVISORY") && fields[4].equals("READ")
                        && fields[5].equals(Integer.toString(Process.myPid()))
                        && fields[6].matches("[0-9a-f]+:[0-9a-f]+:" + held.st_ino)
                        && fields[7].matches("[0-9]+")
                        && (fields[8].equals("EOF") || fields[8].matches("[0-9]+")),
                        "JOURNAL_LOCK_ENCODING");
                long first = Long.parseLong(fields[7]);
                long last = fields[8].equals("EOF") ? Long.MAX_VALUE : Long.parseLong(fields[8]);
                pending |= first <= PENDING_BYTE && last >= PENDING_BYTE;
                reserved |= first <= RESERVED_BYTE && last >= RESERVED_BYTE;
                shared |= first <= SHARED_FIRST && last >= SHARED_LAST;
            }
        }
        // SQLite releases its transient PENDING read lock on acquiring SHARED;
        // RESERVED excludes rollback writers; SHARED excludes journal conversion.
        // Neither proves WAL quiescence: ordinary SQLite SHM locks provide the read snapshot.
        require(inode && reserved && shared && (reading || pending),
                "JOURNAL_MODE_STABILITY_UNPROVEN");
    }

    private static String scalar(SQLiteDatabase db, String sql) {
        try (Cursor c = db.rawQuery(sql, null)) {
            require(c.moveToFirst() && !c.isNull(0), "SCHEMA_VALUE");
            String value = c.getString(0);
            require(!c.moveToNext(), "SCHEMA_CARDINALITY");
            return value;
        }
    }

    private static void columns(SQLiteDatabase db, String table, String texts, String numbers,
            String blobs) {
        Set<String> requiredText = new HashSet<>(Arrays.asList(texts.split(" ")));
        Set<String> requiredNumber = new HashSet<>(Arrays.asList(numbers.split(" ")));
        Set<String> requiredBlob = new HashSet<>(Arrays.asList(blobs.split(" ")));
        requiredText.remove("");
        requiredNumber.remove("");
        requiredBlob.remove("");
        try (Cursor c = db.rawQuery("PRAGMA table_info(`" + table + "`)", null)) {
            int count = 0;
            while (c.moveToNext()) {
                require(++count <= 64, "SCHEMA_BOUND");
                String name = c.getString(1), type = c.getString(2);
                if (requiredText.remove(name)) require(type.equals("TEXT"), "SCHEMA_COLUMNS");
                if (requiredNumber.remove(name)) require(type.equals("INTEGER"), "SCHEMA_COLUMNS");
                if (requiredBlob.remove(name)) require(type.equals("BLOB"), "SCHEMA_COLUMNS");
            }
        }
        require(requiredText.isEmpty() && requiredNumber.isEmpty() && requiredBlob.isEmpty(),
                "SCHEMA_COLUMNS");
    }

    private static long integer(Cursor c, int i, long minimum) {
        require(c.getType(i) == Cursor.FIELD_TYPE_INTEGER, "WORK_VALUE_TYPE");
        long value = c.getLong(i);
        require(value >= minimum, "WORK_VALUE_RANGE");
        return value;
    }

    private static String platform(SQLiteDatabase db, boolean wal) {
        String version = scalar(db, "SELECT sqlite_version()");
        String source = scalar(db, "SELECT sqlite_source_id()");
        require(version.equals("3.44.3") || version.equals("3.44.4"), "SQLITE_VERSION_UNREVIEWED");
        require(source.length() <= 100 && source.matches(
                "[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} [0-9a-f]{64}(-alt[0-9]+)?"),
                "SQLITE_SOURCE_ID_UNSUPPORTED");
        String mode = wal ? "wal" : "delete";
        require(scalar(db, "PRAGMA journal_mode").equals(mode), "JOURNAL_MODE_CHANGED");
        // Fixed nonsecret metadata for HOST binding, not proof of a vendor binary's behavior.
        return "SQLITE " + version + " " + source + " " + mode;
    }

    private static String project(SQLiteDatabase db) {
        // No input, output, progress, tags, preferences or payload contents are queried.
        // The two blob-derived booleans only reject unsupported constraint encodings.
        String sql = "SELECT n.name,w.id,w.state,w.worker_class_name,"
                + "w.interval_duration,w.flex_duration,w.initial_delay,w.required_network_type,"
                + "w.requires_charging,w.requires_device_idle,w.requires_battery_not_low,"
                + "w.requires_storage_not_low,w.generation,s.system_id,w.last_enqueue_time,"
                + "w.schedule_requested_at,w.run_attempt_count,w.period_count,w.backoff_policy,"
                + "w.backoff_delay_duration,w.next_schedule_time_override,"
                + "w.next_schedule_time_override_generation,w.stop_reason,"
                + "CASE WHEN typeof(w.required_network_request)='blob' "
                + "AND length(w.required_network_request)=0 THEN 0 ELSE 1 END,"
                + "CASE WHEN typeof(w.content_uri_triggers)='blob' "
                + "AND length(w.content_uri_triggers)=0 THEN 0 ELSE 1 END,"
                + "w.trigger_content_update_delay,w.trigger_max_content_delay,"
                + "w.backoff_on_system_interruptions "
                + "FROM WorkName n LEFT JOIN WorkSpec w ON w.id=n.work_spec_id "
                + "LEFT JOIN SystemIdInfo s ON s.work_spec_id=w.id AND s.generation=w.generation "
                + "WHERE n.name IN ('wardpulse.providerSync','wardpulse.recoveryWake') "
                + "ORDER BY n.name,w.id LIMIT 33";
        StringBuilder out = new StringBuilder();
        Set<String> ids = new HashSet<>();
        int rows = 0, provider = 0, recovery = 0;
        try (Cursor c = db.rawQuery(sql, null)) {
            while (c.moveToNext()) {
                require(++rows <= 32, "WORK_ROW_BOUND");
                String name = c.getString(0), id = c.getString(1);
                require(id != null && id.matches("[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}")
                        && ids.add(id), "WORK_ID_OR_JOIN");
                long state = integer(c, 2, 0);
                require(state <= 5 && WORKER.equals(c.getString(3)), "WORK_STATE_OR_WORKER");
                long interval = integer(c, 4, 0), flex = integer(c, 5, 0);
                require(integer(c, 7, 0) == 1, "CONNECTED_NETWORK_REQUIRED");
                for (int i = 8; i <= 11; i++) require(integer(c, i, 0) == 0, "UNEXPECTED_CONSTRAINT");
                require(integer(c, 23, 0) == 0 && integer(c, 24, 0) == 0,
                        "UNSUPPORTED_CONSTRAINT_ENCODING");
                require(integer(c, 25, -1) == -1 && integer(c, 26, -1) == -1,
                        "UNEXPECTED_CONTENT_CONSTRAINT");
                if (name.equals("wardpulse.providerSync")) {
                    require(interval >= 900000 && flex >= 300000 && flex <= interval,
                            "PERIODIC_SPEC");
                    require(state != 4, "PERIODIC_DEPENDENCY");
                    if (state == 0 || state == 1) provider++;
                } else {
                    require(name.equals("wardpulse.recoveryWake") && interval == 0 && flex == 0,
                            "RECOVERY_SPEC");
                    if (state == 0 || state == 1 || state == 4) recovery++;
                }
                require(integer(c, 18, 0) <= 1, "BACKOFF_ENCODING");
                for (int i : new int[] {12, 16, 17, 21}) {
                    require(integer(c, i, 0) <= Integer.MAX_VALUE, "WORK_COUNTER_RANGE");
                }
                if (!c.isNull(13)) require(integer(c, 13, 0) <= Integer.MAX_VALUE, "JOB_ID_RANGE");
                out.append("WORK ").append(name).append(' ').append(id).append(' ')
                        .append(state).append(' ').append(WORKER);
                for (int i = 4; i <= 22; i++) {
                    long min = (i == 14 || i == 15) ? -1 : (i == 22 ? -256 : 0);
                    out.append(' ').append(i == 13 && c.isNull(i) ? -1 : integer(c, i, min));
                }
                long interruptBackoff = c.isNull(27) ? -1 : integer(c, 27, 0);
                require(interruptBackoff <= 1, "BACKOFF_INTERRUPTION_ENCODING");
                out.append(' ').append(interruptBackoff);
                out.append('\n');
            }
        }
        require(provider == 1 && recovery <= 1, "LOGICAL_WORK_CARDINALITY");
        require(out.length() <= 12288, "WORK_OUTPUT_BOUND");
        return out.toString();
    }

    private static String snapshot(String apk) throws Exception {
        installedVersion(apk);
        File file = database();
        String projection, sqlite;
        ParcelFileDescriptor descriptor = ParcelFileDescriptor.open(file,
                ParcelFileDescriptor.MODE_READ_ONLY);
        try (ParcelFileDescriptor.AutoCloseInputStream input =
                new ParcelFileDescriptor.AutoCloseInputStream(descriptor);
                FileLock guard = input.getChannel().tryLock(PENDING_BYTE,
                        SHARED_LAST - PENDING_BYTE + 1, true)) {
            requireStableJournalMode(file, descriptor, guard, false);
            boolean wal = walMode(file, input);
            requireStableJournalMode(file, descriptor, guard, false);
            // API36 READONLY skips journal/sync/checkpoint configuration; NO_LOCALIZED
            // also skips locale/metadata queries. No pre-BEGIN schema read is requested.
            // Retain every extra DB/sidecar descriptor until AFTER SQLite close:
            // closing any descriptor for an inode releases this process's POSIX locks.
            // Existing WAL/SHM are required. SQLite may automatically initialize/rebuild
            // the SHM index and coordinate read marks, even as the first reader after
            // app death. No explicit sidecar writes, checkpoint or writable fallback.
            try (ParcelFileDescriptor walFile = sidecar(file, "-wal", wal);
                    ParcelFileDescriptor shmFile = sidecar(file, "-shm", wal)) {
                try (SQLiteDatabase db = SQLiteDatabase.openDatabase(file.getPath(), null,
                        SQLiteDatabase.OPEN_READONLY | SQLiteDatabase.NO_LOCALIZED_COLLATORS,
                        ignored -> { throw new Hold("DATABASE_CORRUPTION"); })) {
                    requireStableJournalMode(file, descriptor, guard, false);
                    require(db.isReadOnly(), "READ_ONLY_REQUIRED");
                    db.beginTransactionReadOnly();
                    try {
                        requireStableJournalMode(file, descriptor, guard, false);
                        // First pager read establishes a committed SQLite snapshot, including
                        // WAL frames under SQLite's own SHM reader/recovery locks.
                        require(scalar(db, "PRAGMA user_version").equals("24"), "SCHEMA_VERSION");
                        requireStableJournalMode(file, descriptor, guard, true);
                        sqlite = platform(db, wal);
                        require(scalar(db, "SELECT identity_hash FROM room_master_table WHERE id=42")
                                .equals(IDENTITY), "SCHEMA_IDENTITY");
                        require(scalar(db, "SELECT count(*) FROM sqlite_master WHERE type='table' "
                                + "AND name IN ('WorkName','WorkSpec','SystemIdInfo','room_master_table')")
                                .equals("4"), "SCHEMA_TABLES");
                        columns(db, "WorkName", "name work_spec_id", "", "");
                        columns(db, "WorkSpec", "id worker_class_name", "state " + COLUMNS,
                                "required_network_request content_uri_triggers");
                        columns(db, "SystemIdInfo", "work_spec_id", "generation system_id", "");
                        projection = project(db);
                        requireStableJournalMode(file, descriptor, guard, true);
                        sidecarIdentity(file, "-wal", walFile);
                        sidecarIdentity(file, "-shm", shmFile);
                    } finally {
                        db.endTransaction();
                    }
                } catch (SQLiteException failure) {
                    throw new Hold("SQLITE_READ_OR_LOCK_UNAVAILABLE");
                }
                // No SQLite operation follows transaction end/close. Do not compare
                // DB/WAL/SHM byte stamps: WAL writers and automatic SHM coordination
                // can legitimately change them without changing our committed snapshot.
                sameFile(file, descriptor.getFileDescriptor());
                sidecarIdentity(file, "-wal", walFile);
                sidecarIdentity(file, "-shm", shmFile);
                noSidecar(file, "-journal");
            }
        }
        return "SCHEMA 2.11.2 24 " + IDENTITY + " " + file.getParentFile().getName()
                + "\n" + sqlite + "\nTIME " + System.currentTimeMillis() + "\n" + projection;
    }

    public static void main(String[] args) {
        Thread watchdog = new Thread(() -> {
            SystemClock.sleep(6000);
            Runtime.getRuntime().halt(1);
        }, "work-snapshot-deadline");
        watchdog.setDaemon(true);
        watchdog.start();
        int status = 1;
        try {
            require(args.length == 2 && Build.VERSION.SDK_INT == 36
                    && Process.myUid() == Integer.parseInt(args[0]), "READER_PLATFORM_OR_UID");
            String process = identity();
            System.out.println("READER " + process);
            System.out.flush();
            // Deliberate stdin contract: host verifies this real PID/start before GO.
            byte[] go = new byte[3];
            int offset = 0, n;
            while (offset < go.length && (n = System.in.read(go, offset, go.length - offset)) > 0) {
                offset += n;
            }
            require(offset == 3 && Arrays.equals(go, new byte[] {'G', 'O', '\n'}), "READER_HANDSHAKE");
            String result = snapshot(args[1]);
            require(identity().equals(process), "READER_IDENTITY");
            System.out.print(result);
            System.out.println("END " + process);
            status = 0;
        } catch (Hold failure) {
            System.out.println("HOLD " + failure.getMessage());
        } catch (Throwable failure) {
            // Never print SQL, paths, exception messages or platform stack traces.
            System.out.println("HOLD READER_UNSUPPORTED_OR_RACED");
        }
        System.out.flush();
        System.exit(status);
    }
}
