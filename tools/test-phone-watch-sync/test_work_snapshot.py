"""Cheap inventory/metadata/protocol regressions; no Java, DEX or devices."""

import json
from pathlib import Path
import re
import sqlite3
import subprocess
import tempfile
import time
import unittest


OWNER = Path(__file__).resolve().parent
JAVA = (OWNER / 'WorkSnapshot.java').read_text()
SHELL = (OWNER / 'run.sh').read_text()
WORK_ID = '00000000-0000-0000-0000-000000000001'
OTHER_ID = '00000000-0000-0000-0000-000000000002'


def sql_expression(expression):
    return ''.join(json.loads(s) for s in re.findall(r'"(?:[^"\\]|\\.)*"', expression))


def java_sql(name):
    return sql_expression(re.search(r'\bString ' + name + r'\s*=\s*(.*?);', JAVA, re.S)[1])


def shell_function(name):
    return re.search(r'^' + name + r'\(\) \{\n.*?^\}', SHELL, re.M | re.S)[0]


BOOT_ID = '00000000-0000-0000-0000-000000000001'
OBSERVER_NAME = 'wardpulse-work-snapshot-7'
APP_ROW = '10123 41 app.wardpulse'
OBSERVER_ROW = f'10123 42 {OBSERVER_NAME}'


