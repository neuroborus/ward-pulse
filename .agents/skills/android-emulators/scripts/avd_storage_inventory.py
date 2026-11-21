#!/usr/bin/env python3
"""Read-only, bounded host metadata inventory: python3 avd_storage_inventory.py [ROOT ...].

ROOT defaults to ~/.android/avd; explicitly selected symlink aliases are resolved.
Requires POSIX directory descriptors, O_DIRECTORY and O_NOFOLLOW. Descendant
symlinks are measured, never followed. No guest/file contents are read. Live
measurements are non-atomic; detected changes, errors and bounds make them partial.

--max-entries (100000) bounds distinct canonical paths admitted for accounting;
enumeration streams, with at most one lookahead name per directory at the bound.
--max-depth (64) is relative to each selected root (root depth zero). Up to 32
roots and 20 retained diagnostics are allowed. Explicit alias rechecks follow the
Linux pathname lookup limit of 40 symlinks. Overlaps/aliases share observations;
root totals cover observed paths within that root's depth limit. Root and RAM
groups overlap. Path counts describe distinct canonical observed paths; byte totals
deduplicate (device, inode), even across hardlinks and directory aliases.

Allocated bytes use st_blocks * 512. An inode with missing block metadata makes
each containing group's allocated total null, with a partial known subtotal.
Grand totals include regular files and separately shown directory, symlink and
other metadata overhead. Compare allocated totals with GNU du without symlink
dereferencing. Apparent totals sum st_size, including directory and other overhead
excluded by GNU du --apparent-size. QCOW virtual capacity and potential freed
space are outside these measures. ram.bin means a regular file of that exact name.
External layouts are directory children of a 'snapshots' directory;
only exact 'default_boot' labels are separated from other names (including backups).
RAM presence means a direct regular ram.bin. Uncertain observations are null.

One ASCII-escaped JSON report is emitted; exit 0 means complete host metadata
accounting, 1 partial/unavailable, 2 invalid arguments. --help prints this guidance.
Completeness proves neither snapshot validity nor recovery/disposal eligibility.
Internal QCOW snapshots, backing dependencies, ownership, running state, configured
or active Quick Boot and recovery validity remain Unknown. Qualified operator
qemu-img metadata is separate and has concurrent-read limitations; this helper
cannot clear dependencies or authorize cleanup. It invokes no tools or controls.
"""

import argparse
from collections import deque
from contextlib import ExitStack
from datetime import datetime, timezone
import json
import os
import stat
import sys


MAX_ROOTS = 32
MAX_DIAGNOSTICS = 20
MAX_ROOT_SYMLINKS = 40
UNKNOWN_FACTS = (
    "internal_qcow_snapshot_count", "backing_dependencies", "ownership",
    "running_state", "configured_quick_boot", "active_quick_boot", "recovery_validity",
    "disposal_eligibility",
)


def timestamp():
    return datetime.now(timezone.utc).isoformat()


def identity(metadata):
    return metadata.st_dev, metadata.st_ino


def binding_identity(metadata):
    return identity(metadata), stat.S_IFMT(metadata.st_mode)


def fingerprint(metadata):
    return tuple(getattr(metadata, name, None) for name in (
        "st_dev", "st_ino", "st_mode", "st_nlink", "st_size", "st_mtime_ns", "st_ctime_ns",
    ))


def kind(metadata):
    for name, predicate in (("regular_files", stat.S_ISREG),
                            ("directories", stat.S_ISDIR), ("symlinks", stat.S_ISLNK)):
        if predicate(metadata.st_mode):
            return name
    return "other"


def accounting(records, allocation_unavailable):
    categories = {name: [] for name in ("regular_files", "directories", "symlinks", "other")}
    for metadata in records:
        categories[kind(metadata)].append(metadata)
    return {
        **{name: totals(items, allocation_unavailable) for name, items in categories.items()},
        "total": totals(records, allocation_unavailable),
    }


def totals(records, allocation_unavailable):
    unique = {}
    for metadata in records:
        unique.setdefault(identity(metadata), metadata)
    missing = unique.keys() & allocation_unavailable
    known = sum(metadata.st_blocks * 512 for key, metadata in unique.items() if key not in missing)
    return {
        "path_count": len(records),
        "unique_inode_count": len(unique),
        "apparent_bytes": sum(metadata.st_size for metadata in unique.values()),
        "allocated_bytes": None if missing else known,
        "allocated_known_bytes": known,
        "allocation_complete": not missing,
    }


