# Fixture Validation Tools

Automation for fixture and schema checks.

Every file under `schemas/` and `fixtures/` must parse, and every golden fixture in
`fixtures/snapshots/` must match the schema named for it in `FIXTURE_SCHEMAS`. The schemas are
closed (`additionalProperties: false`), so a stray field, a missing required one, or a value of
the wrong shape fails the gate. A new golden fixture must be listed there: the run fails while
any file in `fixtures/snapshots/` has no schema named for it, so an unchecked fixture cannot pass
for a checked one.

A schema must be named `*.schema.json` for the same reason: that is the glob the checker reads,
and one named otherwise would sit unswept.

The watch payload version is checked across the three places that must agree: the `const` in
`watch_dashboard_summary.schema.json`, `SCHEMA_VERSION` in the Wear store, and `schemaVersion`
in the phone's sync service. A mismatch builds fine and fails at run time — the watch drops
every payload whose version it does not recognise — so the shells run this gate too
(`phone-android.yml`, `wear-android.yml`), not only the core workflow.

Provider fixtures (`fixtures/providers/`) are sanitized payloads from other people's APIs and
have no schema of ours to match; they are checked for syntax only.

All three file-decoding routes in [`validate_json.py`](validate_json.py) (`load_schemas`,
the `main` syntax sweep and its mapped-fixture read) use `load_json`. Bare `NaN`, `Infinity`
and `-Infinity` are invalid JSON and fail with the file name and token. Quoted occurrences
remain strings: they pass in string fields and fail in numeric fields. Finite numbers,
explicit nulls and zero retain their schema meanings. Booleans are not numbers, and a float
such as `1240.0` is not an integer, matching the strict Rust readers.

`check_string` asserts `format: date-time` as a parsed timezone-aware instant. Date-only
values and times without a timezone fail with the fixture field; UTC `Z`, explicit offsets
and fractional seconds remain valid. Separate `format: date` annotations retain their
existing behavior; they do not acquire the instant requirement. These tooling checks do not
change runtime DateTimeUtc parsing.

The checker reads the keyword subset these schemas use (`type`, `$ref`, `properties`,
`additionalProperties`, `required`, `items`, `enum`, `const`, `anyOf`, `allOf`, `minimum`,
`maximum`, `minLength`, `maxLength`, `maxItems`, `pattern`, and `date-time` for `format`). Every
schema is swept for anything outside that set before the fixtures are checked — branches no
fixture walks into included — so a rule cannot be added that the gate reads past.

Run the checks from the repository root:

```sh
just validate-fixtures
```

## Isolated regressions

The standard-library suite in [`test_validate_json.py`](test_validate_json.py),
`FixtureValidatorTests`, imports the actual production module and calls its unchanged `main`
and `load_schemas` entry points. It temporarily binds `ROOT` to an external
`TemporaryDirectory` and restricts `FIXTURE_SCHEMAS` to the existing watch-summary entry.
Every case uses regular input files: an independent watch-summary sample, byte-for-byte
copies of its three schema dependencies, and minimal synthetic phone/Wear version
declarations. Defects are confined to these copies. Cleanup restores both bindings and
removes owned inputs even after a failed assertion. Canonical inputs are never displaced,
repointed, overlaid or written.

Raw tokens are written into otherwise valid JSON, including at `today.usedPercent`.
Schema loading is also exercised directly. To independently reach the mapped-fixture read,
one test filters only that file out of the preceding syntax enumeration with `Path.glob`;
the real file read, decoder and validation remain intact. Provider fixtures prove syntax
decoding and SyntaxOnly behavior. Other controls cover quoted tokens, finite/null/zero
values, strict numeric types, timezone-aware instants, separate date annotations and the
existing schema, mapping and shell-version guards.

Run from the repository root:

```sh
python3 -B -m unittest discover -s tools/validate-fixtures -p 'test_*.py'
```

The same command is `just test-fixture-validator`, included in `just test-all`.
`just validate-fixtures` remains the separate gate over all canonical inputs. Each production
invocation emits a `fixture-validator-inputs` JSON record with a stable case name and the
relative paths, sizes and SHA256 hashes of every generated input, followed by a
`fixture-validator-result` record with its actual status and bounded diagnostics. No input
payload is printed. These records support the HOST comparison below; they are not gate
acceptance on their own. Separate flushed `fixture-validator-scratch` records identify the
owned temporary directory and whether it still exists after cleanup. Their absolute paths
are custody data, excluded from the stable input-byte comparison.

## One-shot HOST comparison

This is a post-whole-run HOST procedure, separate from ordinary writable Worker FINALIZE.
Native completion does not wait for it. Root first qualifies whole-run DONE, scoped
reader/controller retirement, a separate fresh public idle observation and actual successful
owning CLI exit when a CLI was used. MCP management requires no invented CLI exit. Root must
then establish exclusive Source custody, retire other readers, and qualify this final
procedure, tests, support inputs and interpreter. Do not start substitution without those
conditions. No clone, worktree, Source export, rewritten baseline or replay framework is used.