class InventoryTests(unittest.TestCase):
    def inventory(self, lists=None, starts=None, absence=None, released=1,
                  observer=True, boots=None, role='phone', header='UID PID NAME'):
        if lists is None:
            lists = [APP_ROW + '\n' + OBSERVER_ROW] * 4
        effects = {'ps': [header + '\n' + rows + '\n' for rows in lists],
                   'boot': boots or [BOOT_ID] * 2,
                   'start.41': ['100'] * 4, 'start.42': ['200'] * 4,
                   'absence': absence or ['absent'] * 4}
        effects.update(starts or {})
        with tempfile.TemporaryDirectory(prefix='work-inventory-', dir=OWNER) as scratch:
            for key, values in effects.items():
                for index, value in enumerate(values):
                    if key.startswith('start.') and value is not None:
                        value = '42 (process) ' + ' '.join(['S'] + ['0'] * 18 + [value])
                    Path(scratch, f'{key}.{index}').write_text(
                        '!error' if value is None else value)
            device = r'''
take() {
  local key=$1 index=0 value
  if [[ -f "$SCENARIO/$key.index" ]]; then read -r index <"$SCENARIO/$key.index"; fi
  printf '%s\n' "$((index + 1))" >"$SCENARIO/$key.index"
  value=$(command cat "$SCENARIO/$key.$index") || return 1
  [[ "$value" != '!error' ]] || return 1
  printf '%s\n' "$value"
}
ps() { take ps; }
cat() {
  if [[ "$*" == /proc/sys/kernel/random/boot_id ]]; then take boot
  else command cat "$@"; fi
}
awk() {
  local path=${!#} value pid
  if [[ "$path" == /proc/*/stat ]]; then
    pid=${path#/proc/}; pid=${pid%/stat}
    value=$(take "start.$pid") || return 1
    command awk "$1" <<<"$value"
  else command awk "$@"; fi
}
[() {
  if [[ "$#" == 4 && "$1" == '!' && "$2" == '-e' && "$3" == /proc/* ]]; then
    local state
    state=$(take absence) || return 2
    [[ "$state" == absent ]]
  else builtin [ "$@"; fi
}
'''
            script = r'''
set -euo pipefail
SCENARIO=$1 DEVICE=$2 ROLE=$3
declare -A UIDS=([phone]=10123 [wear]=10123)
declare -A BOOT=([phone]=$4 [wear]=$4)
OBSERVER=$5 OBSERVER_RELEASED=$6 OBSERVING=0
hold() { printf 'HOLD: %s\n' "$*" >&2; exit 1; }
adb_on() { bash -c "$DEVICE"$'\n'"$4"$'\n'"$5"; }
export SCENARIO
'''
            result = subprocess.run([
                'bash', '-c', script + shell_function('processes') + '\n'
                + shell_function('app_processes') + '\napp_processes device "$ROLE"\n',
                'work-inventory', scratch, device, role, BOOT_ID,
                f'42 200 {OBSERVER_NAME}' if observer else '', str(released),
            ], text=True, capture_output=True, timeout=5)
            return result

    def test_released_observer_disappears_before_start_lookup(self):
        result = self.inventory(lists=[APP_ROW + '\n' + OBSERVER_ROW] + [APP_ROW] * 3,
                                starts={'start.42': [None]})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '41 100 app.wardpulse')

    def assert_rejected(self, result):
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')
        self.assertIn('HOLD:', result.stderr)
        self.assertNotIn('No such file', result.stderr)

    def test_retirement_across_inventory_boundaries(self):
        for live_lists in range(5):
            with self.subTest(live_lists=live_lists):
                result = self.inventory(
                    lists=[APP_ROW + '\n' + OBSERVER_ROW] * live_lists
                    + [APP_ROW] * (4 - live_lists))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, '41 100 app.wardpulse')
        for failed_read in range(1, 4):
            with self.subTest(failed_read=failed_read):
                result = self.inventory(
                    lists=[APP_ROW + '\n' + OBSERVER_ROW] * (failed_read + 1)
                    + [APP_ROW] * (3 - failed_read),
                    starts={'start.42': ['200'] * failed_read + [None]})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, '41 100 app.wardpulse')
        result = self.inventory(lists=[''] * 4)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '')

    def test_pre_go_inventory_is_strict(self):
        result = self.inventory(released=0)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '41 100 app.wardpulse')
        self.assert_rejected(self.inventory(
            lists=[APP_ROW + '\n' + OBSERVER_ROW] + [APP_ROW] * 3,
            starts={'start.42': [None]}, released=0))
        self.assert_rejected(self.inventory(
            lists=[APP_ROW + '\n' + OBSERVER_ROW, APP_ROW] * 2, released=0))

    def test_retirement_requires_absence_and_stays_retired(self):
        self.assert_rejected(self.inventory(
            starts={'start.42': [None]}, absence=['present']))
        self.assert_rejected(self.inventory(lists=[APP_ROW] * 4, absence=['present']))
        self.assert_rejected(self.inventory(lists=[APP_ROW] * 4, absence=[None]))
        for lists, starts in [
                ([APP_ROW + '\n' + OBSERVER_ROW] * 4, {'start.42': [None]}),
                ([APP_ROW, APP_ROW + '\n' + OBSERVER_ROW] * 2, {}),
                ([APP_ROW + '\n' + OBSERVER_ROW, APP_ROW,
                  APP_ROW + '\n' + OBSERVER_ROW, APP_ROW], {})]:
            with self.subTest(lists=lists, starts=starts):
                self.assert_rejected(self.inventory(lists=lists, starts=starts))

    def test_live_observer_identity_must_match(self):
        for changed_read in range(4):
            with self.subTest(changed_read=changed_read):
                self.assert_rejected(self.inventory(
                    starts={'start.42': ['200'] * changed_read + ['201'] * (4 - changed_read)}))
        for row in ['10123 42 app.wardpulse', '10124 42 ' + OBSERVER_NAME,
                    '10123 43 ' + OBSERVER_NAME, '10123 42 wardpulse-work-snapshot-8']:
            with self.subTest(row=row):
                self.assert_rejected(self.inventory(
                    lists=[APP_ROW + '\n' + OBSERVER_ROW] * 3 + [APP_ROW + '\n' + row]))

    def test_every_other_process_remains_strict(self):
        self.assert_rejected(self.inventory(starts={'start.41': [None]}))
        self.assert_rejected(self.inventory(starts={'start.41': ['100', '101', '101', '101']}))
        for live_lists in range(1, 4):
            with self.subTest(live_lists=live_lists):
                self.assert_rejected(self.inventory(
                    lists=[APP_ROW + '\n' + OBSERVER_ROW] * live_lists
                    + [OBSERVER_ROW] * (4 - live_lists)))
        for role, observer in [('phone', False), ('wear', True)]:
            with self.subTest(role=role, observer=observer):
                self.assert_rejected(self.inventory(role=role, observer=observer))
        result = self.inventory(lists=[APP_ROW] * 4, observer=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '41 100 app.wardpulse')

    def test_malformed_and_oversized_inventory(self):
        rows = [APP_ROW + '\n' + APP_ROW, '10123 nope app.wardpulse',
                '10123 0 app.wardpulse', '10123 2147483648 app.wardpulse',
                '10123 41 unknown', '10123 41 app.wardpulse extra',
                '10123 41 app.wardpulse\r', '10123 41 app.wardpulse:' + 'a' * 128,
                '010123 41 app.wardpulse',
                '\n'.join(f'10123 {pid} app.wardpulse' for pid in range(1, 130)),
                '\n'.join(f'10123 {pid} app.wardpulse:' + 'a' * 110 for pid in range(1, 129))]
        for row in rows:
            with self.subTest(row=row[:80]):
                self.assert_rejected(self.inventory(lists=[row] * 4))
        for header in ['', 'UID PID', 'UID PID NAME EXTRA']:
            with self.subTest(header=header):
                self.assert_rejected(self.inventory(header=header))
        for start in ['', '0', '-1', '01', '200x', '18446744073709551616']:
            with self.subTest(start=start):
                self.assert_rejected(self.inventory(starts={'start.42': [start]}))

    def test_boot_continuity_and_expected_boot(self):
        other_boot = '00000000-0000-0000-0000-000000000002'
        for boots in [[BOOT_ID, other_boot], [other_boot] * 2, ['unknown'] * 2]:
            with self.subTest(boots=boots):
                self.assert_rejected(self.inventory(boots=boots))

    def test_start_ticks_require_one_record(self):
        extra_stat = '41 (process) ' + ' '.join(['S'] + ['0'] * 18 + ['100'])
        self.assert_rejected(self.inventory(
            starts={'start.41': ['100\n' + extra_stat] * 4}))


