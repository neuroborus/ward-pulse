"""Inert controlled regressions: no canonical Source writes, SDK, JVM or replay."""

import copy
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

import replay_original19 as replay


def widget(b_only=False):
    value = {f'row_{row}_{field}': '' for row in range(6) for field in replay.ROW_FIELDS}
    value.update(stale='0', empty='0', row_count=1 if b_only else 2)
    if not b_only:
        value.update(row_0_kind='allowance', row_0_family='Cursor', row_0_percent='80% left',
                     row_0_label='Cursor · Plan usage')
    row = 0 if b_only else 1
    value.update({f'row_{row}_kind': 'budget', f'row_{row}_family': 'OpenAI',
                  f'row_{row}_spent_minor': '900', f'row_{row}_spent_currency': 'USD'})
    return value


def oracle(old=False):
    b = {'id': 'openai-local', 'connection': 'openai.platform', 'status': 'ok',
         'spent': 900, 'allowances': []}
    a = {'id': 'cursor-local', 'connection': 'cursor.plan', 'status': 'ok', 'spent': None,
         'allowances': [{'id': 'cursor-plan', 'usedPercent': 20}]}
    publications = [widget()] + ([widget(True)] if old else [])
    return {'oldAccounts': [b], 'acceptedAccounts': [copy.deepcopy(b), a],
            'lateOutcome': 'completed', 'lateCurrent': old, 'latePublished': old,
            'completedAbsentReads': 1, 'publications': publications,
            'redraws': copy.deepcopy(publications), 'visible': copy.deepcopy(publications[-1])}


def event(kind, **fields):
    return json.dumps({'type': kind, 'time': 0, **fields}) + '\n'


def transcript(old=False, evidence=None, error=None):
    result = event('start', protocolVersion='0.1.1', runnerVersion=None)
    result += event('suite', suite={'id': 0, 'platform': 'vm', 'path': None})
    result += event('testStart', test={'id': 1, 'name': '(setUpAll)', 'line': None,
                                    'column': None, 'url': None})
    result += event('testDone', testID=1, result='success', hidden=True, skipped=False)
    result += event('testStart', test={'id': 2, 'name': replay.CASE, 'line': None,
                                    'column': None, 'url': None})
    # Repeated reporter types are ordinary protocol traffic, not duplicate causality.
    result += event('print', testID=2, message='synthetic progress', messageType='print') * 2
    result += replay.TAG + json.dumps(oracle(old) if evidence is None else evidence,
                                     ensure_ascii=False) + '\n'
    if old or error:
        result += event('error', testID=2, error=error or replay.ASSERTION,
                        isFailure=True, stackTrace='private synthetic stack')
    result += event('testDone', testID=2, result='failure' if old or error else 'success',
                    hidden=False, skipped=False)
    result += event('testStart', test={'id': 3, 'name': '(tearDownAll)', 'line': None,
                                    'column': None, 'url': None})
    result += event('testDone', testID=3, result='success', hidden=True, skipped=False)
    result += event('done', success=not (old or bool(error)))
    return result.encode()


def reporter(data):
    result = replay.Reporter()
    result.feed(data)
    result.feed(b'', final=True)
    return result