OLD is exactly `1ff850eaa618786d0d693450b747a7c7fa570fb2:tools/validate-fixtures/validate_json.py`,
Git blob `d367427df19be2c9c3cdd5be134d440c474ee7f6`, Git mode `100644`. Its production closure
is that single file and the same Python standard library. Retain the regular file's
filesystem permissions `0664` (full mode `0100664`). The only substituted Source bytes are
that production file; final tests, support inputs and interpreter stay identical in both
legs. Protected Source here means every tracked and nonignored untracked path; Root must
also qualify that no relevant input or reader is hidden outside this inventory.

After qualifying custody, run the following Runner-authored parent once from the repository
root on HOST. It retains its external scratch journal and logs on every outcome, including
failure; the printed location is a custody record, not a claim of cleanup. The journal saves
only the substituted file's final bytes, identity manifests and logs. It is not a Source
copy. The parent installs interrupt cleanup before mutation, allows at most 60 seconds per
test child, and terminates and waits its active test or Git reader before any restoration.
Signal handlers record interruption requests; safe checkpoints act on them after child
ownership is recorded, without interrupting cleanup. A running test remains bounded by its
60-second deadline. The qualified test closure starts no descendant readers. Do not use this
procedure if that assumption or the qualified ownership changes. An uncatchable parent termination requires the custodian
to retire all readers and restore from the retained journal before any further work; it
cannot produce acceptance.