class ReaderLifecycleTests(unittest.TestCase):
    def capture(self, mode='complete'):
        with tempfile.TemporaryDirectory(prefix='work-reader-', dir=OWNER) as scratch:
            Path(scratch, 'evidence').write_text(evidence())
            adb = Path(scratch, 'adb')
            adb.write_text('''#!/bin/bash
set -eu
printf 'READER 42 200\\n'
IFS= read -r go
[[ "$go" == GO ]] || exit 1
printf 'go-received\\n' >>"$SCENARIO/trace"
cat "$SCENARIO/evidence"
if [[ "$MODE" != missing-end ]]; then printf 'END 42 200\\n'; fi
if [[ "$MODE" == failed-exit ]]; then exit 5; fi
''')
            adb.chmod(0o700)
            device = r'''
ps() {
  printf 'UID PID NAME\n'
  if [[ -n "$observer" && "$released" == 0 ]]; then
    local pid ticks name
    read -r pid ticks name <<<"$observer"
    printf '%s %s %s\n' "$uid" "$pid" "$name"
  fi
}
awk() {
  if [[ "${!#}" == /proc/42/stat ]]; then
    if [[ "$MODE" == changed-start ]]; then printf '201\n'; else printf '200\n'; fi
  else command awk "$@"; fi
}
cat() {
  if [[ "$*" == /proc/sys/kernel/random/boot_id ]]; then printf '%s\n' "$EXPECTED_BOOT"
  else command cat "$@"; fi
}
[() {
  if [[ "$#" == 4 && "$1" == '!' && "$2" == '-e' && "$3" == /proc/42 ]]; then return 0
  else builtin [ "$@"; fi
}
'''
            script = r'''
set -euo pipefail
SCRATCH=$1 SCENARIO=$1 ADB=$1/adb MODE=$2 DEVICE=$3 EXPECTED_BOOT=$4 DEVICE_SCRATCH=$1/device
export SCENARIO MODE EXPECTED_BOOT
unset SECONDS
SECONDS=10
PHONE_SERIAL=phone WEAR_SERIAL=wear
declare -A UIDS=([phone]=10123 [wear]=10124)
declare -A BOOT=([phone]=$4 [wear]=$4)
RETAINING=1 RETENTION_DEADLINE=70 LAST_OBSERVATION=10 PRE_DEATH_DEADLINE=0
BASELINE=hash BASELINE_METADATA=stat OBSERVER= OBSERVER_RELEASED=0 EVENTS=
OBSERVING=0
READER_HOST= READER_DIAG_HOST= READER_DEVICE_PID= READER_STAGE_ACTIVE=0
READER_INPUT_FD= READER_OUTPUT_FD= READER_STDERR_FD= READER_STDERR_DRAIN_FD=
READER_DIAG_OUTPUT_FAILED=0 PHONE_ACTIVITY=0
hold() { printf 'HOLD: %s\n' "$*" >&2; exit 1; }
barrier() { EVENTS=; }
installed_apk() { printf 'apk'; }
reader_diagnostic() { printf "$@" >>"$SCRATCH/trace"; }
reader_stderr() { :; }
reader_stderr_collect() { cat >/dev/null; }
summary_hash() {
  printf '%s released=%s\n' "$phase" "$OBSERVER_RELEASED" >>"$SCRATCH/trace"
  printf hash
}
summary_metadata() { printf stat; }
adb_on() {
  if [[ "$#" == 5 ]]; then bash -c "$DEVICE"$'\n'"$4"$'\n'"$5"
  else [[ "$MODE" != unproved-retirement ]]; fi
}
reconcile_work() { printf 'accepted\n' >>"$SCRATCH/trace"; }
native_jobs() { : >"$SCRATCH/native.current"; }
finish() {
  local status=$? descriptor
  if [[ -n "$READER_INPUT_FD" ]]; then exec {READER_INPUT_FD}>&-; fi
  if [[ -n "$READER_OUTPUT_FD" ]]; then exec {READER_OUTPUT_FD}<&-; fi
  if [[ -n "$READER_STDERR_FD" ]]; then exec {READER_STDERR_FD}>&-; fi
  if [[ -n "$READER_STDERR_DRAIN_FD" ]]; then exec {READER_STDERR_DRAIN_FD}<&-; fi
  descriptor=${WORK_READER[1]:-}
  if [[ -n "$descriptor" ]]; then exec {descriptor}>&-; fi
  descriptor=${WORK_READER[0]:-}
  if [[ -n "$descriptor" ]]; then exec {descriptor}<&-; fi
  if [[ -n "$READER_HOST" ]]; then wait "$READER_HOST" || :; fi
  if [[ -n "$READER_DIAG_HOST" ]]; then wait "$READER_DIAG_HOST" || :; fi
  exit "$status"
}
trap finish EXIT
'''
            script += '\n'.join(shell_function(name) for name in
                                ['processes', 'app_processes', 'check_separation', 'work_snapshot'])
            script += '\nwork_snapshot sample\n'
            result = subprocess.run(['bash', '-c', script, 'work-reader', scratch, mode, device, BOOT_ID],
                                    text=True, capture_output=True, timeout=5)
            return result, Path(scratch, 'trace').read_text()

    def test_complete_reader_retirement_and_released_separation(self):
        result, trace = self.capture()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('sample-before-reader released=0\n', trace)
        self.assertIn('sample-reader-released released=1\n', trace)
        self.assertIn('sample-reader-retired released=0\n', trace)
        self.assertIn('accepted\n', trace)
        self.assertIn('Bounded logical/native work reconciled: sample', result.stdout)

    def test_pre_go_identity_failure_retires_fixture_children(self):
        result, trace = self.capture('changed-start')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Cannot identify the actual reader process.', result.stderr)
        self.assertNotIn('go-received\n', trace)
        self.assertNotIn('sample-reader-released', trace)
        self.assertNotIn('accepted\n', trace)

    def test_retirement_tolerance_cannot_accept_incomplete_reader(self):
        cases = [('missing-end', 'Partial reader evidence.'),
                 ('failed-exit', 'Reader process failed or did not retire normally.'),
                 ('unproved-retirement', 'Reader PID is still live or reused.')]
        for mode, reason in cases:
            with self.subTest(mode=mode):
                result, trace = self.capture(mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(reason, result.stderr)
                self.assertIn('sample-reader-released released=1\n', trace)
                self.assertNotIn('sample-reader-retired', trace)
                self.assertNotIn('accepted\n', trace)
                self.assertNotIn('Bounded logical/native work reconciled:', result.stdout)


class MappingQueryTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(':memory:')
        self.addCleanup(self.db.close)
        # No affinity/constraints: malformed stored values must be rejected too.
        self.db.executescript('''
            CREATE TABLE WorkSpec(id, generation);
            CREATE TABLE WorkName(name, work_spec_id);
            CREATE TABLE SystemIdInfo(work_spec_id, generation, system_id);
        ''')
        self.db.execute('INSERT INTO WorkSpec VALUES (?, ?)', (WORK_ID, 2))

    def mapping(self, generation=2, job=7, work_id=WORK_ID):
        self.db.execute('INSERT INTO SystemIdInfo VALUES (?, ?, ?)',
                        (work_id, generation, job))

    def counts(self):
        self.assertEqual(self.db.execute(java_sql('MAPPING_INVALID_SQL')).fetchone(), (0,))
        return self.db.execute(java_sql('MAPPING_COUNTS_SQL')).fetchone()

    def test_older_mapping_keeps_work_id(self):
        self.mapping(generation=1)
        # Execute the production orphan assertion, including on the unfixed reader.
        expression = re.search(
            r'require\(scalar\(db,\s*(.*?)\)\s*\.equals\("0"\), "ORPHAN_SYSTEM_ID"\)',
            JAVA, re.S)[1].rsplit('require(scalar(db,', 1)[-1]
        self.assertEqual(self.db.execute(sql_expression(expression)).fetchone(), (0,))

    def test_mapping_classification(self):
        cases = [
            ([], (0, 0, 0, 0, 0)),
            ([(WORK_ID, 2, 7)], (1, 0, 1, 0, 0)),
            ([(WORK_ID, 1, 7)], (1, 0, 0, 1, 0)),
            ([(WORK_ID, 1, 7), (WORK_ID, 2, 8)], (2, 0, 1, 1, 0)),
            ([(OTHER_ID, 0, 7)], (1, 1, 0, 0, 0)),
            ([(WORK_ID, 3, 7)], (1, 0, 0, 0, 1)),
            ([(WORK_ID, 1, 7), (OTHER_ID, 0, 8), (WORK_ID, 3, 9)], (3, 1, 0, 1, 1)),
        ]
        for mappings, expected in cases:
            with self.subTest(mappings=mappings):
                self.db.execute('DELETE FROM SystemIdInfo')
                self.db.executemany('INSERT INTO SystemIdInfo VALUES (?, ?, ?)', mappings)
                self.assertEqual(self.counts(), expected)
        self.db.execute('DELETE FROM SystemIdInfo')
        self.db.execute('UPDATE WorkSpec SET generation=2147483647')
        self.mapping(generation=2147483647, job=2147483647)
        self.assertEqual(self.counts(), (1, 0, 1, 0, 0))

    def test_invalid_and_ambiguous_metadata(self):
        invalid = [None, -1, 2147483648, 9223372036854775807, 1.5, '1', b'1']
        cases = [(WORK_ID, v, 7) for v in invalid]
        cases += [(WORK_ID, 1, v) for v in invalid]
        cases += [(v, 1, 7) for v in (None, 1, b'id', '', 'unknown',
                                    '00000000-0000-0000-0000-00000000000A', WORK_ID + '\0extra')]
        for row in cases:
            with self.subTest(row=row):
                self.db.execute('DELETE FROM SystemIdInfo')
                # A valid current row must never hide invalid older/unmatched data.
                self.mapping(job=8)
                self.db.execute('INSERT INTO SystemIdInfo VALUES (?, ?, ?)', row)
                self.assertNotEqual(self.db.execute(java_sql('MAPPING_INVALID_SQL')).fetchone(), (0,))
        for rows in (
                [(WORK_ID, 1, 7), (WORK_ID, 1, 8)],
                [(WORK_ID, 1, 7), (WORK_ID, 2, 7)],
                [(WORK_ID, 1, 7), (OTHER_ID, 0, 7)]):
            with self.subTest(rows=rows):
                self.db.execute('DELETE FROM SystemIdInfo')
                self.db.executemany('INSERT INTO SystemIdInfo VALUES (?, ?, ?)', rows)
                self.assertNotEqual(self.db.execute(java_sql('MAPPING_INVALID_SQL')).fetchone(), (0,))
        self.db.execute('DELETE FROM SystemIdInfo')
        self.mapping(generation=0)
        for generation in invalid:
            with self.subTest(work_generation=generation):
                self.db.execute('UPDATE WorkSpec SET generation=?', (generation,))
                self.assertNotEqual(self.db.execute(java_sql('MAPPING_INVALID_SQL')).fetchone(), (0,))
        self.db.execute('UPDATE WorkSpec SET generation=2')
        self.db.execute('INSERT INTO WorkSpec VALUES (?, 2)', (WORK_ID,))
        self.assertNotEqual(self.db.execute(java_sql('MAPPING_INVALID_SQL')).fetchone(), (0,))

    def test_projection_selects_only_current_job(self):
        # Add only the fixed projection's remaining metadata, without payloads.
        columns = set(re.findall(r'\bw\.([a-z_]+)', java_sql('sql'))) - {'id', 'generation'}
        for name in sorted(columns):
            self.db.execute('ALTER TABLE WorkSpec ADD COLUMN ' + name)
        self.db.execute('INSERT INTO WorkName VALUES (?, ?)', ('wardpulse.providerSync', WORK_ID))
        self.mapping(generation=1)
        self.assertIsNone(self.db.execute(java_sql('sql')).fetchone()[13])
        self.mapping(generation=2, job=8)
        rows = self.db.execute(java_sql('sql')).fetchall()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0][12:14], (2, 8))