class ParserTests(unittest.TestCase):
    def test_real_account_shape_nulls_repeated_events_and_split_utf8(self):
        data = transcript().replace(b'synthetic progress', 'synthetic \u03bb'.encode())
        result = replay.Reporter()
        for byte in data:
            result.feed(bytes([byte]))
        result.feed(b'', final=True)
        proof = result.classify(0)
        self.assertEqual(proof['classification'], 'FINAL0')
        self.assertIsNone(proof['acceptedAccounts'][1]['spent'])
        self.assertEqual(proof['acceptedAccounts'][0]['spent'], 900)
        nullable = oracle()
        nullable['acceptedAccounts'][1]['allowances'].append(
            {'id': 'cursor-on-demand', 'usedPercent': None})
        self.assertIsNone(replay.validate_oracle(nullable)['acceptedAccounts'][1]
                          ['allowances'][1]['usedPercent'])

    def test_semantic_010_requires_the_named_late_publication_assertion(self):
        self.assertEqual(reporter(transcript(True)).classify(1, True)['classification'],
                         'OLD-named-semantic1')
        for exit_code, error in ((0, None), (2, None), (1, 'Unrelated early assertion')):
            with self.subTest(exit_code=exit_code, error=error), self.assertRaises(replay.Hold):
                reporter(transcript(True, error=error)).classify(exit_code, True)
        for change in ('lateOutcome', 'completedAbsentReads', 'redraws', 'oldAccounts'):
            evidence = oracle(True)
            evidence[change] = {'lateOutcome': 'error', 'completedAbsentReads': 0,
                                'redraws': [widget()], 'oldAccounts': []}[change]
            with self.subTest(change=change), self.assertRaises(replay.Hold):
                reporter(transcript(True, evidence)).classify(1, True)

    def test_unicode_widget_labels_are_accepted_without_retaining_free_text(self):
        for old in (False, True):
            with self.subTest(old=old):
                proof = reporter(transcript(old)).classify(1 if old else 0, old)
                self.assertEqual(proof['publications'][0]['payloadSha256'],
                                 replay.digest(replay.encoded(widget())))
                self.assertNotIn('Cursor · Plan usage', json.dumps(proof, ensure_ascii=False))
        for label in ('unsafe\nlabel', '\x7f', '\ud800', 'x' * 161):
            value = widget()
            value['row_0_label'] = label
            with self.subTest(label=repr(label)), self.assertRaises(replay.Hold):
                replay.payload(value)

    def test_wrong_row_kinds_currency_and_incidental_assertion_text_do_not_qualify(self):
        for key, bad in (('row_0_kind', 'budget'), ('row_1_kind', 'allowance'),
                         ('row_1_spent_currency', '')):
            evidence = oracle(True)
            for item in evidence['publications'][:1] + evidence['redraws'][:1]:
                item[key] = bad
            with self.subTest(key=key), self.assertRaises(replay.Hold):
                reporter(transcript(True, evidence)).classify(1, True)
        with self.assertRaises(replay.Hold):
            reporter(transcript(True, error='Unrelated failure mentioning ' + replay.ASSERTION)).classify(1, True)

    def test_malformed_duplicate_keys_nonfinite_depth_and_types(self):
        for data in (b'{', b'{"x":1,"x":2}', b'{"x":NaN}', b'{"x":1e999}',
                     b'[' * 25 + b'0' + b']' * 25, b'"\\ud800"', b'\xff'):
            with self.subTest(data=data), self.assertRaises(replay.Hold):
                replay.strict_json(data)
        for key, bad in (('completedAbsentReads', True), ('lateCurrent', 1),
                         ('acceptedAccounts', ['openai-local', 'cursor-local'])):
            value = oracle()
            value[key] = bad
            with self.subTest(key=key), self.assertRaises(replay.Hold):
                reporter(transcript(evidence=value))

    def test_duplicate_or_unassociated_oracle_and_incomplete_reporter(self):
        data = transcript()
        line = replay.TAG.encode() + json.dumps(oracle(), ensure_ascii=False).encode() + b'\n'
        with self.assertRaises(replay.Hold):
            reporter(data.replace(line, line + line))
        with self.assertRaises(replay.Hold):
            reporter(line + data)
        duplicate = event('print', testID=2, message=replay.TAG + json.dumps(oracle())).encode()
        with self.assertRaises(replay.Hold):
            reporter(data.replace(line, line + duplicate))
        with self.assertRaises(replay.Hold):
            reporter(data[:data.rfind(b'{"type": "done"')]).classify(0)
        with self.assertRaises(replay.Hold):
            reporter(data.rstrip(b'\n'))

    def test_bounds_and_raw_utf8_failure(self):
        for block in (b'x' * (replay.MAX_LINE + 1), b'\xff\n', b'{}\n' * 400):
            result = replay.Reporter()
            with self.subTest(size=len(block)), self.assertRaises(replay.Hold):
                if block.startswith(b'{}'):
                    with patch.object(replay, 'MAX_STREAM', 100):
                        result.feed(block)
                else:
                    result.feed(block)

    def test_unrelated_errors_and_errors_before_the_oracle_never_qualify(self):
        data = transcript(True)
        failure = event('error', testID=2, error=replay.ASSERTION,
                        isFailure=True, stackTrace=None).encode()
        without_error = transcript(True).splitlines(keepends=True)
        without_error = b''.join(line for line in without_error if b'"type": "error"' not in line)
        with self.assertRaises(replay.Hold):
            reporter(without_error.replace(replay.TAG.encode(), failure + replay.TAG.encode())).classify(1, True)
        with self.assertRaises(replay.Hold):
            reporter(data.replace(b'"isFailure": true', b'"isFailure": false')).classify(1, True)

    def test_failed_output_never_escapes_into_retained_projections(self):
        marker = 'synthetic-private-report'
        result = reporter(transcript(True, error=marker))
        with self.assertRaises(replay.Hold) as raised:
            result.classify(1, True)
        self.assertNotIn(marker, str(raised.exception))
        self.assertNotIn(marker, repr(result.errors))
        evidence = oracle()
        for item in evidence['publications'] + evidence['redraws'] + [evidence['visible']]:
            item['row_0_label'] = marker
        proof = reporter(transcript(evidence=evidence)).classify(0)
        self.assertNotIn(marker, json.dumps(proof))
        self.assertNotIn('private synthetic stack', json.dumps(proof))