def is_snapshot_layout(path):
    return os.path.basename(os.path.dirname(path)) == "snapshots"


def open_lookup_directory(path, *, dir_fd=None):
    # Intermediate directories need name lookup access only.
    lookup = getattr(os, "O_SEARCH", getattr(os, "O_PATH", os.O_RDONLY))
    return os.open(path, lookup | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=dir_fd)


def open_directory(path):
    """Open every canonical component without following replacement symlinks."""
    read_flags = os.O_DIRECTORY | os.O_NOFOLLOW | os.O_RDONLY
    parent, leaf = os.path.split(path)
    if not leaf:
        return os.open(os.path.sep, read_flags)

    descriptor = open_lookup_directory(os.path.sep)
    try:
        for part in parent.split(os.path.sep):
            if part:
                child = open_lookup_directory(part, dir_fd=descriptor)
                os.close(descriptor)
                descriptor = child
        return os.open(leaf, read_flags, dir_fd=descriptor)
    finally:
        os.close(descriptor)


class Inventory:
    def __init__(self, roots, max_entries, max_depth):
        self.records = {}
        self.inodes = {}
        self.allocation_unavailable = {}
        self.inspected = set()
        self.stable_listings = set()
        self.unverified = set()
        self.directory_paths = {}
        self.aliases = {}
        self.max_entries = max_entries
        self.max_depth = max_depth
        self.report = {
            "status": "complete", "complete": True,
            "measurement": {"started_at": timestamp(), "ended_at": None},
            "bounds": {"max_entries": max_entries, "max_depth": max_depth,
                       "max_roots": MAX_ROOTS, "max_diagnostics": MAX_DIAGNOSTICS,
                       "max_root_symlinks": MAX_ROOT_SYMLINKS},
            "roots": [{"requested": root, "canonical": None, "identity": None}
                      for root in roots],
            "diagnostics": [], "diagnostics_omitted": 0,
            "unknown": dict.fromkeys(UNKNOWN_FACTS, "Unknown"),
            "limitations": ["Non-atomic host metadata accounting only.",
                            "Group totals overlap; inode bytes are not additive.",
                            "No snapshot, recovery, dependency or cleanup clearance."],
        }

    def problem(self, code, path, error=None):
        self.report.update(status="partial", complete=False)
        if code in ("changed", "unavailable", "unavailable_or_replaced"):
            self.unverified.add(path)
        diagnostic = {"code": code, "path": path}
        if error is not None:
            diagnostic["detail"] = str(error)
        if len(self.report["diagnostics"]) < MAX_DIAGNOSTICS:
            self.report["diagnostics"].append(diagnostic)
        else:
            self.report["diagnostics_omitted"] += 1

    def observe_blocks(self, path, metadata):
        blocks = getattr(metadata, "st_blocks", None)
        if blocks is not None and blocks >= 0:
            return blocks
        inode = identity(metadata)
        if inode not in self.allocation_unavailable:
            self.allocation_unavailable[inode] = path
            if inode in self.inodes:
                self.problem("allocation_unavailable", path)
        return None

    def changed(self, path, before, after):
        before_blocks = self.observe_blocks(path, before)
        after_blocks = self.observe_blocks(path, after)
        if (
            fingerprint(before) != fingerprint(after)
            or (None not in (before_blocks, after_blocks) and before_blocks != after_blocks)
        ):
            self.problem("changed", path)
            return True
        return False

    def inspect(self, path):
        if path not in self.inspected and len(self.inspected) >= self.max_entries:
            self.problem("max_entries", path)
            return False
        self.inspected.add(path)
        return True

    def remember(self, path, metadata):
        if path in self.records:
            return not self.changed(path, self.records[path], metadata)
        inode = identity(metadata)
        # A root lookup can observe missing blocks before a scan counts the inode.
        if inode not in self.inodes and inode in self.allocation_unavailable:
            self.problem("allocation_unavailable", self.allocation_unavailable[inode])
        previous = self.inodes.setdefault(inode, metadata)
        self.changed(path, previous, metadata)
        self.records[path] = metadata
        return True

    def note_directory(self, path, metadata):
        prior = self.directory_paths.setdefault(identity(metadata), path)
        if prior != path:
            self.aliases[path] = prior

    def walk(self, path, descriptor, metadata):
        # Frames keep only open ancestors and streaming iterators, never listings.
        stack = []
        ancestors = set()

        def push(current, fd, before, depth):
            try:
                iterator = os.scandir(fd)
            except OSError as error:
                self.problem("unavailable", current, error)
                os.close(fd)
                return
            stack.append((current, fd, before, depth, iterator))
            ancestors.add(identity(before))

        def finish(exhausted):
            current, fd, before, _, iterator = stack.pop()
            ancestors.remove(identity(before))
            try:
                stable = not self.changed(current, before, os.fstat(fd))
                if stack:
                    binding = os.stat(os.path.basename(current), dir_fd=stack[-1][1],
                                      follow_symlinks=False)
                    stable = not self.changed(current, before, binding) and stable
                if exhausted and stable and is_snapshot_layout(current):
                    self.stable_listings.add(current)
            except OSError as error:
                self.problem("unavailable", current, error)
            finally:
                iterator.close()
                os.close(fd)

        push(path, descriptor, metadata, 0)
        try:
            while stack:
                current, fd, before, depth, iterator = stack[-1]
                try:
                    entry = next(iterator)
                except StopIteration:
                    finish(True)
                    continue
                except OSError as error:
                    self.problem("unavailable", current, error)
                    finish(False)
                    continue
                child = os.path.join(current, entry.name)
                if depth >= self.max_depth:
                    self.problem("max_depth", child)
                    finish(False)
                    continue
                if not self.inspect(child):
                    finish(False)
                    continue
                try:
                    observed = os.stat(entry.name, dir_fd=fd, follow_symlinks=False)
                    if not self.remember(child, observed):
                        continue
                    if stat.S_ISDIR(observed.st_mode):
                        child_fd = os.open(
                            entry.name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd
                        )
                        try:
                            opened = os.fstat(child_fd)
                            if self.changed(child, observed, opened):
                                continue
                            self.note_directory(child, opened)
                            if identity(opened) in ancestors:
                                self.problem("directory_cycle", child)
                            else:
                                push(child, child_fd, opened, depth + 1)
                                child_fd = None
                        finally:
                            if child_fd is not None:
                                os.close(child_fd)
                    else:
                        binding = os.stat(entry.name, dir_fd=fd, follow_symlinks=False)
                        self.changed(child, observed, binding)
                except OSError as error:
                    self.problem("unavailable_or_replaced", child, error)
        finally:
            while stack:
                finish(False)

    def members(self, root):
        prefix = os.path.join(root, "")
        return [
            metadata for path, metadata in self.records.items()
            if path == root or (path.startswith(prefix)
                                and path.count(os.path.sep, len(prefix)) < self.max_depth)
        ]

    def has_unverified_component(self, path):
        # A scan through an open descriptor can outlive an ancestor's path binding.
        while path not in self.unverified:
            parent = os.path.dirname(path)
            if parent == path:
                return False
            path = parent
        return True

    def check_root_bindings(self, requested, *, lookup_failed):
        # Compare earlier observations with the components reached by the explicit lookup.
        # Check alias targets component by component before interpreting later '..' entries.
        if not os.path.isabs(requested):
            try:
                requested = os.path.join(os.getcwd(), requested)
            except OSError as error:
                self.problem("unavailable", requested, error)
                return None, None
        pending = deque(requested.split(os.path.sep))
        path = os.path.sep
        followed_links = 0
        result = None, None
        bindings = []
        # Keep lookup descriptors available for rechecking even after leaving a branch.
        with ExitStack() as opened:
            try:
                anchor = open_lookup_directory(path)
                opened.callback(os.close, anchor)
                parents = [(path, anchor)]
                while pending:
                    part = pending.popleft()
                    if part in ("", "."):
                        continue
                    if part == "..":
                        if len(parents) > 1:
                            parents.pop()
                        path = parents[-1][0]
                        continue
                    parent, descriptor = parents[-1]
                    path = os.path.join(parent, part)
                    current = os.stat(part, dir_fd=descriptor, follow_symlinks=False)
                    bindings.append((path, part, descriptor, current))
                    # Allocation belongs to the inode even if the path is already unverified.
                    self.observe_blocks(path, current)
                    previous = self.records.get(path)
                    if previous is not None and path not in self.unverified:
                        self.changed(path, previous, current)
                    if stat.S_ISLNK(current.st_mode):
                        if followed_links == MAX_ROOT_SYMLINKS:
                            self.problem("root_symlink_limit", requested)
                            break
                        followed_links += 1
                        target = os.readlink(part, dir_fd=descriptor)
                        pending.extendleft(reversed(target.split(os.path.sep)))
                        if os.path.isabs(target):
                            del parents[1:]
                        path = parents[-1][0]
                    elif pending:
                        if not stat.S_ISDIR(current.st_mode):
                            if not lookup_failed and path not in self.unverified:
                                self.problem("unavailable", path)
                            break
                        child = open_lookup_directory(part, dir_fd=descriptor)
                        opened.callback(os.close, child)
                        metadata = os.fstat(child)
                        self.observe_blocks(path, metadata)
                        if binding_identity(current) != binding_identity(metadata):
                            self.problem("changed", path)
                            break
                        parents.append((path, child))
                else:
                    if path == parents[-1][0]:
                        current = os.fstat(parents[-1][1])
                        self.observe_blocks(path, current)
                    result = path, current
            except OSError as error:
                if path not in self.unverified:
                    self.problem("unavailable", path, error)

            if not self.root_bindings_stable(bindings):
                return None, None
        if lookup_failed and result[0] in self.records:
            self.unverified.add(result[0])
        return result

    def root_bindings_stable(self, bindings):
        # Check children before parents so an open but detached ancestor cannot
        # make the metadata reached through it look like a current path binding.
        stable = True
        for path, name, descriptor, before in reversed(bindings):
            try:
                current = os.stat(name, dir_fd=descriptor, follow_symlinks=False)
            except OSError as error:
                if path not in self.unverified:
                    self.problem("unavailable", path, error)
                stable = False
                continue
            self.observe_blocks(path, current)
            if path in self.records and path not in self.unverified:
                stable = not self.changed(path, before, current) and stable
            elif (binding_identity(before) != binding_identity(current)
                  or (stat.S_ISLNK(before.st_mode) and fingerprint(before) != fingerprint(current))):
                if path not in self.unverified:
                    self.problem("changed", path)
                stable = False
        return stable

    def check_root_metadata(self, root, before, current):
        if binding_identity(before) == binding_identity(current):
            root["identity"] = dict(zip(("device", "inode"), identity(current)))
        return self.changed(root["canonical"], before, current)

    def run(self):
        if not (hasattr(os, "O_NOFOLLOW") and hasattr(os, "O_DIRECTORY")
                and os.open in os.supports_dir_fd and os.stat in os.supports_dir_fd
                and os.readlink in os.supports_dir_fd
                and os.scandir in os.supports_fd):
            self.problem("unsupported_directory_anchoring", None)
        else:
            walked_roots = set()
            for root in self.report["roots"]:
                requested = root["requested"]
                alias_changed = False
                try:
                    requested = os.path.expanduser(requested)
                    canonical = None
                    try:
                        before = os.stat(requested)
                        self.observe_blocks(requested, before)
                        canonical = os.path.realpath(requested, strict=True)
                    finally:
                        if self.records:
                            resolved, _ = self.check_root_bindings(
                                requested, lookup_failed=canonical is None
                            )
                            if canonical is not None and resolved != canonical:
                                self.unverified.add(canonical)
                                alias_changed = resolved is not None
                    root["canonical"] = canonical
                    if not stat.S_ISDIR(before.st_mode):
                        self.problem("not_directory", requested)
                        continue
                    descriptor = open_directory(canonical)
                    try:
                        opened = os.fstat(descriptor)
                        if self.check_root_metadata(root, before, opened):
                            continue
                        if not self.inspect(canonical) or not self.remember(canonical, opened):
                            continue
                        self.note_directory(canonical, opened)
                        if canonical not in walked_roots:
                            walked_roots.add(canonical)
                            # Only exact canonical root repeats share a traversal.
                            root_fd, descriptor = descriptor, None
                            self.walk(canonical, root_fd, opened)
                        after = os.stat(requested)
                        self.changed(canonical, before, after)
                        if os.path.realpath(requested, strict=True) != canonical:
                            alias_changed = True
                    finally:
                        if descriptor is not None:
                            os.close(descriptor)
                except (OSError, ValueError, RecursionError) as error:
                    self.problem("unavailable", root["canonical"] or requested, error)
                finally:
                    if root["canonical"] is not None:
                        resolved, current = self.check_root_bindings(requested, lookup_failed=False)
                        if resolved is None:
                            self.unverified.add(canonical)
                        elif resolved != canonical:
                            alias_changed = True
                        elif not stat.S_ISDIR(before.st_mode):
                            self.check_root_metadata(root, before, current)
                        elif canonical not in self.unverified:
                            self.changed(canonical, before, current)
                        if alias_changed:
                            self.unverified.add(canonical)
                            self.problem("root_alias_changed", requested)
        allocation_unavailable = self.allocation_unavailable.keys()
        for root in self.report["roots"]:
            canonical = root["canonical"]
            metadata = self.records.get(canonical)
            root["accounting"] = None
            if (
                metadata is not None
                and stat.S_ISDIR(metadata.st_mode)
                and root["identity"] == dict(zip(("device", "inode"), identity(metadata)))
            ):
                root["accounting"] = accounting(self.members(canonical), allocation_unavailable)
        self.report["accounting"] = accounting(self.records.values(), allocation_unavailable)
        ram_files = [
            metadata for path, metadata in self.records.items()
            if os.path.basename(path) == "ram.bin" and stat.S_ISREG(metadata.st_mode)
        ]
        self.report["ram_files"] = totals(ram_files, allocation_unavailable)
        layouts = []
        for path, metadata in self.records.items():
            if not stat.S_ISDIR(metadata.st_mode) or not is_snapshot_layout(path):
                continue
            ram_path = os.path.join(path, "ram.bin")
            ram = self.records.get(ram_path)
            presence = None
            if not self.has_unverified_component(ram_path):
                if ram is not None:
                    presence = stat.S_ISREG(ram.st_mode)
                elif path in self.stable_listings:
                    presence = False
            label = os.path.basename(path)
            layouts.append({
                "path": path,
                "label": label,
                "identity": dict(zip(("device", "inode"), identity(metadata))),
                "category": "default_boot" if label == "default_boot" else "named",
                "regular_ram_observed": presence,
            })
        self.report["external_snapshot_directories"] = {
            "observations": layouts,
            "default_boot_paths": sum(item["category"] == "default_boot" for item in layouts),
            "named_paths": sum(item["category"] == "named" for item in layouts),
            "without_regular_ram_paths": sum(item["regular_ram_observed"] is False for item in layouts),
            "ram_observation_unknown_paths": sum(item["regular_ram_observed"] is None for item in layouts),
        }
        self.report["directory_aliases"] = self.aliases
        self.report["measurement"]["ended_at"] = timestamp()
        return self.report


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise ValueError(message)


def main(argv=None):
    parser = Parser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("roots", nargs="*", help="directory roots (default: ~/.android/avd)")
    parser.add_argument("--max-entries", type=int, default=100000)
    parser.add_argument("--max-depth", type=int, default=64)
    try:
        args = parser.parse_args(argv)
        roots = args.roots or [os.path.expanduser("~/.android/avd")]
        if len(roots) > MAX_ROOTS or any(not root or "\0" in root for root in roots):
            raise ValueError("select 1 to 32 nonempty directory roots without NUL characters")
        if args.max_entries < 1 or args.max_depth < 0:
            raise ValueError("max-entries must be positive and max-depth nonnegative")
    except ValueError as error:
        print(json.dumps({"status": "invalid", "complete": False, "error": str(error)}, ensure_ascii=True))
        return 2
    report = Inventory(roots, args.max_entries, args.max_depth).run()
    print(json.dumps(report, ensure_ascii=True, allow_nan=False))
    return 0 if report["complete"] else 1


if __name__ == "__main__":
    sys.exit(main())