def work_record(job=8, generation=2, state=0, name='wardpulse.providerSync', work_id=WORK_ID):
    fields = ['WORK', name, work_id, str(state), 'dev.fluttercommunity.workmanager.BackgroundWorker',
              '900000', '300000', '0', '1', '0', '0', '0', '0', str(generation), str(job),
              '1700000000000', '1700000000000', '0', '0', '0', '30000',
              '9223372036854775807', '0', '-256', '-1']
    return ' '.join(fields)


def evidence(counts='MAPPINGS 1 0 1 0 0', work=None):
    return '\n'.join([
        'SCHEMA 2.11.2 24 08b926448d86528e697981ddd30459f7 no_backup',
        'SQLITE 3.44.3 2024-01-01 00:00:00 ' + 'a' * 64 + ' wal',
        'TIME 1700000001000', counts, work_record() if work is None else work,
    ]) + '\n'


class ConsumerTests(unittest.TestCase):
    def consume(self, current, previous='', rejected='', activity=0):
        with tempfile.TemporaryDirectory(prefix='work-metadata-', dir=OWNER) as scratch:
            Path(scratch, 'work.previous').write_text(previous)
            Path(scratch, 'work.current').write_text(current)
            return subprocess.run([
                'bash', '-c', 'set -euo pipefail\nSCRATCH=$1\nPHONE_ACTIVITY=$2\nWORK_ACTIVITY=0\n'
                'hold() { printf "HOLD: %s\\n" "$*" >&2; exit 1; }\n'
                + shell_function('reconcile_work') + '\nreconcile_work sample "$3"\n',
                'work-metadata', scratch, str(activity), rejected,
            ], text=True, capture_output=True, timeout=5)

    def test_accepts_counts_and_preserves_transitions(self):
        for counts, work in [
                ('MAPPINGS 1 0 1 0 0', work_record()),
                ('MAPPINGS 2 0 1 1 0', work_record()),
                ('MAPPINGS 1 0 0 1 0', work_record(job=-1, state=1))]:
            with self.subTest(counts=counts):
                result = self.consume(evidence(counts, work))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, '')
        previous = evidence()
        changed = evidence(work=work_record(generation=3))
        self.assertNotEqual(self.consume(changed, previous).returncode, 0)
        self.assertEqual(self.consume(changed, previous, activity=1).returncode, 0)
        unknown = evidence(work=work_record(name='unknown'))
        self.assertNotEqual(self.consume(unknown).returncode, 0)

    def test_closed_count_protocol(self):
        base = evidence()
        cases = [base.replace('MAPPINGS 1 0 1 0 0\n', ''),
                 base.replace('MAPPINGS 1 0 1 0 0', 'MAPPINGS 1 0 1 0 0\nMAPPINGS 1 0 1 0 0'),
                 base + 'UNKNOWN 0\n',
                 base.replace('TIME 1700000001000\nMAPPINGS 1 0 1 0 0',
                              'MAPPINGS 1 0 1 0 0\nTIME 1700000001000')]
        for counts in ['MAPPINGS 1 0 0 0 0', 'MAPPINGS 1 0 0 1 0', 'MAPPINGS 0 0 0 0 0',
                       'MAPPINGS 1 1 0 0 0', 'MAPPINGS 1 0 0 0 1', 'MAPPINGS 1 0 1 0',
                       'MAPPINGS 1 0 1 0 0 0', 'MAPPINGS -1 0 1 0 0', 'MAPPINGS 1 0 1.0 0 0',
                       'MAPPINGS 1 0 1e0 0 0', 'MAPPINGS 01 0 1 0 0',
                       'MAPPINGS 2147483648 0 1 2147483647 0',
                       'MAPPINGS 999999999999999999999999 0 1 0 0',
                       'MAPPINGS 1 0 1 9223372036854775808 0']:
            cases.append(base.replace('MAPPINGS 1 0 1 0 0', counts))
        for current in cases:
            with self.subTest(current=current):
                result = self.consume(current)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, '')

    def test_count_only_rejections(self):
        for counts, category in [('MAPPINGS 1 1 0 0 0', 'ORPHAN_SYSTEM_ID'),
                                 ('MAPPINGS 2 0 1 0 1', 'FUTURE_SYSTEM_ID'),
                                 ('MAPPINGS 3 1 0 1 1', 'ORPHAN_SYSTEM_ID')]:
            with self.subTest(category=category):
                result = self.consume(counts + '\n', rejected=category)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, '')
                self.assertIn('Rejected mapping evidence: ' + counts, result.stderr)
        for counts, category in [('MAPPINGS 1 0 1 0 0', 'ORPHAN_SYSTEM_ID'),
                                 ('MAPPINGS 1 1 0 0 0', 'FUTURE_SYSTEM_ID'),
                                 ('MAPPINGS 1 0 0 0 1', 'UNKNOWN'),
                                 ('MAPPINGS 1 0 0 1 0', 'ORPHAN_SYSTEM_ID'),
                                 ('MAPPINGS 1 0 0 0 1\nUNKNOWN 0', 'FUTURE_SYSTEM_ID'),
                                 ('MAPPINGS 1 0 0 0 1\nMAPPINGS 1 0 0 0 1', 'FUTURE_SYSTEM_ID')]:
            with self.subTest(category=category, counts=counts):
                result = self.consume(counts + '\n', rejected=category)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('Rejected mapping evidence:', result.stderr)


if __name__ == '__main__':
    started = time.monotonic()
    try:
        unittest.main()
    finally:
        print(f'Inventory/metadata/protocol regression elapsed: {time.monotonic() - started:.3f}s')