class InertFiles(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='original19-controlled-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        # Fixture subdirectories must not change the sealed journal parent's identity.
        evidence = self.root / 'evidence'
        evidence.mkdir(mode=0o700)
        self.journal = replay.Journal(evidence)
        self.addCleanup(self.journal.close)
        self.custody = replay.Custody(self.root / 'index.lock', self.journal, lambda: None)
        self.addCleanup(self.custody.close_handles)
        self.original = []
        for index in range(3):
            path = self.root / f'owner-{index}'
            path.write_bytes(b'final-' + bytes([48 + index]))
            path.chmod(0o640 | (0o100 if index == 1 else 0))
            self.original.append((path.read_bytes(), stat.S_IMODE(path.stat().st_mode),
                                  replay.identity(path.stat())))

    def acquire(self):
        self.custody.acquire()
        for index in range(3):
            self.custody.files.append(replay.StableFile(self.root / f'owner-{index}'))

    def arm(self):
        self.custody.prepare(self.custody.files, [
            {'path': f'owner-{i}', 'sha256': replay.digest(data), 'mode': mode}
            for i, (data, mode, _) in enumerate(self.original)])

    def assert_restored(self):
        for index, (data, mode, identity) in enumerate(self.original):
            path = self.root / f'owner-{index}'
            self.assertEqual((path.read_bytes(), stat.S_IMODE(path.stat().st_mode),
                              replay.identity(path.stat())), (data, mode, identity))


class CustodyTests(InertFiles):

    def test_failure_before_substitution_does_not_write_source(self):
        self.acquire()
        self.arm()
        with patch.object(replay.StableFile, 'replace', side_effect=AssertionError('source write')):
            self.custody.restore()
            self.custody.release()
        self.assert_restored()
        self.assertFalse((self.root / 'index.lock').exists())

    def test_failed_arming_never_permits_a_write(self):
        self.acquire()
        with patch.object(self.journal, 'sync', side_effect=OSError('inert disk fault')):
            with self.assertRaises(OSError):
                self.arm()
        self.assertFalse(self.custody.armed)
        self.assertTrue(self.journal.failed)
        with self.assertRaises(replay.Hold):
            self.custody.substitute([(b'old', 0o644)] * 3)
        self.assertFalse(self.custody.attempted)
        self.assert_restored()

    def test_first_and_later_partial_writes_restore_exact_bytes_modes_and_identity(self):
        self.acquire()
        self.arm()
        for failing_call in (1, 3):
            calls = []
            def write(fd, data, offset):
                calls.append(fd)
                journal = self.journal.path.read_bytes()
                self.assertIn(b'"event":"restoration-armed"', journal)
                self.assertIn(b'"event":"substitution-may-have-begun"', journal)
                # A real prefix write followed by failure on the first or later owner.
                if len(calls) == failing_call:
                    os.pwrite(fd, data[:1], offset)
                    raise OSError('inert partial write')
                return os.pwrite(fd, data, offset)
            with self.subTest(failing_call=failing_call), self.assertRaises(OSError):
                self.custody.substitute([(b'OLD-LONGER', 0o600)] * 3, write)
            self.assertTrue(self.custody.attempted)
            self.custody.restore()
            self.assert_restored()
        self.custody.release()

    def test_foreign_lock_is_untouched(self):
        path = self.root / 'index.lock'
        path.write_bytes(b'foreign')
        before = replay.file_seal(path)
        with self.assertRaisesRegex(replay.Hold, 'foreign-index-lock'):
            self.custody.acquire()
        self.assertEqual(replay.file_seal(path), before)
        self.assertEqual(self.custody.evidence(), {
            'custodyHeld': False, 'lockDisposition': 'foreign', 'lockIdentity': None})

    def test_interrupted_creation_before_descriptor_retention_reports_unknown(self):
        opened = []
        original_open = os.open
        def interrupted(path, flags, *args, **kwargs):
            if Path(path) == self.custody.path:
                self.assertIn(b'"event":"lock-acquisition-pending"',
                              self.journal.path.read_bytes())
                opened.append(original_open(path, flags, *args, **kwargs))
                raise KeyboardInterrupt
            return original_open(path, flags, *args, **kwargs)
        self.addCleanup(lambda: [os.close(fd) for fd in opened])
        with patch.object(replay.os, 'open', side_effect=interrupted):
            with self.assertRaises(KeyboardInterrupt):
                self.custody.acquire()
        self.assertIsNone(self.custody.fd)
        self.assertIsNone(self.custody.owner)
        before = replay.file_seal(self.custody.path)
        evidence = self.custody.evidence()
        self.assertEqual(evidence, {
            'custodyHeld': 'unknown', 'lockDisposition': 'unknown', 'lockIdentity': None})
        self.journal.append('custody-disposition', recovery=True, **evidence)
        replay.persist(self.root / 'result.json', evidence)
        self.assertEqual(json.loads((self.root / 'result.json').read_bytes()), evidence)
        with patch.object(replay.StableFile, 'replace', side_effect=AssertionError('source write')):
            self.custody.restore()
            with self.assertRaisesRegex(replay.Hold, 'lock-replaced'):
                self.custody.release()
        self.custody.close_handles()
        self.assertEqual(replay.file_seal(self.custody.path), before)
        self.assert_restored()

    def test_retained_descriptor_without_owner_is_unknown_and_owned_lock_is_positive(self):
        original_fstat = os.fstat
        def interrupted(fd):
            if fd == self.custody.fd:
                raise KeyboardInterrupt
            return original_fstat(fd)
        with patch.object(replay.os, 'fstat', side_effect=interrupted):
            with self.assertRaises(KeyboardInterrupt):
                self.custody.acquire()
        self.assertIsNotNone(self.custody.fd)
        self.assertEqual(self.custody.evidence()['custodyHeld'], 'unknown')
        self.assert_restored()
        # A separate, fully acquired lock supplies positive ownership evidence.
        other = replay.Custody(self.root / 'other.lock', self.journal, lambda: None)
        self.addCleanup(other.close_handles)
        other.acquire()
        self.assertEqual(other.evidence(), {
            'custodyHeld': True, 'lockDisposition': 'owned',
            'lockIdentity': list(replay.identity(other.owner))})
        other.release()

    def test_release_sync_failure_preserves_the_known_unlink_disposition(self):
        self.acquire()
        self.arm()
        with patch.object(replay, 'fsync_directory', side_effect=OSError('inert directory sync')):
            with self.assertRaises(OSError):
                self.custody.release()
        self.assertTrue(self.custody.unlinked)
        self.assertEqual(self.custody.evidence()['lockDisposition'], 'released')
        self.assertIs(self.custody.evidence()['custodyHeld'], False)
        self.assertFalse(self.custody.path.exists())
        self.assert_restored()

    def test_replaced_lock_and_source_are_never_adopted(self):
        self.acquire()
        self.arm()
        lock = self.root / 'index.lock'
        lock.rename(self.root / 'owned-lock')
        lock.write_bytes(b'foreign')
        with self.assertRaises(replay.Hold):
            self.custody.release()
        self.assertEqual(self.custody.evidence()['custodyHeld'], 'unknown')
        self.assertEqual(lock.read_bytes(), b'foreign')
        path = self.root / 'owner-0'
        path.rename(self.root / 'original-owner')
        path.write_bytes(b'foreign owner')
        with self.assertRaises(replay.Hold):
            self.custody.files[0].replace(b'old', 0o644)
        self.assertEqual(path.read_bytes(), b'foreign owner')

    def test_surviving_readers_block_substitution_and_failure_restoration(self):
        self.acquire()
        self.arm()
        self.custody.substitute([(b'old', 0o600)] * 3)
        self.custody.readers_retired = lambda: replay.need(False, 'owned-readers-live')
        with self.assertRaises(replay.Hold):
            self.custody.restore()
        self.assertEqual((self.root / 'owner-0').read_bytes(), b'old')
        self.assertTrue((self.root / 'index.lock').exists())
        self.custody.readers_retired = lambda: None
        self.custody.restore()
        self.assert_restored()
        self.custody.release()

    def test_journal_failure_after_partial_substitution_restores_but_retains_lock(self):
        self.acquire()
        self.arm()
        self.custody.substitute([(b'old', 0o600)] * 3)
        self.journal.write = lambda *_: (_ for _ in ()).throw(OSError('inert journal fault'))
        with self.assertRaises(replay.Hold):
            self.custody.restore()
        self.assert_restored()
        with self.assertRaises(replay.Hold):
            self.custody.release()
        self.assertTrue((self.root / 'index.lock').exists())

    def test_restoration_verification_failure_retains_custody(self):
        self.acquire()
        self.arm()
        self.custody.substitute([(b'old', 0o600)] * 3)
        with patch.object(self.custody.files[0], 'replace', return_value=None):
            with self.assertRaises(replay.Hold):
                self.custody.restore()
        self.assertTrue(self.custody.attempted)
        self.custody.restore()
        self.custody.release()

    def test_bounded_journal_has_reserved_durable_restoration_slots(self):
        for _ in range(replay.JOURNAL_SLOTS - replay.RESTORATION_SLOTS):
            self.journal.append('controlled')
        with self.assertRaises(replay.Hold):
            self.journal.append('normal-overflow')
        self.journal.append('restoration-verified', recovery=True)
        self.assertEqual(self.journal.path.stat().st_size, replay.JOURNAL_SLOT * replay.JOURNAL_SLOTS)
        with self.assertRaises(replay.Hold):
            self.journal.append('oversized', recovery=True, value='x' * replay.JOURNAL_SLOT)

    def test_replaced_journal_does_not_supply_durable_arming(self):
        self.acquire()
        self.journal.path.rename(self.root / 'original-journal')
        self.journal.path.write_bytes(b'foreign journal')
        with self.assertRaises(replay.Hold):
            self.arm()
        self.assertFalse(self.custody.armed)
        self.assertEqual(self.journal.path.read_bytes(), b'foreign journal')
        self.assert_restored()


class EvidenceDirectoryTests(unittest.TestCase):
    def test_fresh_private_output_identity_is_shared_by_journal_and_result(self):
        with tempfile.TemporaryDirectory(prefix='original19-evidence-') as temporary:
            root = Path(temporary).resolve()
            output, owner = replay.create_output(root / 'evidence', root / 'source')
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o700)
            journal = replay.Journal(output, directory_identity=owner)
            try:
                journal.append('controlled')
                replay.persist(output / 'result.json', {'status': 'held'}, directory_identity=owner)
                self.assertEqual(json.loads((output / 'result.json').read_bytes()), {'status': 'held'})
                with self.assertRaises(FileExistsError):
                    replay.create_output(output, root / 'source')
            finally:
                journal.close()

    def test_output_parent_replacement_cannot_redirect_creation_into_source(self):
        with tempfile.TemporaryDirectory(prefix='original19-evidence-') as temporary:
            root = Path(temporary).resolve()
            source, parent, moved = root / 'source', root / 'external', root / 'moved'
            source.mkdir()
            parent.mkdir()
            mkdir = os.mkdir
            def replace_parent(name, mode=0o777, *, dir_fd=None):
                parent.rename(moved)
                parent.symlink_to(source, target_is_directory=True)
                mkdir(name, mode, dir_fd=dir_fd)
            with patch.object(os, 'mkdir', side_effect=replace_parent):
                with self.assertRaises(replay.Hold):
                    replay.create_output(parent / 'evidence', source)
            self.assertFalse((source / 'evidence').exists())
            self.assertTrue((moved / 'evidence').is_dir())

    def test_replaced_output_directory_blocks_journal_and_result_writes(self):
        with tempfile.TemporaryDirectory(prefix='original19-evidence-') as temporary:
            root = Path(temporary).resolve()
            output = root / 'output'
            output.mkdir()
            owner = replay.identity(output.stat())
            output.rename(root / 'original')
            output.mkdir()
            with self.assertRaises(replay.Hold):
                replay.persist(output / 'result.json', {'status': 'held'}, directory_identity=owner)
            self.assertFalse((output / 'result.json').exists())
            with self.assertRaises(replay.Hold):
                replay.Journal(output, directory_identity=owner)
            self.assertFalse((output / 'transitions.journal').exists())
            output.rmdir()
            output.symlink_to(root / 'original', target_is_directory=True)
            with self.assertRaises((OSError, replay.Hold)):
                replay.Journal(output)
            self.assertFalse((root / 'original/transitions.journal').exists())


