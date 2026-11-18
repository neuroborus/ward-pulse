#!/usr/bin/env python3
"""HOST-only original19 replay. Importing this module performs no replay or writes."""

import argparse
import codecs
import hashlib
import json
import math
import os
from pathlib import Path
import re
import selectors
import signal
import stat
import subprocess
import sys
import time
from urllib.parse import unquote, urljoin, urlparse


SOURCE = Path('/home/neuroborus/Desktop/PROJECTS/PETS/ward-pulse')
PHONE = Path('apps/phone_flutter')
OLD = 'ddc53fcbb139f221e9a46bd05566ab7e379de950'
CASE = 'connection absence ownership retains accepted A+B after late work'
TAG = 'connection absence ownership oracle '
ASSERTION = 'Late B-only work must not replace accepted A+B'
OWNERS = tuple(str(PHONE / name) for name in (
    'lib/providers/connection_lifecycle.dart',
    'lib/dashboard/merging_connection_repository.dart',
    'lib/dashboard/connection_snapshot_cache.dart',
    'lib/dashboard/dashboard_repository.dart',
    'lib/dashboard/dashboard_load.dart',
    'lib/sync/provider_sync_once.dart',
    'lib/sync/recovery_watchlist.dart',
    'plugins/ward_pulse_watch_sync/android/src/main/java/app/wardpulse/watchsync/ConnectionCacheEngine.java',
))
BRIDGE = 'tools/test-phone-cache/ConnectionCacheEngineBridge.java'
ENGINE_CLASS = 'app/wardpulse/watchsync/ConnectionCacheEngine.class'
BRIDGE_CLASS = 'app/wardpulse/watchsync/ConnectionCacheEngineBridge.class'
FFI = Path('core/target/debug/libward_pulse_ffi.so')
PACKAGE_CONFIG = PHONE / '.dart_tool/package_config.json'
TEST = PHONE / 'test/connection_snapshot_cache_test.dart'
MAX_FILE = 8 * 1024 * 1024
MAX_LINE = 64 * 1024
MAX_STREAM = 4 * 1024 * 1024
MAX_DEPTH = 24
JOURNAL_SLOT = 16 * 1024
JOURNAL_SLOTS = 64
RESTORATION_SLOTS = 8
SDK_PRODUCERS = {
    'bin/flutter': '7d486c33b30a0cf1ea5146231c68bb8f966cdb4e087c5cd8b37e14513f536e7d',
    'bin/internal/shared.sh': '7029bb28e9f60927807f2119d2afe388742db41d34c26f5e263bf15568911fa2',
    'bin/internal/update_engine_version.sh': '6d71ef5d911243afdc83a4238b65159aad7905d7b19cb2464db40e347536ebb4',
}


class Hold(Exception):
    """A fixed, privacy-safe failure code; never include captured output in it."""


def need(condition, code):
    if not condition:
        raise Hold(code)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def integer(value):
    return type(value) is int


def strict_json(data, limit=MAX_LINE):
    need(len(data) <= limit, 'json-size')
    if isinstance(data, bytes):
        try:
            data = data.decode('utf-8', errors='strict')
        except UnicodeError:
            raise Hold('utf8') from None
    # Bound nesting before asking the recursive JSON decoder to allocate objects.
    depth = 0
    quoted = escaped = False
    for character in data:
        if quoted:
            if escaped:
                escaped = False
            elif character == '\\':
                escaped = True
            elif character == '"':
                quoted = False
        elif character == '"':
            quoted = True
        elif character in '[{':
            depth += 1
            need(depth <= MAX_DEPTH, 'json-depth')
        elif character in ']}':
            depth -= 1
    def pairs(items):
        result = {}
        for key, value in items:
            need(key not in result, 'json-duplicate-key')
            result[key] = value
        return result
    def constant(_):
        raise Hold('json-number')
    try:
        value = json.loads(data, object_pairs_hook=pairs, parse_constant=constant)
    except (ValueError, RecursionError):
        raise Hold('json-malformed') from None
    def finite(item):
        if isinstance(item, float):
            need(math.isfinite(item), 'json-number')
        elif isinstance(item, dict):
            for key, child in item.items():
                need(not any(0xD800 <= ord(c) <= 0xDFFF for c in key), 'json-unicode')
                finite(child)
        elif isinstance(item, list):
            for child in item:
                finite(child)
        elif isinstance(item, str):
            need(not any(0xD800 <= ord(c) <= 0xDFFF for c in item), 'json-unicode')
    finite(value)
    return value


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()


def identity(info):
    return (info.st_dev, info.st_ino, info.st_uid, info.st_gid, info.st_nlink)


def read_regular(path, limit=MAX_FILE):
    """Read through a stable, non-symlink descriptor; do not follow a replaced leaf."""
    path = Path(path)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        before = os.fstat(fd)
        need(stat.S_ISREG(before.st_mode), 'not-regular')
        need(before.st_size <= limit, 'file-size')
        data = bytearray()
        while True:
            block = os.read(fd, min(65536, limit + 1 - len(data)))
            if not block:
                break
            data.extend(block)
            need(len(data) <= limit, 'file-size')
        after = os.fstat(fd)
        need((identity(before), before.st_size, before.st_mtime_ns, before.st_ctime_ns) ==
             (identity(after), after.st_size, after.st_mtime_ns, after.st_ctime_ns), 'file-raced')
        need(identity(path.lstat()) == identity(after), 'file-replaced')
        return bytes(data), after
    finally:
        os.close(fd)


def file_seal(path):
    """Hash large immutable binaries without retaining their bytes."""
    path = Path(path)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        before = os.fstat(fd)
        need(stat.S_ISREG(before.st_mode), 'not-regular')
        sha = hashlib.sha256()
        while block := os.read(fd, 1024 * 1024):
            sha.update(block)
        after = os.fstat(fd)
        need((identity(before), before.st_size, before.st_mtime_ns, before.st_ctime_ns) ==
             (identity(after), after.st_size, after.st_mtime_ns, after.st_ctime_ns), 'file-raced')
        need(identity(path.lstat()) == identity(after), 'file-replaced')
        return {'identity': list(identity(after)), 'mode': stat.S_IMODE(after.st_mode),
                'size': after.st_size, 'sha256': sha.hexdigest()}
    finally:
        os.close(fd)


def tree_seal(path):
    """Include directory membership and link identities; never traverse symlinks."""
    path = Path(path)
    info = path.lstat()
    if stat.S_ISREG(info.st_mode):
        return file_seal(path)
    if stat.S_ISLNK(info.st_mode):
        return {'identity': list(identity(info)), 'link': os.readlink(path)}
    need(stat.S_ISDIR(info.st_mode), 'tree-type')
    entries = {}
    for child in sorted(path.iterdir()):
        entries[child.name] = tree_seal(child)
    need(identity(path.lstat()) == identity(info), 'directory-replaced')
    return {'identity': list(identity(info)), 'mode': stat.S_IMODE(info.st_mode),
            'entries': entries}


def sdk_bookkeeping(sdk):
    """Qualify the two outputs of the pinned stock engine-version producer."""
    for name, expected in SDK_PRODUCERS.items():
        need(file_seal(sdk / name)['sha256'] == expected, 'sdk-wrapper-producer')
    engine = read_regular(sdk / 'bin/internal/engine.version')[0]
    version = strict_json(read_regular(sdk / 'bin/cache/flutter.version.json')[0])
    need(re.fullmatch(rb'[0-9a-f]{40}\n', engine) is not None and
         type(version) is dict and version.get('engineRevision') == engine[:-1].decode(),
         'sdk-engine-binding')
    cache = sdk / 'bin/cache'
    need(cache.resolve(strict=True) == cache, 'sdk-cache-path')
    # Runtime.environment excludes FLUTTER_PREBUILT_ENGINE_VERSION and FLUTTER_REALM.
    return {cache / 'engine.stamp': engine, cache / 'engine.realm': b'\n'}


def runtime_seal(path, bookkeeping):
    """Keep immutable tree seals; qualify only proven generated engine bookkeeping."""
    def qualify(path, seal):
        if path in bookkeeping:
            expected = bookkeeping[path]
            if seal is not None:
                parent = path.parent.stat()
                need('sha256' in seal and seal['size'] == len(expected) and
                     seal['sha256'] == digest(expected), 'sdk-bookkeeping-content')
                need(seal['identity'][0] == parent.st_dev and
                     seal['identity'][2:] == [os.getuid(), parent.st_gid, 1] and
                     seal['mode'] & 0o600 == 0o600 and seal['mode'] & ~0o664 == 0,
                     'sdk-bookkeeping-ownership')
            # Creation and the producer's same-byte atomic rename may change membership,
            # inode and nonexecutable creation mode, never the derived engine/realm bytes.
            return {'bookkeepingSha256': digest(expected), 'size': len(expected)}
        if 'entries' in seal:
            entries = seal['entries']
            for generated in bookkeeping:
                if generated.parent == path:
                    need(not any(name.startswith('engine.stamp.tmp.') for name in entries),
                         'sdk-bookkeeping-temporary')
                    entries.setdefault(generated.name, None)
            seal['entries'] = {name: qualify(path / name, child) for name, child in entries.items()}
        return seal
    return qualify(Path(path), tree_seal(path))


