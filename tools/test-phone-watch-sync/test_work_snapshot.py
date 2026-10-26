"""Cheap metadata/protocol regressions; these do not run Java, DEX or devices."""

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
        print(f'Metadata/protocol regression elapsed: {time.monotonic() - started:.3f}s')