class GraphTests(unittest.TestCase):
    def test_same_final_support_is_excluded_from_production_difference_closure(self):
        graph = [*replay.OWNERS, str(replay.TEST),
                 str(replay.PHONE / 'test/connection_cache_test_support.dart'), replay.BRIDGE,
                 'bindings/dart/lib/src/ward_pulse_bindings.dart']
        self.assertEqual(replay.production_paths(graph), [
            *replay.OWNERS, 'bindings/dart/lib/src/ward_pulse_bindings.dart'])

    def test_conditional_imports_and_accepted_owner_edges_are_all_bound(self):
        with tempfile.TemporaryDirectory(prefix='original19-graph-') as temporary:
            root = Path(temporary).resolve()
            for path in (str(replay.TEST), *(p for p in replay.OWNERS if p.endswith('.dart'))):
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text('')
            (root / replay.TEST).write_text(
                "import '../lib/a.dart' if (dart.library.io) '../lib/b.dart';\n")
            for name in ('a', 'b'):
                (root / replay.PHONE / 'lib' / f'{name}.dart').write_text('')
            graph = replay.dependency_graph(root)
            self.assertIn(str(replay.PHONE / 'lib/a.dart'), graph)
            self.assertIn(str(replay.PHONE / 'lib/b.dart'), graph)
            self.assertTrue(set(replay.OWNERS) <= set(graph))