def fsync_directory(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def open_directory(path, expected=None):
    path = Path(path)
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        owner = identity(os.fstat(fd))
        need(path.resolve(strict=True) == path and identity(path.lstat()) == owner,
             'evidence-directory-replaced')
        need(expected is None or owner == expected, 'evidence-directory-replaced')
        return fd
    except BaseException:
        os.close(fd)
        raise


def create_output(path, source):
    path = Path(path)
    need(path.is_absolute() and not path.is_relative_to(source), 'external-output')
    parent = open_directory(path.parent)
    try:
        owner = identity(os.fstat(parent))[:4]
        os.mkdir(path.name, mode=0o700, dir_fd=parent)
        need(identity(path.parent.lstat())[:4] == owner and
             path.parent.resolve(strict=True) == path.parent, 'evidence-directory-replaced')
        directory = open_directory(path)
        try:
            info = os.fstat(directory)
            need(info.st_uid == os.getuid() and stat.S_IMODE(info.st_mode) == 0o700,
                 'evidence-directory-ownership')
            directory_identity = identity(info)
        finally:
            os.close(directory)
        os.fsync(parent)
    finally:
        os.close(parent)
    return path, directory_identity


class Journal:
    """Preallocated fixed slots leave recovery space even at the normal bound."""

    def __init__(self, directory, write=os.pwrite, sync=os.fsync, directory_identity=None):
        self.path = Path(directory) / 'transitions.journal'
        directory_fd = open_directory(self.path.parent, directory_identity)
        self.fd = None
        self.write = write
        self.sync = sync
        self.slot = 0
        self.failed = False
        try:
            self.directory = identity(os.fstat(directory_fd))
            self.fd = os.open(self.path.name, os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                              0o600, dir_fd=directory_fd)
            self.owner = identity(os.fstat(self.fd))
            need(identity(self.path.parent.lstat()) == self.directory and
                 self.path.parent.resolve(strict=True) == self.path.parent,
                 'evidence-directory-replaced')
            os.posix_fallocate(self.fd, 0, JOURNAL_SLOT * JOURNAL_SLOTS)
            self.sync(self.fd)
            os.fsync(directory_fd)
        except BaseException:
            self.failed = True
            if self.fd is not None:
                os.close(self.fd)
            raise
        finally:
            os.close(directory_fd)

    def append(self, event, recovery=False, **fields):
        # Call sites supply fixed event names and explicitly sanitized projections only.
        try:
            need(identity(os.fstat(self.fd)) == self.owner == identity(self.path.lstat()) and
                 identity(self.path.parent.lstat()) == self.directory and
                 self.path.parent.resolve(strict=True) == self.path.parent, 'journal-replaced')
            need(stat.S_IMODE(os.fstat(self.fd).st_mode) == 0o600, 'journal-mode')
            maximum = JOURNAL_SLOTS if recovery else JOURNAL_SLOTS - RESTORATION_SLOTS
            need(self.slot < maximum, 'journal-bound')
            record = encoded({'event': event, **fields})
            need(len(record) < JOURNAL_SLOT, 'journal-record-bound')
            block = record + b' ' * (JOURNAL_SLOT - len(record) - 1) + b'\n'
            offset = self.slot * JOURNAL_SLOT
            while block:
                count = self.write(self.fd, block, offset)
                need(integer(count) and 0 < count <= len(block), 'journal-write')
                block = block[count:]
                offset += count
            self.sync(self.fd)
            need(identity(self.path.lstat()) == self.owner, 'journal-replaced')
            self.slot += 1
        except BaseException:
            self.failed = True
            raise

    def close(self):
        os.close(self.fd)


class StableFile:
    def __init__(self, path):
        self.path = Path(path)
        need(self.path.resolve() == self.path, 'source-link')
        self.fd = os.open(self.path, os.O_RDWR | os.O_NOFOLLOW | os.O_CLOEXEC)
        try:
            self.initial = os.fstat(self.fd)
            need(stat.S_ISREG(self.initial.st_mode) and self.initial.st_nlink == 1 and
                 self.initial.st_uid == os.getuid(), 'source-ownership')
            self.mode = stat.S_IMODE(self.initial.st_mode)
            self.final, _ = read_regular(self.path)
            self.check()
        except BaseException:
            os.close(self.fd)
            raise

    def check(self):
        current = os.fstat(self.fd)
        need(identity(current) == identity(self.initial) == identity(self.path.lstat()),
             'source-replaced')
        need(stat.S_ISREG(current.st_mode) and stat.S_IMODE(current.st_mode) == self.mode,
             'source-mode')

    def replace(self, data, mode, write=os.pwrite):
        self.check()
        offset = 0
        while offset < len(data):
            count = write(self.fd, data[offset:], offset)
            need(integer(count) and 0 < count <= len(data) - offset, 'source-write')
            offset += count
        os.ftruncate(self.fd, len(data))
        os.fchmod(self.fd, mode)
        self.mode = mode
        os.fsync(self.fd)
        self.check()
        need(read_regular(self.path)[0] == data, 'source-write-verification')

    def close(self):
        os.close(self.fd)


class Custody:
    """No context-manager cleanup may silently restore or release uncertain custody."""

    def __init__(self, lock_path, journal, readers_retired):
        self.path = Path(lock_path)
        self.journal = journal
        self.readers_retired = readers_retired
        self.fd = None
        self.files = []
        self.attempted = False
        self.armed = False
        self.unlinked = False
        self.acquisition = 'not-attempted'
        self.owner = None

    def acquire(self):
        # A signal may arrive after creation but before the returned descriptor is retained.
        self.acquisition = 'unknown'
        self.journal.append('lock-acquisition-pending')
        try:
            self.fd = os.open(self.path, os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        except FileExistsError:
            self.acquisition = 'foreign'
            raise Hold('foreign-index-lock') from None
        self.owner = os.fstat(self.fd)
        need(self.owner.st_uid == os.getuid() and self.owner.st_nlink == 1, 'lock-ownership')
        self.check()
        self.acquisition = 'owned'
        os.fsync(self.fd)
        fsync_directory(self.path.parent)

    def check(self):
        need(self.fd is not None and self.owner is not None and
             identity(os.fstat(self.fd)) == identity(self.owner) ==
             identity(self.path.lstat()), 'lock-replaced')
        need(stat.S_ISREG(os.fstat(self.fd).st_mode) and
             stat.S_IMODE(os.fstat(self.fd).st_mode) == 0o600, 'lock-mode')

    def evidence(self):
        disposition = 'released' if self.unlinked else self.acquisition
        if disposition == 'owned':
            try:
                self.check()
            except BaseException:
                disposition = 'unknown'
        return {'custodyHeld': True if disposition == 'owned' else
                'unknown' if disposition == 'unknown' else False,
                'lockDisposition': disposition,
                'lockIdentity': list(identity(self.owner)) if self.owner is not None else None}

    def prepare(self, files, blobs):
        self.check()
        self.files = files
        need(len(files) == len(blobs), 'restore-manifest')
        self.readers_retired()
        self.journal.append('restoration-armed', files=blobs)
        self.armed = True

    def substitute(self, old_blobs, write=os.pwrite):
        self.check()
        need(self.armed, 'restoration-unarmed')
        self.readers_retired()
        # Durable before the very first write attempt, even one that throws immediately.
        self.journal.append('substitution-may-have-begun')
        self.attempted = True
        for handle, (data, mode) in zip(self.files, old_blobs, strict=True):
            handle.replace(data, mode, write)
        self.journal.append('old-installed')

    def restore(self):
        if not self.attempted:
            return
        self.check()
        need(self.armed, 'restoration-unarmed')
        self.readers_retired()
        # Once armed, restore after partial writes even if subsequent journaling failed.
        journal_error = None
        try:
            self.journal.append('restoration-started', recovery=True)
        except (OSError, Hold) as error:
            journal_error = error
        for handle in self.files:
            handle.replace(handle.final, stat.S_IMODE(handle.initial.st_mode))
        for handle in self.files:
            handle.check()
            need(read_regular(handle.path)[0] == handle.final and
                 handle.mode == stat.S_IMODE(handle.initial.st_mode), 'restoration-verification')
        self.attempted = False
        if journal_error:
            raise Hold('journal-failure') from None
        self.journal.append('restoration-verified', recovery=True)

    def release(self):
        self.check()
        need(not self.attempted and not self.journal.failed, 'custody-held')
        self.readers_retired()
        self.journal.append('release-verified', recovery=True)
        self.check()
        os.unlink(self.path)
        self.unlinked = True
        fsync_directory(self.path.parent)
        os.close(self.fd)
        self.fd = None

    def close_handles(self):
        for handle in self.files:
            handle.close()
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None


ROW_FIELDS = ('kind', 'spent_minor', 'spent_currency', 'cap_minor', 'cap_currency',
              'extra_used_value', 'extra_used_unit', 'extra_cap_value', 'extra_cap_unit',
              'percent', 'credits', 'label', 'family', 'pool', 'resets_at', 'color')
PAYLOAD_KEYS = {'stale', 'empty', 'row_count'} | {
    f'row_{row}_{field}' for row in range(6) for field in ROW_FIELDS}


def accounts(value):
    need(type(value) is list and 0 < len(value) <= 2, 'oracle-accounts')
    result = []
    seen = set()
    for account in value:
        need(type(account) is dict and set(account) ==
             {'id', 'connection', 'status', 'spent', 'allowances'}, 'oracle-account-shape')
        need(account['id'] in ('openai-local', 'cursor-local') and
             account['id'] not in seen, 'oracle-account-identity')
        seen.add(account['id'])
        need(account['connection'] == {'openai-local': 'openai.platform',
                                      'cursor-local': 'cursor.plan'}[account['id']],
             'oracle-account-connection')
        need(account['status'] in ('ok', 'warning', 'rateLimited', 'authRequired',
                                  'stale', 'error', 'unknown'), 'oracle-account-status')
        need(account['spent'] is None or (integer(account['spent']) and
             0 <= account['spent'] < 10**12), 'oracle-account-spent')
        windows = account['allowances']
        need(type(windows) is list and len(windows) <= 8, 'oracle-allowances')
        ids = set()
        for window in windows:
            need(type(window) is dict and set(window) == {'id', 'usedPercent'},
                 'oracle-allowance-shape')
            need(type(window['id']) is str and window['id'] in
                 ('cursor-plan', 'cursor-extra', 'cursor-on-demand') and
                 window['id'] not in ids, 'oracle-allowance-identity')
            ids.add(window['id'])
            used = window['usedPercent']
            need(used is None or (type(used) in (int, float) and 0 <= used <= 10000),
                 'oracle-allowance-value')
        result.append(account)
    return result


def payload(value):
    need(type(value) is dict and set(value) == PAYLOAD_KEYS, 'oracle-payload-shape')
    need(integer(value['row_count']) and 0 <= value['row_count'] <= 6 and
         value['stale'] in ('0', '1') and value['empty'] in ('0', '1'), 'oracle-payload-flags')
    for key in PAYLOAD_KEYS - {'row_count'}:
        need(type(value[key]) is str and len(value[key]) <= 160 and
             all(c.isprintable() for c in value[key]), 'oracle-payload-value')
    return value


def validate_oracle(value):
    keys = {'oldAccounts', 'acceptedAccounts', 'lateOutcome', 'lateCurrent', 'latePublished',
            'completedAbsentReads', 'publications', 'redraws', 'visible'}
    need(type(value) is dict and set(value) == keys, 'oracle-shape')
    accounts(value['oldAccounts'])
    accounts(value['acceptedAccounts'])
    need(value['lateOutcome'] in ('completed', 'error'), 'oracle-outcome')
    need(type(value['lateCurrent']) is bool and type(value['latePublished']) is bool,
         'oracle-booleans')
    need(integer(value['completedAbsentReads']) and 0 <= value['completedAbsentReads'] <= 8,
         'oracle-absence-reads')
    for key in ('publications', 'redraws'):
        need(type(value[key]) is list and 0 < len(value[key]) <= 3, 'oracle-effects')
        for item in value[key]:
            payload(item)
    payload(value['visible'])
    return value


def payload_projection(value):
    # Keep values needed for the causal proof, never free-form labels or reports.
    fields = ('kind', 'family', 'percent', 'spent_minor', 'spent_currency')
    result = {key: value[key] for key in ('row_count', 'stale', 'empty')}
    for row in range(value['row_count']):
        for field in fields:
            item = value[f'row_{row}_{field}']
            if field == 'family':
                need(item in ('Cursor', 'OpenAI'), 'oracle-family')
            elif field == 'kind':
                need(item in ('allowance', 'budget'), 'oracle-kind')
            elif field == 'percent':
                need(item == '' or re.fullmatch(r'\d+(?:\.\d+)?% (?:left|used)', item),
                     'oracle-percent')
            elif field == 'spent_minor':
                need(item == '' or re.fullmatch(r'\d{1,12}', item), 'oracle-spend')
            else:
                need(item in ('', 'USD'), 'oracle-currency')
            result[f'row_{row}_{field}'] = item
    result['payloadSha256'] = digest(encoded(value))
    return result


class Reporter:
    """One bounded raw oracle, associated with the live named reporter test."""

    def __init__(self):
        self.decoder = codecs.getincrementaldecoder('utf-8')(errors='strict')
        self.pending = ''
        self.total = 0
        self.tests = {}
        self.named = None
        self.oracle = None
        self.errors = []
        self.done = None
        self.started = False
        self.closed = False
        self.events = 0

    def feed(self, block, final=False):
        need(not self.closed, 'reporter-after-eof')
        self.total += len(block)
        need(self.total <= MAX_STREAM, 'stream-bound')
        try:
            decoded = self.decoder.decode(block, final=final)
        except UnicodeError:
            raise Hold('utf8') from None
        self.pending += decoded
        while '\n' in self.pending:
            line, self.pending = self.pending.split('\n', 1)
            need(len(line.encode()) <= MAX_LINE, 'line-bound')
            self.line(line.rstrip('\r'))
        need(len(self.pending.encode()) <= MAX_LINE, 'line-bound')
        if final:
            need(not self.pending.strip(), 'reporter-truncated')
            self.closed = True

    def line(self, line):
        if not line:
            return
        need(self.done is None, 'reporter-after-done')
        self.events += 1
        need(self.events <= 20000, 'reporter-event-bound')
        if line.startswith(TAG):
            need(self.oracle is None and self.named is not None and
                 self.tests[self.named]['result'] is None, 'oracle-duplicate-or-unassociated')
            self.oracle = validate_oracle(strict_json(line[len(TAG):]))
            return
        event = strict_json(line)
        need(type(event) is dict and type(event.get('type')) is str, 'reporter-event')
        kind = event['type']
        need(integer(event.get('time')) and event['time'] >= 0, 'reporter-time')
        if kind == 'start':
            need(not self.started, 'reporter-start')
            self.started = True
            return
        need(self.started, 'reporter-no-start')
        if kind in ('suite', 'allSuites'):
            return
        if kind == 'testStart':
            test = event.get('test')
            need(type(test) is dict and integer(test.get('id')) and
                 type(test.get('name')) is str and test['id'] not in self.tests,
                 'reporter-test')
            for key in ('line', 'column'):
                need(test.get(key) is None or integer(test[key]), 'reporter-location')
            need(test.get('url') is None or type(test['url']) is str, 'reporter-location')
            self.tests[test['id']] = {'result': None, 'name': test['name']}
            if test['name'] == CASE:
                need(self.named is None, 'reporter-duplicate-case')
                self.named = test['id']
        elif kind in ('print', 'error', 'testDone'):
            test_id = event.get('testID')
            need(integer(test_id) and test_id in self.tests, 'reporter-test-id')
            test = self.tests[test_id]
            need(test['result'] is None, 'reporter-ended-test')
            if kind == 'error':
                need(type(event.get('error')) is str and type(event.get('isFailure')) is bool,
                     'reporter-error')
                # Drop all error text and stacks immediately; retain only classification.
                self.errors.append((test_id, event['isFailure'],
                                    ASSERTION in (line.strip() for line in event['error'].splitlines()),
                                    self.oracle is not None))
                need(len(self.errors) <= 8, 'reporter-error-bound')
            elif kind == 'print':
                need(type(event.get('message')) is str, 'reporter-print')
                need(TAG not in event['message'], 'oracle-ambiguous-channel')
            elif kind == 'testDone':
                need(event.get('result') in ('success', 'failure', 'error') and
                     type(event.get('skipped')) is bool and type(event.get('hidden')) is bool,
                     'reporter-test-result')
                need(not event['skipped'], 'reporter-skipped')
                test['result'] = event['result']
        elif kind == 'done':
            need(type(event.get('success')) is bool, 'reporter-done')
            self.done = event['success']
        else:
            raise Hold('reporter-event-type')

    def classify(self, exit_code, old=False):
        need(self.closed and self.started and self.named is not None and
             self.done is not None and self.oracle is not None, 'incomplete-reporter')
        need(all(test['result'] is not None for test in self.tests.values()),
             'incomplete-tests')
        value = self.oracle
        # Validate observations before evaluating late-currentness flags or assertions.
        old_accounts = value['oldAccounts']
        accepted = value['acceptedAccounts']
        need([a['id'] for a in old_accounts] == ['openai-local'] and
             [a['id'] for a in accepted] == ['openai-local', 'cursor-local'],
             'causal-account-order')
        need(old_accounts[0] == accepted[0] and accepted[0]['status'] == 'ok' and
             accepted[0]['spent'] == 900 and accepted[0]['allowances'] == [], 'causal-healthy-b')
        need(accepted[1]['status'] == 'ok' and any(
            w['id'] == 'cursor-plan' and w['usedPercent'] == 20
            for w in accepted[1]['allowances']), 'causal-healthy-a')
        pubs, redraws = value['publications'], value['redraws']
        first = pubs[0]
        need(first['row_count'] == 2 and first['row_0_kind'] == 'allowance' and
             first['row_0_family'] == 'Cursor' and
             first['row_0_percent'] == '80% left' and first['row_1_family'] == 'OpenAI' and
             first['row_1_kind'] == 'budget' and first['row_1_spent_minor'] == '900' and
             first['row_1_spent_currency'] == 'USD' and first['stale'] == '0' and
             first['empty'] == '0' and redraws[0] == first, 'causal-accepted-publication')
        projection = {
            'oldAccounts': old_accounts, 'acceptedAccounts': accepted,
            'lateOutcome': value['lateOutcome'], 'completedAbsentReads': value['completedAbsentReads'],
            'lateCurrent': value['lateCurrent'], 'latePublished': value['latePublished'],
            'publications': [payload_projection(p) for p in pubs],
            'redraws': [payload_projection(p) for p in redraws],
            'visible': payload_projection(value['visible']),
        }
        need(value['lateOutcome'] == 'completed' and value['completedAbsentReads'] == 1,
             'causal-early-validity')
        other_results = [t['result'] for key, t in self.tests.items() if key != self.named]
        need(all(result == 'success' for result in other_results), 'unrelated-test-failure')
        if old:
            late = pubs[-1]
            need(len(pubs) == len(redraws) == 2 and redraws == pubs and
                 value['visible'] == late and late['row_count'] == 1 and
                 late['row_0_family'] == 'OpenAI' and late['row_0_spent_minor'] == '900' and
                 late['stale'] == '0' and late['empty'] == '0' and
                 value['lateCurrent'] is True and value['latePublished'] is True,
                 'old-not-late-b-only')
            need(all(late[f'row_0_{field}'] == first[f'row_1_{field}'] for field in ROW_FIELDS),
                 'old-healthy-b-payload-changed')
            # All cleared trailing rows are part of the real receiver/readback proof.
            need(all(late[f'row_{i}_{field}'] == '' for i in range(1, 6)
                     for field in ROW_FIELDS), 'old-trailing-rows')
            need(exit_code == 1 and self.done is False and
                 self.tests[self.named]['result'] == 'failure' and
                 self.errors == [(self.named, True, True, True)], 'old-not-semantic-red')
            projection['classification'] = 'OLD-named-semantic1'
        else:
            need(pubs == redraws == [first] and value['visible'] == first and
                 value['lateCurrent'] is False and value['latePublished'] is False,
                 'final-not-preserved')
            need(exit_code == 0 and self.done is True and not self.errors and
                 self.tests[self.named]['result'] == 'success', 'final-not-success')
            projection['classification'] = 'FINAL0'
        need(len(encoded(projection)) <= MAX_LINE, 'retained-evidence-bound')
        return projection


def process_identity(pid):
    """Linux PID/start identity, with parent/session information for scoped ownership."""
    raw = proc_bytes(Path(f'/proc/{pid}/stat'), MAX_LINE)
    fields = raw[raw.rfind(b')') + 2:].split()
    need(len(fields) >= 20, 'proc-stat')
    return {'pid': int(pid), 'start': int(fields[19]), 'parent': int(fields[1]),
            'group': int(fields[2]), 'session': int(fields[3]), 'state': fields[0].decode('ascii')}


def proc_bytes(path, limit):
    with path.open('rb') as stream:
        data = stream.read(limit + 1)
    need(len(data) <= limit, 'proc-input-bound')
    return data


def same_process(left, right):
    return (left['pid'], left['start']) == (right['pid'], right['start'])


def alive(record, observe=process_identity):
    try:
        current = observe(record['pid'])
    except FileNotFoundError:
        return False
    need(same_process(current, record), 'pid-reuse')
    return current['state'] not in ('Z', 'X')


def signal_process(record, sig, observe=process_identity, open_pid=os.pidfd_open,
                   send=signal.pidfd_send_signal):
    """A PID may be reused between inspection and signaling; pin the target first."""
    try:
        fd = open_pid(record['pid'], 0)
    except ProcessLookupError:
        return
    try:
        try:
            need(same_process(observe(record['pid']), record), 'pid-reuse')
            send(fd, sig)
        except (FileNotFoundError, ProcessLookupError):
            pass
    finally:
        os.close(fd)


def proc_members():
    members = {}
    for entry in Path('/proc').iterdir():
        if not entry.name.isdecimal():
            continue
        need(len(members) < 32768, 'proc-census-bound')
        try:
            if entry.stat().st_uid == os.getuid():
                members[int(entry.name)] = process_identity(int(entry.name))
        except (FileNotFoundError, PermissionError):
            continue
    return members


def become_subreaper():
    # Orphaned owned descendants remain observable even after double-fork/setsid.
    import ctypes
    libc = ctypes.CDLL(None, use_errno=True)
    need(libc.prctl(36, 1, 0, 0, 0) == 0, 'subreaper-unavailable')  # PR_SET_CHILD_SUBREAPER


def class_directory_identity(path):
    info = path.lstat()
    need(stat.S_ISDIR(info.st_mode) and info.st_uid == os.getuid(), 'java-output-identity')
    # javac legitimately adds package subdirectories, changing a directory's link count.
    return [*identity(info)[:4], stat.S_IMODE(info.st_mode)]


class Processes:
    """Owned sessions only; observations are injectable without launching Flutter."""

    def __init__(self, source, runtime, ffi_seal, observe=process_identity, census=proc_members,
                 journal=None, execution=None):
        self.source = Path(source)
        self.runtime = runtime
        self.ffi = ffi_seal
        self.observe = observe
        self.census = census
        self.known = {}
        self.session = None
        self.child = None
        self.launch_pending = False
        self.javac = {}
        self.java = {}
        self.mapping = None
        self.journal = journal
        self.execution = execution or self.read_execution

    def read_execution(self, pid):
        root = Path(f'/proc/{pid}')
        exe = Path(os.readlink(root / 'exe')).resolve(strict=True)
        raw = proc_bytes(root / 'cmdline', MAX_LINE)
        args = [os.fsdecode(a) for a in raw.rstrip(b'\0').split(b'\0')]
        maps = proc_bytes(root / 'maps', MAX_STREAM) if exe == self.runtime['tester'] else b''
        return exe, args, maps

    def remember(self, record):
        need(len(self.known) < 64, 'owned-process-bound')
        self.known[record['pid']] = record
        if self.journal is not None and not self.journal.failed:
            self.journal.append('owned-process', identity={k: record[k] for k in
                                ('pid', 'start', 'parent', 'group', 'session')})

    def discover(self):
        need(not self.launch_pending, 'launch-ownership-unproven')
        members = self.census()
        for pid, known in self.known.items():
            if pid not in members:
                try:
                    members[pid] = self.observe(pid)
                except FileNotFoundError:
                    continue
                except PermissionError:
                    raise Hold('owned-process-unreadable') from None
            if pid in members:
                need(same_process(members[pid], known), 'pid-reuse')
        changed = True
        while changed:
            changed = False
            for pid, record in members.items():
                if pid not in self.known and (
                        (self.session is not None and record['session'] == self.session) or
                        record['parent'] in self.known or
                        (self.session is not None and record['parent'] == os.getpid())):
                    self.remember(record)
                    changed = True
        return members

    def observe_execution(self):
        members = self.discover()
        for pid, record in list(self.known.items()):
            if pid not in members or members[pid]['state'] in ('Z', 'X'):
                continue
            try:
                exe, args, maps = self.execution(pid)
                after = self.observe(pid)
                need(same_process(record, after), 'pid-reuse')
                if exe == self.runtime['javac'] and len(args) == 5 and args[1] == '-d':
                    need(Path(args[3]).resolve() == self.source / OWNERS[-1] and
                         Path(args[4]).resolve() == self.source / BRIDGE, 'javac-inputs')
                    output = Path(args[2]).resolve(strict=True)
                    need(not output.is_relative_to(self.source), 'java-output-in-source')
                    key = (pid, record['start'])
                    directory_identity = class_directory_identity(output)
                    if key in self.javac:
                        need(self.javac[key]['directoryIdentity'] == directory_identity,
                             'java-output-replaced')
                    self.javac[key] = {'output': output, 'identity': record,
                                       'directoryIdentity': directory_identity}
                if exe == self.runtime['java'] and len(args) == 4 and args[1] == '-cp' and \
                        args[3] == 'app.wardpulse.watchsync.ConnectionCacheEngineBridge':
                    output = Path(args[2]).resolve(strict=True)
                    matches = [v for v in self.javac.values() if v['output'] == output]
                    need(len(matches) == 1, 'java-without-owned-javac')
                    need(class_directory_identity(output) == matches[0]['directoryIdentity'],
                         'java-output-replaced')
                    compiler = matches[0]['identity']
                    need(not alive(compiler, self.observe), 'java-before-compiler-retired')
                    key = (pid, record['start'])
                    classes = self.java[key]['classes'] if key in self.java else self.classes(output)
                    self.java[key] = {'output': output, 'identity': record, 'classes': classes}
                if exe == self.runtime['tester']:
                    ffi = self.source / FFI
                    for line in maps.decode('utf-8', errors='strict').splitlines():
                        fields = line.split(maxsplit=5)
                        if len(fields) != 6 or fields[5] != str(ffi):
                            continue
                        major, minor = (int(x, 16) for x in fields[3].split(':'))
                        device, inode = self.ffi['identity'][:2]
                        need(int(fields[4]) == inode and os.makedev(major, minor) == device,
                             'ffi-mapping-identity')
                        need(self.mapping is None or same_process(self.mapping, record),
                             'ffi-mapping-ambiguous')
                        self.mapping = record
                need(same_process(self.observe(pid), record), 'pid-reuse')
            except FileNotFoundError:
                # A missed short-lived process supplies no positive execution witness.
                continue
            except (PermissionError, UnicodeError):
                raise Hold('owned-process-unreadable') from None

    def classes(self, directory):
        info = directory.lstat()
        need(stat.S_ISDIR(info.st_mode) and info.st_uid == os.getuid(), 'java-output-identity')
        result = {}
        for path in sorted(directory.rglob('*.class')):
            data, details = read_regular(path)
            need(details.st_uid == os.getuid() and details.st_mtime_ns >= self.started_ns and
                 data.startswith(b'\xca\xfe\xba\xbe'), 'java-class-qualification')
            result[str(path.relative_to(directory))] = digest(data)
            need(len(result) <= 64, 'java-class-bound')
        need(ENGINE_CLASS in result and BRIDGE_CLASS in result, 'java-class-missing')
        return result

    def readers_retired(self):
        members = self.discover()
        need(not any(pid in members and members[pid]['state'] not in ('Z', 'X')
                     for pid in self.known), 'owned-readers-live')
        # Do not signal foreign readers. Inaccessible *known* readers hold, as above;
        # unrelated inaccessible processes establish no in-scope ownership.
        for pid, record in members.items():
            if pid == os.getpid() or record['state'] in ('Z', 'X'):
                continue
            root = Path(f'/proc/{pid}')
            try:
                links = list((root / 'fd').iterdir())
                need(len(links) <= 8192, 'reader-fd-bound')
                for fd in links:
                    try:
                        target = os.readlink(fd).removesuffix(' (deleted)')
                    except FileNotFoundError:
                        continue
                    need(not target.startswith(str(self.source) + '/'), 'foreign-source-reader')
                maps = proc_bytes(root / 'maps', MAX_STREAM)
                need(str(self.source).encode() + b'/' not in maps, 'foreign-source-reader')
                need(same_process(self.observe(pid), record), 'reader-identity-race')
            except FileNotFoundError:
                continue
            except PermissionError:
                need(pid not in self.known, 'owned-process-unreadable')

    def signal_owned(self, sig):
        members = self.discover()
        for pid, record in self.known.items():
            if pid not in members or members[pid]['state'] in ('Z', 'X'):
                continue
            signal_process(record, sig, self.observe)

    def retire(self):
        if self.child is None:
            self.readers_retired()
            return
        self.signal_owned(signal.SIGTERM)
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            self.child.poll()
            members = self.discover()
            if not any(pid in members and members[pid]['state'] not in ('Z', 'X')
                       for pid in self.known):
                break
            time.sleep(0.01)
        else:
            self.signal_owned(signal.SIGKILL)
            kill_deadline = time.monotonic() + 2
            while time.monotonic() < kill_deadline:
                self.child.poll()
                members = self.discover()
                if not any(pid in members and members[pid]['state'] not in ('Z', 'X')
                           for pid in self.known):
                    break
                time.sleep(0.01)
        try:
            self.child.wait(timeout=2)
        except subprocess.TimeoutExpired:
            raise Hold('owned-process-retirement') from None
        for pid, known in self.known.items():
            if pid == self.child.pid:
                continue
            try:
                current = self.observe(pid)
                need(same_process(current, known), 'pid-reuse')
                if current['parent'] == os.getpid() and current['state'] == 'Z':
                    os.waitpid(pid, os.WNOHANG)
            except (FileNotFoundError, ChildProcessError):
                continue
        self.readers_retired()

    def run(self, command, cwd, environment, old=False):
        self.readers_retired()
        self.known = {}
        self.session = None
        self.child = None
        self.javac, self.java, self.mapping = {}, {}, None
        self.started_ns = time.time_ns()
        reporter = Reporter()
        selector = None
        stderr_bytes = 0
        deadline = time.monotonic() + 60
        try:
            # An interrupted launch may have created readers before returning a handle.
            # Hold transitions unless the new session's root identity was captured.
            self.launch_pending = True
            self.child = subprocess.Popen(command, cwd=cwd, env=environment,
                                          stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                          stderr=subprocess.PIPE, start_new_session=True)
            self.session = self.child.pid
            root = self.observe(self.child.pid)
            need(root['session'] == root['pid'] and root['group'] == root['pid'], 'process-session')
            self.remember(root)
            self.launch_pending = False
            selector = selectors.DefaultSelector()
            for stream in (self.child.stdout, self.child.stderr):
                os.set_blocking(stream.fileno(), False)
                selector.register(stream, selectors.EVENT_READ)
            while selector.get_map() or self.child.poll() is None:
                need(time.monotonic() < deadline, 'leg-timeout')
                self.observe_execution()
                for key, _ in selector.select(timeout=min(0.01, max(0, deadline - time.monotonic()))):
                    block = os.read(key.fileobj.fileno(), 16384)
                    if not block:
                        selector.unregister(key.fileobj)
                    elif key.fileobj is self.child.stdout:
                        reporter.feed(block)
                    else:
                        stderr_bytes += len(block)
                        need(stderr_bytes <= MAX_STREAM, 'stderr-bound')
            reporter.feed(b'', final=True)
            self.retire()
            need(len(self.javac) == len(self.java) == 1 and self.mapping is not None,
                 'missing-java-or-ffi-witness')
            projection = reporter.classify(self.child.returncode, old)
            projection['execution'] = {
                'javac': [{k: r[k] for k in ('pid', 'start')} for r in
                          (v['identity'] for v in self.javac.values())],
                'java': [{k: r[k] for k in ('pid', 'start')} for r in
                         (v['identity'] for v in self.java.values())],
                'classes': next(iter(self.java.values()))['classes'],
                'ffiReader': {k: self.mapping[k] for k in ('pid', 'start')},
                'ffiSha256': self.ffi['sha256'], 'retired': True,
            }
            return projection
        finally:
            try:
                self.retire()
                drain_deadline = time.monotonic() + 1
                drained = 0
                while selector is not None and selector.get_map():
                    need(time.monotonic() < drain_deadline, 'pipe-drain-timeout')
                    for key, _ in selector.select(timeout=0.01):
                        block = os.read(key.fileobj.fileno(), 16384)
                        if not block:
                            selector.unregister(key.fileobj)
                        drained += len(block)
                        need(drained <= MAX_STREAM, 'pipe-drain-bound')
            finally:
                if selector is not None:
                    selector.close()
                if self.child is not None:
                    self.child.stdout.close()
                    self.child.stderr.close()


class Git:
    def __init__(self, source, executable):
        self.source = Path(source)
        self.executable = str(executable)
        self.processes = Processes(self.source, {}, {})
        self.env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
        self.env.update(GIT_OPTIONAL_LOCKS='0', GIT_NO_REPLACE_OBJECTS='1',
                        GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null',
                        GIT_TERMINAL_PROMPT='0', LC_ALL='C')

    def run(self, *args):
        command = [self.executable, '--no-pager', '-c', 'core.fsmonitor=false',
                   '-c', 'core.untrackedCache=false', '-c', 'core.hooksPath=/dev/null', *args]
        processes = self.processes
        processes.readers_retired()
        processes.known, processes.session, processes.child = {}, None, None
        selector = None
        output = bytearray()
        total = 0
        deadline = time.monotonic() + 15
        try:
            processes.launch_pending = True
            processes.child = subprocess.Popen(
                command, cwd=self.source, env=self.env, stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
            child = processes.child
            processes.session = child.pid
            owner = processes.observe(child.pid)
            need(owner['session'] == owner['group'] == child.pid, 'git-process-ownership')
            processes.remember(owner)
            processes.launch_pending = False
            selector = selectors.DefaultSelector()
            for stream in (child.stdout, child.stderr):
                os.set_blocking(stream.fileno(), False)
                selector.register(stream, selectors.EVENT_READ)
            while selector.get_map() or child.poll() is None:
                need(time.monotonic() < deadline, 'git-timeout')
                processes.discover()
                for key, _ in selector.select(timeout=0.01):
                    block = os.read(key.fileobj.fileno(), 65536)
                    if not block:
                        selector.unregister(key.fileobj)
                    total += len(block)
                    need(total <= 32 * 1024 * 1024, 'git-output-bound')
                    if key.fileobj is child.stdout:
                        output.extend(block)
            child.wait(timeout=max(0.001, deadline - time.monotonic()))
        finally:
            try:
                processes.retire()
            finally:
                try:
                    if selector is not None:
                        selector.close()
                finally:
                    if processes.child is not None:
                        try:
                            processes.child.stdout.close()
                        finally:
                            processes.child.stderr.close()
        need(child.returncode == 0, 'git-metadata')
        return bytes(output)

    def snapshot(self):
        return {
            'head': self.run('rev-parse', '--verify', 'HEAD').strip().decode('ascii'),
            'headFile': file_seal(self.source / '.git/HEAD'),
            'refs': self.run('for-each-ref', '--format=%(refname) %(objectname) %(symref)'),
            'index': read_regular(self.source / '.git/index')[0],
            'indexIdentity': file_seal(self.source / '.git/index'),
            'logical': self.run('ls-files', '--stage', '-z'),
            'metadata': {name: tree_seal(self.source / name) if (self.source / name).exists()
                         else None for name in ('.git/config', '.git/info', '.git/packed-refs',
                                                '.git/objects/info', '.git/config.worktree',
                                                '.git/commondir')},
        }

    def blob(self, commit, path):
        row = self.run('ls-tree', '-z', commit, '--', path).rstrip(b'\0')
        need(row.count(b'\t') == 1, 'git-blob-membership')
        details, name = row.split(b'\t')
        mode, kind, oid = details.split()
        need(name.decode() == path and kind == b'blob' and mode in (b'100644', b'100755'),
             'git-blob-mode')
        data = self.run('cat-file', 'blob', oid.decode())
        need(len(data) <= MAX_FILE, 'git-blob-bound')
        need(hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest() == oid.decode(),
             'git-blob-identity')
        return data, (0o755 if mode == b'100755' else 0o644), oid.decode()


def tracked_manifest(source, git):
    paths = git.run('ls-files', '-z').split(b'\0')[:-1]
    need(len(paths) == len(set(paths)) and len(paths) <= 50000, 'tracked-membership')
    result = {os.fsdecode(p): tree_seal(source / os.fsdecode(p)) for p in paths}
    directories = set()
    for name in result:
        directory = (source / name).parent
        while directory != source:
            directories.add(directory)
            directory = directory.parent
    for directory in sorted(directories):
        info = directory.lstat()
        need(stat.S_ISDIR(info.st_mode), 'source-directory-link')
        result[str(directory.relative_to(source)) + '/'] = {
            'identity': list(identity(info)), 'mode': stat.S_IMODE(info.st_mode)}
    return result


def dependency_graph(source):
    """Resolve local import/export/part edges; external package inputs are sealed separately."""
    pending = [str(TEST), *(path for path in OWNERS if path.endswith('.dart'))]
    seen = set()
    pattern = re.compile(r'^[ \t]*(?:import|export|part)\s+(.*?);', re.MULTILINE | re.DOTALL)
    while pending:
        relative = pending.pop()
        if relative in seen:
            continue
        need(len(seen) <= 2000, 'import-graph-bound')
        seen.add(relative)
        data, _ = read_regular(source / relative)
        uris = [uri for directive in pattern.findall(data.decode('utf-8'))
                for uri in re.findall(r"['\"]([^'\"]+)['\"]", directive)]
        for uri in uris:
            if uri.startswith('dart:'):
                continue
            if uri.startswith('package:ward_pulse_phone/'):
                path = source / PHONE / 'lib' / uri.split('/', 1)[1]
            elif uri.startswith('package:ward_pulse_bindings/'):
                path = source / 'bindings/dart/lib' / uri.split('/', 1)[1]
            elif uri.startswith('package:ward_pulse_watch_sync/'):
                path = source / PHONE / 'plugins/ward_pulse_watch_sync/lib' / uri.split('/', 1)[1]
            elif uri.startswith('package:'):
                continue
            else:
                need(':' not in uri and not uri.startswith('/'), 'import-uri')
                path = source / Path(relative).parent / uri
            path = path.resolve(strict=True)
            need(path.is_relative_to(source), 'import-outside-source')
            pending.append(str(path.relative_to(source)))
    seen.update((OWNERS[-1], BRIDGE))
    return sorted(seen)


def production_paths(graph):
    return [path for path in graph if not path.startswith(str(PHONE / 'test') + '/') and path != BRIDGE]


def external_packages(source):
    config = strict_json(read_regular(source / PACKAGE_CONFIG)[0], MAX_FILE)
    need(type(config) is dict and config.get('configVersion') == 2 and
         type(config.get('packages')) is list, 'package-config')
    result = set()
    names = set()
    local_packages = {'ward_pulse_phone': source / PHONE,
                      'ward_pulse_bindings': source / 'bindings/dart',
                      'ward_pulse_watch_sync': source / PHONE / 'plugins/ward_pulse_watch_sync'}
    for item in config['packages']:
        need(type(item) is dict and type(item.get('name')) is str and
             item['name'] not in names and type(item.get('rootUri')) is str,
             'package-config-entry')
        names.add(item['name'])
        url = urlparse(urljoin((source / PACKAGE_CONFIG).as_uri(), item['rootUri']))
        need(url.scheme == 'file' and not url.netloc and not url.query and not url.fragment,
             'package-root')
        root = Path(unquote(url.path)).resolve(strict=True)
        if item['name'] in local_packages:
            need(root == local_packages[item['name']] and item.get('packageUri') == 'lib/',
                 'local-package-binding')
        else:
            result.add(root)
    need(set(local_packages) <= names, 'missing-local-package')
    return result


def qualified_record(path, expected=None):
    data, info = read_regular(path)
    seal = {'identity': list(identity(info)), 'mode': stat.S_IMODE(info.st_mode),
            'size': len(data), 'sha256': digest(data)}
    if expected is not None:
        need(digest(encoded(seal)) == expected, 'metadata-seal')
    value = strict_json(data, MAX_FILE)
    return value, seal


class Release:
    """Validate a fresh Root-admitted envelope and its independently linked records."""

    def __init__(self, source, receipt, final, controller, now_ns=time.time_ns):
        self.source = source
        self.receipt = Path(receipt).absolute()
        need(self.receipt.resolve(strict=True) == self.receipt and
             not self.receipt.is_relative_to(source), 'receipt-in-source')
        self.value, receipt_seal = qualified_record(self.receipt)
        self.metadata = {self.receipt: receipt_seal}
        value = self.value
        need(type(value) is dict and value.get('format') == 'original19-release-v1' and
             value.get('admittedBy') == 'Root' and value.get('final') == final,
             'release-admission')
        need(value.get('source') == str(SOURCE) == str(source) and
             value.get('sourceIdentity') == list(identity(source.lstat())), 'canonical-source')
        run = value.get('runId')
        need(type(run) is str and re.fullmatch(r'[a-zA-Z0-9-]{1,80}', run), 'release-run')
        links = value.get('records')
        need(type(links) is dict and set(links) == {'done', 'cli', 'retirement', 'idle'},
             'release-records')
        records = {}
        for kind, link in links.items():
            need(type(link) is dict and set(link) == {'path', 'sealSha256'} and
                 type(link['path']) is str and Path(link['path']).is_absolute(), 'release-link')
            path = Path(link['path'])
            need(path.resolve(strict=True) == path and path not in self.metadata and
                 not path.is_relative_to(source), 'release-link-identity')
            record, seal = qualified_record(path, link['sealSha256'])
            need(type(record) is dict and record.get('runId') == run and
                 record.get('kind') == kind and integer(record.get('observedNs')),
                 'release-record-binding')
            records[kind] = record
            self.metadata[path] = seal
        done, cli, retirement, idle = (records[k] for k in ('done', 'cli', 'retirement', 'idle'))
        need(done.get('status') == 'DONE' and done.get('head') == final, 'whole-done')
        need(type(cli.get('used')) is bool, 'cli-evidence')
        if cli['used']:
            need(cli.get('actualExit') is True and integer(cli.get('exitCode')) and
                 cli['exitCode'] == 0, 'cli-not-exited')
        else:
            need(cli.get('identity') is None and cli.get('exitCode') is None, 'cli-unused')
        identities = retirement.get('identities')
        need(type(identities) is list and len(identities) > 0 and
             retirement.get('scope') == run and retirement.get('remaining') == [] and
             retirement.get('unresolved') == [], 'retirement-evidence')
        seen = set()
        boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
        for record in identities:
            need(type(record) is dict and set(record) == {'pid', 'start', 'bootId'} and
                 integer(record['pid']) and record['pid'] > 0 and integer(record['start']) and
                 record['start'] > 0 and record['bootId'] == boot, 'retirement-identity')
            key = (record['pid'], record['start'])
            need(key not in seen, 'retirement-duplicate')
            seen.add(key)
            try:
                current = process_identity(record['pid'])
                need(not same_process(record, current) or current['state'] in ('Z', 'X'),
                     'released-process-live')
            except FileNotFoundError:
                pass
        if cli['used']:
            need(cli.get('identity') in identities, 'cli-retirement-link')
        need(idle.get('public') is True and idle.get('status') == 'idle' and
             idle.get('lease') is None and idle.get('processes') == [], 'fresh-public-idle')
        need(done['observedNs'] <= cli['observedNs'] <= retirement['observedNs'] <
             idle['observedNs'] < controller['startedNs'] <= now_ns() and
             now_ns() - idle['observedNs'] <= 300 * 10**9, 'release-order-or-freshness')
        metadata = value.get('metadata')
        need(type(metadata) is list and len(metadata) > 0, 'pinned-metadata')
        for item in metadata:
            need(type(item) is dict and set(item) == {'path', 'sealSha256'} and
                 type(item['path']) is str and Path(item['path']).is_absolute(), 'metadata-entry')
            path = Path(item['path'])
            need(path.resolve(strict=True) == path and path not in self.metadata, 'metadata-duplicate')
            seal = file_seal(path)
            need(digest(encoded(seal)) == item['sealSha256'], 'metadata-seal')
            self.metadata[path] = seal

    def verify(self):
        need(all(file_seal(path) == seal for path, seal in self.metadata.items()),
             'metadata-changed')


class Runtime:
    def __init__(self, source, release):
        value = release.value.get('runtime')
        need(type(value) is dict and value.get('versions') ==
             {'flutter': '3.44.6', 'dart': '3.12.2'}, 'runtime-versions')
        paths = value.get('executables')
        need(type(paths) is dict and set(paths) ==
             {'flutter', 'dart', 'tester', 'java', 'javac', 'python', 'git'}, 'runtime-executables')
        self.executables = {}
        for key, name in paths.items():
            need(type(name) is str and Path(name).is_absolute(), 'runtime-path')
            path = Path(name)
            need(path.resolve(strict=True) == path and path.is_file() and os.access(path, os.X_OK),
                 'runtime-executable-identity')
            self.executables[key] = path
        sdk = (source / '.toolchains/flutter').resolve(strict=True)
        need(self.executables['flutter'] == sdk / 'bin/flutter' and
             self.executables['dart'] == sdk / 'bin/cache/dart-sdk/bin/dart' and
             self.executables['tester'] == sdk / 'bin/cache/artifacts/engine/linux-x64/flutter_tester' and
             self.executables['python'] == Path(sys.executable).resolve() ==
             Path(os.readlink('/proc/self/exe')).resolve(), 'pinned-runtime-paths')
        version = strict_json(read_regular(sdk / 'bin/cache/flutter.version.json')[0])
        need(version.get('frameworkVersion') == '3.44.6' and
             read_regular(sdk / 'bin/cache/dart-sdk/version')[0].strip() == b'3.12.2',
             'pinned-runtime-version-inputs')
        self.bookkeeping = sdk_bookkeeping(sdk)
        admitted = value.get('inputs')
        need(type(admitted) is list and 0 < len(admitted) <= 512, 'runtime-inputs')
        self.inputs = {}
        for item in admitted:
            need(type(item) is dict and set(item) == {'path', 'sealSha256'} and
                 type(item['path']) is str and Path(item['path']).is_absolute(), 'runtime-input')
            path = Path(item['path'])
            need(path not in self.inputs and path.resolve(strict=True) == path, 'runtime-input-identity')
            seal = runtime_seal(path, self.bookkeeping)
            need(digest(encoded(seal)) == item['sealSha256'], 'runtime-input-seal')
            self.inputs[path] = seal
        required = external_packages(source) | {sdk, source / PACKAGE_CONFIG,
                                               source / FFI, *self.executables.values()}
        def targets(path, seal):
            if 'link' in seal:
                required.add(path.resolve(strict=True))
            for name, child in seal.get('entries', {}).items():
                targets(path / name, child)
        for path, seal in self.inputs.items():
            targets(path, seal)
        for path in required:
            need(any(path == root or (path.is_relative_to(root) and 'entries' in seal)
                     for root, seal in self.inputs.items()), 'unsealed-runtime-input')
        self.ffi = file_seal(source / FFI)
        need(value.get('ffiSha256') == self.ffi['sha256'], 'ffi-release-binding')

    def verify(self):
        need(all(runtime_seal(path, self.bookkeeping) == seal for path, seal in self.inputs.items()),
             'runtime-changed')

    def environment(self):
        paths = [self.executables[k].parent for k in ('flutter', 'java', 'javac', 'python', 'git')]
        env = {k: v for k, v in os.environ.items() if k in
               ('HOME', 'USER', 'LOGNAME', 'LANG', 'PUB_CACHE', 'TMPDIR', 'XDG_CACHE_HOME')}
        env.update(PATH=os.pathsep.join(dict.fromkeys(map(str, [*paths, Path('/usr/bin'), Path('/bin')]))),
                   LD_LIBRARY_PATH=str(SOURCE / FFI.parent), GIT_OPTIONAL_LOCKS='0',
                   FLUTTER_SUPPRESS_ANALYTICS='true', DART_SUPPRESS_ANALYTICS='true', CI='true')
        return env


def controller_identity(script):
    record = process_identity(os.getpid())
    boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    boot_epoch = time.time_ns() - int(time.clock_gettime(time.CLOCK_BOOTTIME) * 10**9)
    started = boot_epoch + record['start'] * 10**9 // os.sysconf('SC_CLK_TCK')
    return {'pid': record['pid'], 'start': record['start'], 'bootId': boot,
            'startedNs': started, 'script': file_seal(script),
            'executable': file_seal(Path(os.readlink('/proc/self/exe')))}


def persist(path, value, limit=32 * 1024 * 1024, directory_identity=None):
    path = Path(path)
    data = encoded(value) + b'\n'
    need(len(data) <= limit, 'evidence-bound')
    directory = open_directory(path.parent, directory_identity)
    fd = None
    try:
        fd = os.open(path.name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                     0o600, dir_fd=directory)
        offset = 0
        while offset < len(data):
            count = os.write(fd, data[offset:])
            need(count > 0, 'evidence-write')
            offset += count
        os.fsync(fd)
        need(identity(path.parent.lstat()) == identity(os.fstat(directory)) and
             path.parent.resolve(strict=True) == path.parent, 'evidence-directory-replaced')
        os.fsync(directory)
    finally:
        if fd is not None:
            os.close(fd)
        os.close(directory)


class Replay:
    """Linear orchestration with only transition, process and observation boundaries injected."""

    def __init__(self, custody, verify, leg, retire, journal):
        self.custody, self.verify, self.leg = custody, verify, leg
        self.retire, self.journal = retire, journal
        self.legs = []

    def same_final_observations(self):
        first, current = self.legs[0], self.legs[-1]
        need(current['oldAccounts'] == first['oldAccounts'] and
             current['acceptedAccounts'] == first['acceptedAccounts'] and
             current['publications'][0] == first['publications'][0], 'same-final-observations-changed')

    def run(self, old_blobs):
        self.verify(False)
        self.legs.append(self.leg(False))
        self.journal.append('final0', proof=self.legs[-1])
        self.retire()
        self.verify(False)
        self.custody.substitute(old_blobs)
        self.verify(True)
        self.legs.append(self.leg(True))
        self.same_final_observations()
        self.journal.append('old-semantic1', proof=self.legs[-1])
        self.retire()
        self.verify(True)
        self.custody.restore()
        self.verify(False)
        self.legs.append(self.leg(False))
        self.same_final_observations()
        self.legs[-1]['classification'] = 'restored-FINAL0'
        self.journal.append('restored-final0', proof=self.legs[-1])
        self.retire()
        self.verify(False)
        self.custody.release()

    def contain(self):
        # No restoration writes before the durable attempted-substitution boundary.
        self.retire()
        self.custody.restore()
        self.verify(False)
        self.custody.release()


def host_replay(final, receipt, output):
    need(re.fullmatch(r'[0-9a-f]{40}', final) is not None, 'final-object-id')
    source = SOURCE
    script = source / 'tools/test-phone-cache/replay_original19.py'
    need(source.resolve(strict=True) == source and Path.cwd() == source and
         Path(__file__).absolute() == script and script.resolve(strict=True) == script,
         'canonical-controller')
    controller = controller_identity(script)
    release = Release(source, receipt, final, controller)
    runtime = Runtime(source, release)
    become_subreaper()
    git = Git(source, runtime.executables['git'])
    need((source / '.git').is_dir() and (source / '.git').resolve() == source / '.git',
         'canonical-git-directory')
    output, output_identity = create_output(output, source)
    journal = Journal(output, directory_identity=output_identity)
    processes = Processes(source, runtime.executables, runtime.ffi, journal=journal)
    def readers_retired():
        git.processes.readers_retired()
        processes.readers_retired()
    def retire():
        try:
            processes.retire()
        finally:
            git.processes.retire()
    custody = Custody(source / '.git/index.lock', journal, readers_retired)
    replay = None
    sealed = False
    held = False
    outcome = {'status': 'held', 'failure': 'incomplete', 'custodyHeld': False, 'legs': []}
    try:
        custody.acquire()
        held = True
        journal.append('lock-acquired', identity=list(identity(custody.owner)))
        need(git.run('rev-parse', '--show-toplevel').strip().decode() == str(source) and
             git.run('rev-parse', '--path-format=absolute', '--git-common-dir').strip().decode() ==
             str(source / '.git'), 'canonical-git-binding')
        baseline = git.snapshot()
        need(baseline['head'] == final and not git.run(
            'status', '--porcelain=v1', '-z', '--untracked-files=normal', '--ignore-submodules=none'),
            'final-not-released-clean-head')
        need(release.value.get('indexSha256') == digest(baseline['index']) and
             release.value.get('refsSha256') == digest(baseline['refs']) and
             release.value.get('logicalIndexSha256') == digest(baseline['logical']),
             'released-git-binding')
        source_identity = list(identity(source.lstat()))
        manifest = tracked_manifest(source, git)
        graph = dependency_graph(source)
        need(all(path in manifest for path in graph), 'unsealed-local-import')
        need(release.value.get('graphSha256') == digest(encoded(graph)), 'released-graph-binding')
        changed = git.run('diff', '--no-ext-diff', '--no-textconv', '--name-only', '-z',
                          OLD, final, '--', *production_paths(graph)).split(b'\0')[:-1]
        need(set(map(os.fsdecode, changed)) == set(OWNERS), 'eight-owner-closure')
        need(all(path in graph for path in OWNERS), 'incomplete-causal-graph')
        old_blobs, old_manifest, restoration = [], {}, []
        for path in OWNERS:
            handle = StableFile(source / path)
            custody.files.append(handle)
            data, mode, oid = git.blob(final, path)
            need(handle.final == data and bool(handle.mode & 0o111) == bool(mode & 0o111),
                 'final-blob-binding')
            old_data, old_mode, old_oid = git.blob(OLD, path)
            old_blobs.append((old_data, old_mode))
            old_manifest[path] = {'blob': old_oid, 'sha256': digest(old_data), 'mode': old_mode}
            restoration.append({'path': path, 'blob': oid, 'sha256': digest(data),
                                'gitMode': mode, 'filesystemMode': handle.mode,
                                'identity': list(identity(handle.initial))})
        need(digest(read_regular(script)[0]) == digest(git.blob(final, str(script.relative_to(source)))[0]),
             'controller-final-blob')
        source_digest = digest(encoded(manifest))
        need(release.value.get('sourceSealSha256') == source_digest, 'released-source-binding')
        runtime.verify()
        release.verify()
        persist(output / 'seals.json', {
            'final': final, 'old': OLD, 'source': manifest, 'graph': graph,
            'oldOwners': old_manifest, 'restoration': restoration, 'controller': controller,
            'runtime': {str(p): s for p, s in runtime.inputs.items()},
            'metadata': {str(p): s for p, s in release.metadata.items()},
            'git': {'head': final, 'refsSha256': digest(baseline['refs']),
                    'indexSha256': digest(baseline['index']),
                    'logicalIndexSha256': digest(baseline['logical']),
                    'lockIdentity': list(identity(custody.owner))},
        }, directory_identity=journal.directory)

        def verify(old):
            custody.check()
            need(list(identity(source.lstat())) == source_identity, 'source-root-replaced')
            need(git.snapshot() == baseline, 'git-state-changed')
            need(not git.run('ls-files', '--others', '--exclude-standard', '-z'),
                 'untracked-source-changed')
            current = tracked_manifest(source, git)
            need(set(current) == set(manifest), 'source-membership-changed')
            for path, expected in manifest.items():
                if old and path in old_manifest:
                    actual = current[path]
                    need(actual['identity'] == expected['identity'] and
                         actual['sha256'] == old_manifest[path]['sha256'] and
                         actual['mode'] == old_manifest[path]['mode'], 'old-source-changed')
                else:
                    need(current[path] == expected, 'source-changed')
            if old:
                old_graph = dependency_graph(source)
                need(all(path in manifest for path in old_graph), 'unsealed-old-import')
                union = sorted(set(graph) | set(old_graph))
                differences = git.run('diff', '--no-ext-diff', '--no-textconv', '--name-only', '-z',
                                      OLD, final, '--', *production_paths(union)).split(b'\0')[:-1]
                need(set(map(os.fsdecode, differences)) == set(OWNERS), 'old-import-closure')
            runtime.verify()
            release.verify()
            need(file_seal(script) == controller['script'] and
                 file_seal(runtime.executables['python']) == controller['executable'] and
                 same_process(process_identity(controller['pid']), controller), 'controller-changed')

        command = [str(runtime.executables['flutter']), 'test',
                   'test/connection_snapshot_cache_test.dart', '--plain-name', CASE, '--reporter', 'json']
        replay = Replay(custody, verify, lambda old: processes.run(
            command, source / PHONE, runtime.environment(), old), retire, journal)
        sealed = True
        journal.append('sealed', sourceSha256=source_digest, controller=controller)
        custody.prepare(custody.files, restoration)
        replay.run(old_blobs)
        held = False
        outcome = {'status': 'success', 'failure': '', 'custodyHeld': False, 'legs': replay.legs}
    except BaseException as error:
        code = str(error) if isinstance(error, Hold) else 'interrupted' if isinstance(
            error, (KeyboardInterrupt, SystemExit)) else 'infrastructure'
        outcome['failure'] = code
        held = custody.fd is not None and not custody.unlinked
        attempted = custody.attempted
        # Unsealed state, unknown readers, failed restoration or failed journaling retains custody.
        if held and sealed and replay is not None:
            try:
                replay.contain()
                held = False
            except BaseException as containment_error:
                outcome['containmentFailure'] = str(containment_error) if isinstance(
                    containment_error, Hold) else 'infrastructure'
        outcome['failureRestoration'] = ('not-required' if not attempted else
                                         'unknown' if custody.attempted else 'verified')
        lock_evidence = custody.evidence()
        outcome.update(lock_evidence)
        try:
            journal.append('custody-disposition', recovery=True, **lock_evidence)
        except BaseException:
            outcome['custodyEvidenceFailure'] = 'journal-failure'
        outcome['legs'] = replay.legs if replay else []
        outcome['ownedProcesses'] = [{k: record[k] for k in ('pid', 'start', 'parent', 'session')}
                                     for record in (*git.processes.known.values(),
                                                    *processes.known.values())]
    finally:
        custody.close_handles()
        journal.close()
    try:
        persist(output / 'result.json', outcome, MAX_FILE, journal.directory)
    except (OSError, Hold):
        # Persistence failure does not erase an already known custody disposition.
        outcome['persistenceFailure'] = 'result-persistence'
        if outcome['status'] == 'success':
            outcome['failure'] = 'result-persistence'
        outcome['status'] = 'held'
    return outcome


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--final', required=True)
    parser.add_argument('--release-receipt', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    def interrupted(_number, _frame):
        raise Hold('controller-signal')
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGHUP, interrupted)
    try:
        result = host_replay(args.final, args.release_receipt, args.output)
    except BaseException as error:
        result = {'status': 'held', 'failure': str(error) if isinstance(error, Hold)
                  else 'infrastructure', 'custodyHeld': 'unknown'}
    summary = {key: result[key] for key in ('status', 'failure', 'custodyHeld')}
    if 'persistenceFailure' in result:
        summary['persistenceFailure'] = result['persistenceFailure']
    print(json.dumps(summary, sort_keys=True))
    return 0 if result['status'] == 'success' else 2


if __name__ == '__main__':
    sys.exit(main())