```sh
python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import stat
import subprocess
import sys
import sysconfig
import tempfile
import time

root = Path.cwd()
relative = "tools/validate-fixtures/validate_json.py"
target = root / relative
revision = "1ff850eaa618786d0d693450b747a7c7fa570fb2"
blob = "d367427df19be2c9c3cdd5be134d440c474ee7f6"
command = ["python3", "-B", "-m", "unittest", "discover",
           "-s", "tools/validate-fixtures", "-p", "test_*.py"]
journal = Path(tempfile.mkdtemp(prefix="wardpulse-fixture-proof-"))
print(f"HOST journal retained: {journal}", flush=True)
active = None
pending_signal = None

def git(*args):
    try:
        child = start_reader(["git", *args], cwd=root, stdout=subprocess.PIPE)
        output, _ = child.communicate(timeout=60)
        if child.returncode:
            raise subprocess.CalledProcessError(child.returncode, child.args, output=output)
        return output
    finally:
        stop_reader()

def digest(data):
    return hashlib.sha256(data).hexdigest()

def identity(path):
    mode = path.lstat().st_mode
    if stat.S_ISREG(mode):
        return {"mode": mode, "sha256": digest(path.read_bytes())}
    if stat.S_ISLNK(mode):
        return {"mode": mode, "link": os.readlink(path)}
    raise RuntimeError(f"unsupported protected file type: {path}")

def protected():
    paths = set(git("ls-files", "-z", "--cached", "--others", "--exclude-standard").split(b"\0"))
    return {
        "source": {os.fsdecode(p): identity(root / os.fsdecode(p)) for p in sorted(paths) if p},
        "index": digest(git("ls-files", "--stage", "-z")),
        "refs": digest(git("for-each-ref", "--sort=refname",
                           "--format=%(refname) %(objectname) %(symref)")),
        "head": git("rev-parse", "--symbolic-full-name", "HEAD").decode().strip(),
        "commit": git("rev-parse", "HEAD").decode().strip(),
    }

def runtime():
    executable = Path(shutil.which("python3")).resolve()
    if executable != Path(sys.executable).resolve():
        raise RuntimeError("parent and child interpreters differ")
    libraries = {}
    for base in sorted({sysconfig.get_path("stdlib"), sysconfig.get_path("platstdlib")}):
        for directory, dirs, files in os.walk(base):
            dirs[:] = sorted(d for d in dirs if d not in ("site-packages", "dist-packages"))
            for name in sorted(files):
                path = Path(directory) / name
                libraries[str(path)] = identity(path)
    return {"executable": str(executable), "binary": identity(executable),
            "version": sys.version, "importPath": sys.path, "stdlib": libraries}

def save(name, value):
    (journal / name).write_text(json.dumps(value, sort_keys=True, indent=2) + "\n")

def require(condition, reason):
    if not condition:
        raise RuntimeError(reason)

def stop_reader():
    global active
    if active is not None:
        if active.poll() is None:
            try:
                os.killpg(active.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                active.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(active.pid, signal.SIGKILL)
                active.wait()
        else:
            active.wait()
        active = None

def interrupted(signum, frame):
    global pending_signal
    pending_signal = signum

def check_interruption():
    if pending_signal is not None:
        raise KeyboardInterrupt(f"HOST interrupted by signal {pending_signal}")

def start_reader(*args, **kwargs):
    global active
    active = subprocess.Popen(*args, **kwargs, start_new_session=True)
    return active

def restore(name):
    # Signal requests remain recorded; cleanup never raises them.
    try:
        stop_reader()
        if target.is_symlink():
            target.unlink()
        target.write_bytes(final)
        target.chmod(stat.S_IMODE(mode))
        after = protected()
        save(name, after)
        require(after == before, "FAILED RESTORATION or protected Source/index/refs drift")
    except BaseException as failure:
        save("restoration-failure.json", {"phase": name, "error": str(failure)})
        raise

def leg(name, expected):
    check_interruption()
    require(protected() == expected, f"{name}: Source/index/refs drift before test")
    require(runtime() == interpreter, f"{name}: interpreter/stdlib drift before test")
    check_interruption()
    with (journal / f"{name}.stdout").open("wb") as out, (journal / f"{name}.stderr").open("wb") as err:
        started = time.monotonic()
        start_reader(command, cwd=root, stdout=out, stderr=err)
        save(f"{name}-child.json", {"pid": active.pid, "command": command, "deadlineSeconds": 60})
        try:
            check_interruption()
            code = active.wait(timeout=max(0, started + 60 - time.monotonic()))
            check_interruption()
        except subprocess.TimeoutExpired:
            save(f"{name}-timeout.json", {"timedOut": True})
            raise
        finally:
            stop_reader()
    save(f"{name}-exit.json", {"returncode": code})
    require(protected() == expected, f"{name}: Source/index/refs changed during test")
    require(runtime() == interpreter, f"{name}: interpreter/stdlib changed during test")
    check_interruption()
    return code

for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
    signal.signal(sig, interrupted)

require(git("ls-tree", revision, "--", relative).decode().split()[:2] == ["100644", "blob"],
        "OLD Git mode/type mismatch")
require(git("rev-parse", f"{revision}:{relative}").decode().strip() == blob, "OLD blob mismatch")
old = git("cat-file", "blob", blob)
require(hashlib.sha1(b"blob " + str(len(old)).encode() + b"\0" + old).hexdigest() == blob,
        "OLD bytes do not match the pinned Git blob")
final = target.read_bytes()
mode = target.lstat().st_mode
require(stat.S_ISREG(mode) and stat.S_IMODE(mode) == 0o664, "final must be regular mode 0664")
require(target.lstat().st_nlink == 1, "production file must have exclusive link custody")
(journal / "final-production.bytes").write_bytes(final)
require((journal / "final-production.bytes").read_bytes() == final, "final backup mismatch")
before = protected()
interpreter = runtime()
save("before.json", before)
save("interpreter.json", interpreter)
save("production.json", {"oldRevision": revision, "oldBlob": blob, "gitMode": "100644",
                         "oldSha256": digest(old), "finalSha256": digest(final), "fullMode": oct(mode)})

try:
    check_interruption()
    target.write_bytes(old)
    target.chmod(stat.S_IMODE(mode))
    expected_old = json.loads(json.dumps(before))
    expected_old["source"][relative] = {"mode": mode, "sha256": digest(old)}
    old_code = leg("old", expected_old)
finally:
    restore("restored.json")

try:
    final_code = leg("final", before)
finally:
    restore("after-final.json")
check_interruption()

def manifests(name):
    prefix = "fixture-validator-inputs "
    return [json.loads(line[len(prefix):]) for line in (journal / f"{name}.stdout").read_text().splitlines()
            if line.startswith(prefix)]

old_inputs, final_inputs = manifests("old"), manifests("final")
require(old_inputs and old_inputs == final_inputs, "generated input-byte manifests differ or are missing")
require(old_code == 1 and final_code == 0, "expected assertion RED / final GREEN exits missing")
check_interruption()
print("Comparison recorded; causal assertion review and Root acceptance remain required.")
PY
```

Root reviews both logs and result records, not just exit codes. OLD must actually accept the
controlled bad summaries (`status: 0`) and fail their expected-rejection assertions; the
same final tests must reject those inputs for the intended token or timestamp reason and
pass all valid/type/date/SyntaxOnly controls. Expected OLD failures are confined to the raw
constant cases and the date-only/timezone-less instant cases. Direct-schema and provider
cases additionally demonstrate the other decoding routes. Missing manifests, unexpected
test errors, setup, decoding infrastructure, schema, registry, interpreter or timeout
failures are not semantic RED. Failed restoration is failure. Preserve failed or interrupted
journals truthfully; never report them as a passing comparison.
An interrupted child may leave test scratch behind. Use its allocation/cleanup receipts to
record the actual remaining state and disposition of those owned directories; a missing
cleanup receipt is not proof of removal. Do not delete unrelated temporary storage.

Ordinary writable Worker FINALIZE separately owns `git diff --check HEAD`,
`just test-fixture-validator`, `just validate-fixtures` and full `just check-docs`.
This comparison grants none of that credit. After whole-run release, Root separately owns
applicable `just release-status` validation and its complete independent review after the
last correction. HOST comparison and final acceptance remain pending until actually performed.