class GitTests(InertFiles):
    def setUp(self):
        super().setUp()
        self.root_process = {'pid': 123, 'start': 1, 'state': 'S', 'parent': os.getpid(),
                             'session': 123, 'group': 123}
        self.members = {}
        self.child = Mock(pid=123, stdout=Mock(), stderr=Mock())
        self.git = replay.Git(self.root, '/inert/git')
        self.git.processes = self.process_tracker()

    def process_tracker(self):
        return replay.Processes(
            self.root, {}, {}, observe=lambda pid: self.members[pid],
            census=lambda: self.members.copy())

    def launch(self, *args, **kwargs):
        self.members[123] = self.root_process
        return self.child

    def test_setup_failure_retires_owned_git_and_reparented_descendants(self):
        for failure in (KeyboardInterrupt, OSError):
            with self.subTest(failure=failure.__name__):
                self.members.clear()
                self.child.reset_mock()
                self.git.processes = self.process_tracker()
                descendant = {'pid': 124, 'start': 2, 'state': 'S', 'parent': os.getpid(),
                              'session': 124, 'group': 124}
                owned = descendant if failure is KeyboardInterrupt else self.root_process
                def fail_setup():
                    if failure is KeyboardInterrupt:
                        self.members[123] = {**self.root_process, 'state': 'Z'}
                        self.members[124] = descendant
                    raise failure
                def signal_owned(record, sig, observe):
                    self.assertEqual(record, owned)
                    self.members[record['pid']] = {**record, 'state': 'Z'}
                with patch.object(replay.subprocess, 'Popen', side_effect=self.launch), \
                        patch.object(replay.selectors, 'DefaultSelector', side_effect=fail_setup), \
                        patch.object(replay, 'signal_process', side_effect=signal_owned) as send, \
                        patch.object(replay.os, 'waitpid', return_value=(124, 0)):
                    with self.assertRaises(failure):
                        self.git.run('inert')
                send.assert_called_once_with(owned, replay.signal.SIGTERM,
                                             self.git.processes.observe)
                self.child.wait.assert_called_once_with(timeout=2)
                self.child.stdout.close.assert_called_once_with()
                self.child.stderr.close.assert_called_once_with()
                self.git.processes.readers_retired()

    def test_interrupted_git_launch_holds_restoration_and_custody(self):
        self.acquire()
        self.arm()
        self.custody.substitute([(b'old', 0o600)] * 3)
        for returned in (False, True):
            with self.subTest(returned=returned):
                self.git.processes = self.process_tracker()
                self.custody.readers_retired = self.git.processes.readers_retired
                self.git.processes.observe = Mock(side_effect=KeyboardInterrupt)
                launch = {'return_value': self.child} if returned else {'side_effect': KeyboardInterrupt}
                with patch.object(replay.subprocess, 'Popen', **launch), \
                        patch.object(replay, 'signal_process') as send:
                    with self.assertRaisesRegex(replay.Hold, 'launch-ownership-unproven'):
                        self.git.run('inert')
                    with self.assertRaisesRegex(replay.Hold, 'launch-ownership-unproven'):
                        self.custody.restore()
                    with self.assertRaisesRegex(replay.Hold, 'launch-ownership-unproven'):
                        self.git.run('inert')
                    send.assert_not_called()
                self.assertEqual((self.root / 'owner-0').read_bytes(), b'old')
                self.assertTrue(self.custody.path.exists())
                if returned:
                    self.child.stdout.close.assert_called_once_with()
                    self.child.stderr.close.assert_called_once_with()


class ProcessTests(unittest.TestCase):
    def test_startup_interruption_retires_a_surviving_reparented_descendant(self):
        root = {'pid': 123, 'start': 1, 'state': 'S', 'parent': os.getpid(),
                'session': 123, 'group': 123}
        descendant = {'pid': 124, 'start': 2, 'state': 'S', 'parent': os.getpid(),
                      'session': 124, 'group': 124}
        members = {}
        child = Mock(pid=123, stdout=Mock(), stderr=Mock())
        processes = replay.Processes(Path('/inert'), {}, {}, observe=lambda pid: members[pid],
                                     census=lambda: members.copy())
        def launch(*args, **kwargs):
            members[123] = root
            return child
        def interrupt_setup():
            # The leader has exited; subreaper custody retains its setsid descendant.
            members[123] = {**root, 'state': 'Z'}
            members[124] = descendant
            raise KeyboardInterrupt
        def signal_owned(record, sig, observe):
            self.assertEqual(record, descendant)
            members[record['pid']] = {**record, 'state': 'Z'}
        with patch.object(replay.subprocess, 'Popen', side_effect=launch), \
                patch.object(replay.selectors, 'DefaultSelector', side_effect=interrupt_setup), \
                patch.object(replay, 'signal_process', side_effect=signal_owned) as send, \
                patch.object(replay.os, 'waitpid', return_value=(124, 0)):
            with self.assertRaises(KeyboardInterrupt):
                processes.run(['inert'], '/inert', {})
        self.assertEqual(processes.known[124], descendant)
        send.assert_called_once_with(descendant, replay.signal.SIGTERM, processes.observe)
        child.wait.assert_called_once_with(timeout=2)
        child.stdout.close.assert_called_once_with()
        child.stderr.close.assert_called_once_with()
        processes.readers_retired()

    def test_interrupted_launch_without_a_root_identity_holds_transitions(self):
        for returned in (False, True):
            with self.subTest(returned=returned):
                child = Mock(pid=123, stdout=Mock(), stderr=Mock())
                processes = replay.Processes(Path('/inert'), {}, {},
                                             observe=Mock(side_effect=KeyboardInterrupt), census=lambda: {})
                launch = {'return_value': child} if returned else {'side_effect': KeyboardInterrupt}
                with patch.object(replay.subprocess, 'Popen', **launch), \
                        patch.object(replay, 'signal_process') as send:
                    with self.assertRaisesRegex(replay.Hold, 'launch-ownership-unproven'):
                        processes.run(['inert'], '/inert', {})
                    with self.assertRaisesRegex(replay.Hold, 'launch-ownership-unproven'):
                        processes.readers_retired()
                    send.assert_not_called()
                self.assertTrue(processes.launch_pending)

    def test_unreadable_known_identity_is_not_absence_from_the_census(self):
        record = {'pid': 123, 'start': 1, 'state': 'S', 'parent': 1, 'session': 123, 'group': 123}
        def denied(_):
            raise PermissionError('inert in-scope observation')
        processes = replay.Processes(Path('/inert'), {}, {}, observe=denied, census=lambda: {})
        processes.known = {123: record}
        with self.assertRaisesRegex(replay.Hold, 'owned-process-unreadable'):
            processes.readers_retired()

    def test_pid_reuse_is_not_retirement_or_signal_authority(self):
        known = {'pid': 123, 'start': 1, 'state': 'S', 'parent': 1, 'session': 123, 'group': 123}
        reused = {**known, 'start': 2}
        with self.assertRaises(replay.Hold):
            replay.alive(known, lambda _: reused)
        processes = replay.Processes(Path('/inert'), {}, {}, observe=lambda _: reused,
                                     census=lambda: {123: reused})
        processes.known = {123: known}
        with patch.object(os, 'kill', side_effect=AssertionError('foreign signal')):
            with self.assertRaises(replay.Hold):
                processes.signal_owned(15)

    def test_signaling_pins_the_process_before_rechecking_its_identity(self):
        known = {'pid': 123, 'start': 1}
        calls = []
        with tempfile.TemporaryFile() as token:
            def open_pid(pid, flags):
                calls.append(('open', pid))
                return os.dup(token.fileno())
            def observe(pid):
                calls.append(('observe', pid))
                return {**known, 'start': 2}
            def send(fd, sig):
                calls.append(('send', fd))
            with self.assertRaisesRegex(replay.Hold, 'pid-reuse'):
                replay.signal_process(known, 15, observe, open_pid, send)
        self.assertEqual(calls, [('open', 123), ('observe', 123)])

    def test_descendant_that_changes_session_remains_an_owned_reader(self):
        parent = {'pid': 123, 'start': 1, 'state': 'Z', 'parent': 1, 'session': 123, 'group': 123}
        child = {'pid': 124, 'start': 2, 'state': 'S', 'parent': 123, 'session': 124, 'group': 124}
        members = {123: parent, 124: child}
        processes = replay.Processes(Path('/inert'), {}, {}, census=lambda: members.copy())
        processes.known, processes.session = {123: parent}, 123
        with self.assertRaises(replay.Hold):
            processes.readers_retired()
        self.assertEqual(processes.known[124], child)
        members[124] = {**child, 'parent': 1}
        with self.assertRaises(replay.Hold):
            processes.readers_retired()

    def test_harmless_owned_python_is_observed_and_retired(self):
        with tempfile.TemporaryDirectory(prefix='original19-process-') as temporary:
            child = subprocess.Popen([sys.executable, '-B', '-c',
                                      "import sys; print('ready', flush=True); sys.stdin.readline()"],
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     start_new_session=True)
            try:
                self.assertEqual(child.stdout.readline(), b'ready\n')
                record = replay.process_identity(child.pid)
                def census():
                    try:
                        return {child.pid: replay.process_identity(child.pid)}
                    except FileNotFoundError:
                        return {}
                processes = replay.Processes(Path(temporary), {}, {}, census=census)
                processes.child, processes.session = child, record['session']
                processes.known = {child.pid: record}
                with self.assertRaises(replay.Hold):
                    processes.readers_retired()
                processes.retire()
                self.assertIsNotNone(child.poll())
                processes.readers_retired()
            finally:
                if child.poll() is None:
                    child.kill()
                child.wait(timeout=2)
                child.stdin.close()
                child.stdout.close()

    def test_python_output_cannot_supply_java_or_ffi_execution_proof(self):
        with tempfile.TemporaryDirectory(prefix='original19-process-') as temporary:
            runtime = {name: Path('/inert') / name for name in ('java', 'javac', 'tester')}
            processes = replay.Processes(Path(temporary), runtime, {})
            code = 'import sys; sys.stdout.buffer.write(' + repr(transcript()) + ')'
            with self.assertRaisesRegex(replay.Hold, 'missing-java-or-ffi-witness'):
                processes.run([sys.executable, '-B', '-c', code], temporary, os.environ.copy())
            self.assertIsNotNone(processes.child.poll())

    def test_injected_java_classes_and_ffi_mapping_require_matching_actual_identities(self):
        with tempfile.TemporaryDirectory(prefix='original19-witness-') as temporary:
            root = Path(temporary).resolve()
            source = root / 'source'
            source.mkdir()
            output = root / 'classes'
            output.mkdir()
            library = source / replay.FFI
            library.parent.mkdir(parents=True)
            library.write_bytes(b'inert-library-observation')
            ffi = replay.file_seal(library)
            runtime = {name: Path('/inert') / name for name in ('java', 'javac', 'tester')}
            def member(pid, parent=100, state='S'):
                return {'pid': pid, 'start': pid, 'parent': parent, 'state': state,
                        'session': 100, 'group': 100}
            members = {100: member(100, 1), 101: member(101)}
            device, inode = ffi['identity'][:2]
            def mapping(actual_inode):
                return (f'0-1 r-xp 0 {os.major(device):x}:{os.minor(device):x} '
                        f'{actual_inode} {library}\n').encode()
            observations = {
                100: (Path('/inert/controller'), [], b''),
                101: (runtime['javac'], ['javac', '-d', str(output),
                                         str(source / replay.OWNERS[-1]), str(source / replay.BRIDGE)], b''),
                102: (runtime['java'], ['java', '-cp', str(output),
                                        'app.wardpulse.watchsync.ConnectionCacheEngineBridge'], b''),
                103: (runtime['tester'], ['flutter_tester'], mapping(inode)),
            }
            processes = replay.Processes(source, runtime, ffi, observe=lambda pid: members[pid],
                                         census=lambda: members.copy(), execution=lambda pid: observations[pid])
            processes.session, processes.known, processes.started_ns = 100, {100: members[100]}, 0
            processes.observe_execution()
            for name in (replay.ENGINE_CLASS, replay.BRIDGE_CLASS):
                path = output / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'\xca\xfe\xba\xbe-inert-observation')
            members[101] = member(101, state='Z')
            members.update({102: member(102), 103: member(103)})
            processes.observe_execution()
            self.assertEqual(len(processes.javac), 1)
            self.assertEqual(set(next(iter(processes.java.values()))['classes']),
                             {replay.ENGINE_CLASS, replay.BRIDGE_CLASS})
            self.assertEqual(processes.mapping, members[103])
            observations[103] = (runtime['tester'], [], mapping(inode + 1))
            with self.assertRaisesRegex(replay.Hold, 'ffi-mapping-identity'):
                processes.observe_execution()


class OrchestrationTests(InertFiles):
    def test_three_legs_have_identical_support_and_ordered_transitions(self):
        self.acquire()
        self.arm()
        support = self.root / 'support'
        support.write_bytes(b'identical final support')
        seal = replay.file_seal(support)
        calls = []
        def verify(old):
            self.assertEqual(replay.file_seal(support), seal)
            self.assertEqual((self.root / 'owner-0').read_bytes(), b'old' if old else b'final-0')
            calls.append(('verify', old))
        def leg(old):
            calls.append(('leg', old))
            return reporter(transcript(old)).classify(1 if old else 0, old)
        flow = replay.Replay(self.custody, verify, leg, lambda: calls.append(('retire', None)), self.journal)
        flow.run([(b'old', 0o600)] * 3)
        self.assertEqual([p['classification'] for p in flow.legs],
                         ['FINAL0', 'OLD-named-semantic1', 'restored-FINAL0'])
        self.assertEqual([old for action, old in calls if action == 'leg'], [False, True, False])
        self.assert_restored()
        self.assertFalse((self.root / 'index.lock').exists())

    def test_infrastructure_failure_does_not_run_restored_leg_until_exact_restoration(self):
        self.acquire()
        self.arm()
        calls = []
        def leg(old):
            calls.append(old)
            if old:
                raise replay.Hold('synthetic-infrastructure')
            return reporter(transcript()).classify(0)
        def verify(old):
            self.assertEqual((self.root / 'owner-0').read_bytes(), b'old' if old else b'final-0')
        flow = replay.Replay(self.custody, verify, leg, lambda: None, self.journal)
        with self.assertRaises(replay.Hold):
            flow.run([(b'old', 0o600)] * 3)
        flow.contain()
        self.assertEqual(calls, [False, True])
        self.assert_restored()
        self.assertFalse((self.root / 'index.lock').exists())

    def test_changed_same_final_account_values_hold_and_restore(self):
        self.acquire()
        self.arm()
        def leg(old):
            evidence = oracle(old)
            if old:
                evidence['acceptedAccounts'][1]['spent'] = 1
            return reporter(transcript(old, evidence)).classify(1 if old else 0, old)
        flow = replay.Replay(self.custody, lambda _: None, leg, lambda: None, self.journal)
        with self.assertRaisesRegex(replay.Hold, 'same-final-observations-changed'):
            flow.run([(b'old', 0o600)] * 3)
        flow.contain()
        self.assert_restored()


class RuntimeTests(InertFiles):
    def setUp(self):
        super().setUp()
        self.source = self.root / 'source'
        self.sdk = self.source / '.toolchains/flutter'
        self.cache = self.sdk / 'bin/cache'
        self.cache.mkdir(parents=True)
        self.engine = b'a' * 40 + b'\n'
        producers = {}
        for name in replay.SDK_PRODUCERS:
            path = self.sdk / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'controlled producer: ' + name.encode())
            producers[name] = replay.digest(path.read_bytes())
        producer_patch = patch.object(replay, 'SDK_PRODUCERS', producers)
        producer_patch.start()
        self.addCleanup(producer_patch.stop)
        (self.sdk / 'bin/internal/engine.version').write_bytes(self.engine)
        (self.cache / 'flutter.version.json').write_bytes(replay.encoded({
            'frameworkVersion': '3.44.6', 'dartSdkVersion': '3.12.2',
            'engineRevision': self.engine[:-1].decode()}))
        paths = {'flutter': self.sdk / 'bin/flutter',
                 'dart': self.cache / 'dart-sdk/bin/dart',
                 'tester': self.cache / 'artifacts/engine/linux-x64/flutter_tester',
                 'python': Path(sys.executable).resolve()}
        for name in ('java', 'javac', 'git'):
            paths[name] = self.root / 'tools' / name
        for name, path in paths.items():
            if name != 'python':
                path.parent.mkdir(parents=True, exist_ok=True)
                if not path.exists():
                    path.write_bytes(b'inert executable')
                path.chmod(0o755)
        (self.cache / 'dart-sdk/version').write_bytes(b'3.12.2\n')
        self.config = self.source / replay.PACKAGE_CONFIG
        self.config.parent.mkdir(parents=True)
        packages = {'ward_pulse_phone': self.source / replay.PHONE,
                    'ward_pulse_bindings': self.source / 'bindings/dart',
                    'ward_pulse_watch_sync': self.source / replay.PHONE / 'plugins/ward_pulse_watch_sync'}
        for path in packages.values():
            path.mkdir(parents=True, exist_ok=True)
        self.config.write_bytes(replay.encoded({'configVersion': 2, 'packages': [
            {'name': name, 'rootUri': path.as_uri(), 'packageUri': 'lib/'}
            for name, path in packages.items()]}))
        self.ffi = self.source / replay.FFI
        self.ffi.parent.mkdir(parents=True)
        self.ffi.write_bytes(b'inert ffi input, never loaded')
        self.paths = paths
        self.inputs = [self.sdk, self.config, self.ffi, paths['python'],
                       *(paths[name] for name in ('java', 'javac', 'git'))]

    def runtime(self):
        bookkeeping = replay.sdk_bookkeeping(self.sdk)
        value = {'versions': {'flutter': '3.44.6', 'dart': '3.12.2'},
                 'executables': {name: str(path) for name, path in self.paths.items()},
                 'inputs': [{'path': str(path), 'sealSha256': replay.digest(
                     replay.encoded(replay.runtime_seal(path, bookkeeping)))} for path in self.inputs],
                 'ffiSha256': replay.digest(self.ffi.read_bytes())}
        return replay.Runtime(self.source, Mock(value={'runtime': value}))

    def test_stock_stamp_creation_and_atomic_rename_pass_post_final_verification(self):
        runtime = self.runtime()
        self.acquire()
        self.arm()
        calls = []
        def verify(old):
            runtime.verify()
            calls.append(('verify', old))
        def leg(old):
            stamp = self.cache / 'engine.stamp'
            previous = replay.identity(stamp.stat()) if stamp.exists() else None
            temporary = self.cache / 'engine.stamp.tmp.123'
            temporary.write_bytes(self.engine)
            temporary.chmod(0o664 if previous is None else 0o644)
            temporary.replace(stamp)
            self.assertNotEqual(replay.identity(stamp.stat()), previous)
            (self.cache / 'engine.realm').write_bytes(b'\n')
            calls.append(('leg', old))
            return reporter(transcript(old)).classify(1 if old else 0, old)
        flow = replay.Replay(self.custody, verify, leg, lambda: None, self.journal)
        flow.run([(b'old', 0o600)] * 3)
        self.assertEqual([p['classification'] for p in flow.legs],
                         ['FINAL0', 'OLD-named-semantic1', 'restored-FINAL0'])
        self.assertEqual(calls[:4], [('verify', False), ('leg', False),
                                     ('verify', False), ('verify', True)])
        self.assert_restored()

    def test_changed_bookkeeping_and_immutable_inputs_hold(self):
        runtime = self.runtime()
        changes = [(self.cache / 'engine.stamp', b'b' * 40 + b'\n'),
                   (self.cache / 'engine.realm', b'foreign-realm\n'),
                   (self.sdk / 'bin/internal/engine.version', b'b' * 40 + b'\n'),
                   (self.paths['dart'], b'changed executable'),
                   (self.cache / 'flutter.version.json', b'{}'),
                   (self.config, b'{}'), (self.ffi, b'changed ffi'),
                   (self.cache / 'lockfile', b''),
                   (self.cache / 'engine.stamp.tmp.123', self.engine)]
        for path, data in changes:
            original = path.read_bytes() if path.exists() else None
            with self.subTest(path=path):
                try:
                    path.write_bytes(data)
                    with self.assertRaises(replay.Hold):
                        runtime.verify()
                finally:
                    if original is None:
                        path.unlink()
                    else:
                        path.write_bytes(original)

    def test_generated_content_and_pinned_producer_are_checked_at_admission(self):
        (self.cache / 'engine.stamp').write_bytes(b'changed stamp')
        with self.assertRaisesRegex(replay.Hold, 'sdk-bookkeeping-content'):
            self.runtime()
        (self.sdk / 'bin/internal/shared.sh').write_bytes(b'changed producer')
        with self.assertRaisesRegex(replay.Hold, 'sdk-wrapper-producer'):
            replay.sdk_bookkeeping(self.sdk)

    def test_immutable_same_byte_rename_and_generated_link_are_rejected(self):
        runtime = self.runtime()
        dart = self.paths['dart']
        temporary = dart.with_suffix('.tmp')
        temporary.write_bytes(dart.read_bytes())
        temporary.chmod(0o755)
        temporary.replace(dart)
        with self.assertRaisesRegex(replay.Hold, 'runtime-changed'):
            runtime.verify()
        (self.cache / 'engine.stamp').symlink_to(self.sdk / 'bin/internal/engine.version')
        with self.assertRaisesRegex(replay.Hold, 'sdk-bookkeeping-content'):
            replay.runtime_seal(self.sdk, replay.sdk_bookkeeping(self.sdk))


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='original19-release-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.source = self.root / 'source'
        self.source.mkdir()
        self.final = '1' * 40
        self.now = 10**12
        self.controller = {'startedNs': self.now}
        self.run = 'controlled-run'
        self.boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
        current = replay.process_identity(os.getpid())
        self.retired = {'pid': current['pid'], 'start': current['start'] - 1, 'bootId': self.boot}
        self.records = {
            'done': {'status': 'DONE', 'head': self.final},
            'cli': {'used': True, 'identity': self.retired, 'actualExit': True, 'exitCode': 0},
            'retirement': {'scope': self.run, 'identities': [self.retired], 'remaining': [], 'unresolved': []},
            'idle': {'public': True, 'status': 'idle', 'lease': None, 'processes': []},
        }
        self.metadata = self.root / 'pinned-input'
        self.metadata.write_bytes(b'neutral admitted metadata')
        self.value = {'format': 'original19-release-v1', 'admittedBy': 'Root', 'final': self.final,
                      'source': str(self.source), 'sourceIdentity': list(replay.identity(self.source.stat())),
                      'runId': self.run, 'records': {}, 'metadata': []}
        self.receipt = self.root / 'release.json'
        self.patch = patch.object(replay, 'SOURCE', self.source)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def write(self):
        for index, (kind, record) in enumerate(self.records.items()):
            path = self.root / f'{kind}.json'
            path.write_bytes(replay.encoded({'runId': self.run, 'kind': kind,
                                            'observedNs': self.now - 4000 + 1000 * index, **record}))
            self.value['records'][kind] = {'path': str(path),
                                         'sealSha256': replay.digest(replay.encoded(replay.file_seal(path)))}
        self.value['metadata'] = [{'path': str(self.metadata),
                                  'sealSha256': replay.digest(replay.encoded(replay.file_seal(self.metadata)))}]
        self.receipt.write_bytes(replay.encoded(self.value))

    def qualify(self):
        return replay.Release(self.source, self.receipt, self.final, self.controller, lambda: self.now)

    def test_linked_whole_release_and_sealed_metadata(self):
        self.write()
        release = self.qualify()
        release.verify()
        self.metadata.write_bytes(b'replaced neutral metadata')
        with self.assertRaises(replay.Hold):
            release.verify()

    def test_cli_done_idle_and_retirement_are_independent_gates(self):
        changes = [('done', 'status', 'RUNNING'), ('cli', 'actualExit', False),
                   ('idle', 'public', False), ('idle', 'lease', 'active'),
                   ('retirement', 'unresolved', [self.retired])]
        for kind, key, value in changes:
            previous = self.records[kind].get(key)
            self.records[kind][key] = value
            self.write()
            with self.subTest(kind=kind, key=key), self.assertRaises(replay.Hold):
                self.qualify()
            self.records[kind][key] = previous

    def test_stale_idle_wrong_source_identity_and_tampered_link_hold(self):
        self.write()
        with self.assertRaises(replay.Hold):
            replay.Release(self.source, self.receipt, self.final, self.controller,
                           lambda: self.now + 301 * 10**9)
        self.value['sourceIdentity'][1] += 1
        self.receipt.write_bytes(replay.encoded(self.value))
        with self.assertRaises(replay.Hold):
            self.qualify()
        self.value['sourceIdentity'] = list(replay.identity(self.source.stat()))
        self.write()
        (self.root / 'idle.json').write_bytes(b'{}')
        with self.assertRaises(replay.Hold):
            self.qualify()

    def test_receipt_alias_cannot_hide_an_input_inside_source(self):
        self.write()
        (self.source / 'release.json').write_bytes(self.receipt.read_bytes())
        alias = self.root / 'alias'
        alias.symlink_to(self.source, target_is_directory=True)
        with self.assertRaisesRegex(replay.Hold, 'receipt-in-source'):
            replay.Release(self.source, alias / 'release.json', self.final, self.controller,
                           lambda: self.now)


if __name__ == '__main__':
    unittest.main()
