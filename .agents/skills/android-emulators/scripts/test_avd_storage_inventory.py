"""Controlled host fixtures for the AVD metadata inventory."""

from contextlib import contextmanager, redirect_stdout
from datetime import datetime
import errno
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

import avd_storage_inventory as inventory


@contextmanager
def replace_stat(replacement):
    with (
        mock.patch.object(os, "supports_dir_fd", os.supports_dir_fd | {replacement}),
        mock.patch.object(os, "stat", replacement),
    ):
        yield


def invoke(*arguments):
    stdout = io.StringIO()
    with redirect_stdout(stdout):
        status = inventory.main([os.fspath(argument) for argument in arguments])
    output = stdout.getvalue()
    return status, json.loads(output), output


def gnu_output(program, options, *paths):
    result = subprocess.run(
        [program, *options, "--", *paths], check=True, capture_output=True, text=True,
    )
    return result.stdout


def fixture_state(root):
    state = {}
    for path in (root, *root.rglob("*")):
        metadata = path.lstat()
        if stat.S_ISREG(metadata.st_mode):
            contents = path.read_bytes()
        elif stat.S_ISLNK(metadata.st_mode):
            contents = os.readlink(path)
        else:
            contents = None
        state[path] = (metadata.st_mode, metadata.st_mtime_ns, contents)
    return state


class InventoryTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name).resolve()
        self.root = self.base / "test.avd"
        self.root.mkdir()

    def test_failed_ram_metadata_is_unknown(self):
        layouts = self.root / "snapshots"
        for name in ("default_boot", "missing", "unreadable"):
            (layouts / name).mkdir(parents=True)
        (layouts / "default_boot" / "ram.bin").write_bytes(b"regular")
        (layouts / "unreadable" / "ram.bin").write_bytes(b"unreadable metadata")
        unreadable = (layouts / "unreadable").stat()
        original_stat = os.stat

        def stat_with_denial(path, *, dir_fd=None, follow_symlinks=True):
            if (path == "ram.bin" and dir_fd is not None
                    and os.fstat(dir_fd).st_ino == unreadable.st_ino):
                raise PermissionError(errno.EACCES, "injected metadata denial")
            return original_stat(path, dir_fd=dir_fd, follow_symlinks=follow_symlinks)

        with replace_stat(stat_with_denial):
            status, report, _ = invoke(self.root)

        self.assertEqual(status, 1)
        self.assertFalse(report["complete"])
        observations = report["external_snapshot_directories"]
        self.assertEqual(
            {item["label"]: item["regular_ram_observed"]
             for item in observations["observations"]},
            {"default_boot": True, "missing": False, "unreadable": None},
        )
        self.assertEqual(observations["without_regular_ram_paths"], 1)
        self.assertEqual(observations["ram_observation_unknown_paths"], 1)
        self.assertIn(("unavailable_or_replaced", str(layouts / "unreadable" / "ram.bin")),
                      [(item["code"], item["path"]) for item in report["diagnostics"]])

    def test_late_layout_change_through_root_alias_makes_ram_unknown(self):
        layout = self.root / "snapshots" / "default_boot"
        layout.mkdir(parents=True)
        os.utime(layout, (946684800, 946684800))
        alias = self.base / "layout-alias"
        alias.symlink_to(layout, target_is_directory=True)
        original_stat = os.stat
        alias_reads = 0

        def stat_with_late_ram(path, *, dir_fd=None, follow_symlinks=True):
            nonlocal alias_reads
            if path == str(alias) and dir_fd is None:
                alias_reads += 1
                if alias_reads == 2:
                    (layout / "ram.bin").touch()
            return original_stat(path, dir_fd=dir_fd, follow_symlinks=follow_symlinks)

        with replace_stat(stat_with_late_ram):
            status, report, _ = invoke(alias)

        self.assertEqual(status, 1)
        self.assertFalse(report["complete"])
        observations = report["external_snapshot_directories"]
        self.assertIsNone(observations["observations"][0]["regular_ram_observed"])
        self.assertEqual(observations["without_regular_ram_paths"], 0)
        self.assertEqual(observations["ram_observation_unknown_paths"], 1)
        self.assertIn(("changed", str(layout)),
                      [(item["code"], item["path"]) for item in report["diagnostics"]])

    def test_later_root_rechecks_layout_metadata(self):
        layout = self.root / "snapshots" / "default_boot"
        selected = layout / "selected"
        selected.mkdir(parents=True)
        os.utime(layout, (946684800, 946684800))
        original_stat = os.stat

        for create_ram in (False, True):
            with self.subTest(create_ram=create_ram):
                def stat_with_late_ram(path, *, dir_fd=None, follow_symlinks=True):
                    if create_ram and path == str(selected) and dir_fd is None:
                        (layout / "ram.bin").touch(exist_ok=True)
                    return original_stat(path, dir_fd=dir_fd, follow_symlinks=follow_symlinks)

                with replace_stat(stat_with_late_ram):
                    status, report, _ = invoke(self.root, selected)

                self.assertEqual(status, int(create_ram))
                self.assertEqual(report["complete"], not create_ram)
                observations = report["external_snapshot_directories"]
                self.assertIs(observations["observations"][0]["regular_ram_observed"],
                              None if create_ram else False)
                self.assertEqual(observations["without_regular_ram_paths"], int(not create_ram))
                self.assertEqual(observations["ram_observation_unknown_paths"], int(create_ram))
                if create_ram:
                    self.assertIn(("changed", str(layout)),
                                  [(item["code"], item["path"]) for item in report["diagnostics"]])

    def test_regular_ram_selected_as_root_retains_presence(self):
        snapshots = self.root / "snapshots"
        regular = snapshots / "default_boot" / "ram.bin"
        directory = snapshots / "directory" / "ram.bin"
        regular.parent.mkdir(parents=True)
        regular.touch()
        directory.mkdir(parents=True)
        (snapshots / "missing").mkdir()

        status, report, _ = invoke(self.root, directory, regular)

        self.assertEqual(status, 1)
        self.assertFalse(report["complete"])
        self.assertEqual([(item["code"], item["path"]) for item in report["diagnostics"]],
                         [("not_directory", str(regular))])
        self.assertIsNotNone(report["roots"][1]["accounting"])
        metadata = regular.stat()
        self.assertEqual(report["roots"][2]["identity"],
                         {"device": metadata.st_dev, "inode": metadata.st_ino})
        self.assertIsNone(report["roots"][2]["accounting"])
        observations = report["external_snapshot_directories"]
        self.assertEqual(
            {item["label"]: item["regular_ram_observed"] for item in observations["observations"]},
            {"default_boot": True, "directory": False, "missing": False},
        )
        self.assertEqual(observations["without_regular_ram_paths"], 2)
        self.assertEqual(observations["ram_observation_unknown_paths"], 0)

    def test_replaced_layout_ancestor_makes_ram_unknown(self):
        ancestor = self.root / "avd"
        layouts = ancestor / "snapshots"
        (layouts / "default_boot").mkdir(parents=True)
        (layouts / "named").mkdir()
        (layouts / "named" / "ram.bin").touch()
        control = self.base / "control" / "snapshots" / "missing"
        control.mkdir(parents=True)
        original_stat = os.stat
        ancestor_reads = 0

        def stat_with_replacement(path, *, dir_fd=None, follow_symlinks=True):
            nonlocal ancestor_reads
            if path == ancestor.name and dir_fd is not None:
                ancestor_reads += 1
                if ancestor_reads == 2:  # Recheck the binding after scanning both layouts.
                    ancestor.rename(self.base / "old-avd")
                    (layouts / "default_boot").mkdir(parents=True)
                    (layouts / "default_boot" / "ram.bin").touch()
                    (layouts / "named").mkdir()
            return original_stat(path, dir_fd=dir_fd, follow_symlinks=follow_symlinks)

        with replace_stat(stat_with_replacement):
            status, report, _ = invoke(self.root, control)

        self.assertEqual(status, 1)
        self.assertFalse(report["complete"])
        observations = report["external_snapshot_directories"]
        self.assertEqual(
            {item["label"]: item["regular_ram_observed"]
             for item in observations["observations"]},
            {"default_boot": None, "named": None, "missing": False},
        )
        self.assertEqual(observations["without_regular_ram_paths"], 1)
        self.assertEqual(observations["ram_observation_unknown_paths"], 2)
        self.assertIn(("changed", str(ancestor)),
                      [(item["code"], item["path"]) for item in report["diagnostics"]])

    def test_overlapping_root_replaced_by_file_makes_ram_unknown(self):
        ancestor = self.root / "avd"
        (ancestor / "snapshots" / "default_boot").mkdir(parents=True)
        original_stat = os.stat

        def stat_with_replacement(path, *, dir_fd=None, follow_symlinks=True):
            if path == str(ancestor) and dir_fd is None:
                ancestor.rename(self.base / "old-avd")
                ancestor.touch()
            return original_stat(path, dir_fd=dir_fd, follow_symlinks=follow_symlinks)

        with replace_stat(stat_with_replacement):
            status, report, _ = invoke(self.root, ancestor)

        self.assertEqual(status, 1)
        self.assertFalse(report["complete"])
        observations = report["external_snapshot_directories"]
        self.assertIsNone(observations["observations"][0]["regular_ram_observed"])
        self.assertEqual(observations["without_regular_ram_paths"], 0)
        self.assertIn(("not_directory", str(ancestor)),
                      [(item["code"], item["path"]) for item in report["diagnostics"]])

    def test_failed_overlapping_root_with_trailing_slash_makes_ram_unknown(self):
        original_stat = os.stat
        for failure in ("vanished", "denied"):
            with self.subTest(failure=failure):
                parent = self.root / failure
                ancestor = parent / "avd"
                layout = ancestor / "snapshots" / "default_boot"
                layout.mkdir(parents=True)
                requested = str(ancestor) + "/"

                def stat_with_failure(path, *, dir_fd=None, follow_symlinks=True):
                    if path == requested and dir_fd is None:
                        if failure == "denied":
                            raise PermissionError(errno.EACCES, "injected root lookup denial")
                        ancestor.rename(self.base / "old-avd")
                    return original_stat(path, dir_fd=dir_fd, follow_symlinks=follow_symlinks)

                with replace_stat(stat_with_failure):
                    status, report, _ = invoke(parent, requested)

                self.assertEqual(status, 1)
                self.assertFalse(report["complete"])
                self.assertEqual(report["roots"][1]["requested"], requested)
                observations = report["external_snapshot_directories"]
                self.assertIsNone(observations["observations"][0]["regular_ram_observed"])
                self.assertEqual(observations["without_regular_ram_paths"], 0)
                self.assertEqual(observations["ram_observation_unknown_paths"], 1)

    def test_overlapping_root_retargeted_to_symlink_makes_ram_unknown(self):
        original_stat = os.stat
        for use_alias in (False, True):
            with self.subTest(use_alias=use_alias):
                parent = self.root / ("aliased" if use_alias else "direct")
                ancestor = parent / "avd"
                layout = ancestor / "snapshots" / "default_boot"
                layout.mkdir(parents=True)
                replacement = self.base / parent.name
                other_layout = replacement / "snapshots" / "named"
                other_layout.mkdir(parents=True)
                (other_layout / "ram.bin").touch()
                requested = ancestor
                if use_alias:
                    requested = parent / "alias"
                    requested.symlink_to(ancestor.name, target_is_directory=True)
                replaced = False

                def stat_with_retarget(path, *, dir_fd=None, follow_symlinks=True):
                    nonlocal replaced
                    if path == str(requested) and dir_fd is None and not replaced:
                        ancestor.rename(replacement.with_name(f"old-{parent.name}"))
                        ancestor.symlink_to(replacement, target_is_directory=True)
                        replaced = True
                    return original_stat(path, dir_fd=dir_fd, follow_symlinks=follow_symlinks)

                with replace_stat(stat_with_retarget):
                    status, report, _ = invoke(parent, requested)

                self.assertEqual(status, 1)
                self.assertFalse(report["complete"])
                self.assertEqual(report["roots"][1]["canonical"], str(replacement))
                observations = report["external_snapshot_directories"]
                self.assertEqual(
                    {item["path"]: item["regular_ram_observed"]
                     for item in observations["observations"]},
                    {str(layout): None, str(other_layout): True},
                )
                self.assertEqual(observations["without_regular_ram_paths"], 0)
                self.assertIn(("changed", str(ancestor)),
                              [(item["code"], item["path"]) for item in report["diagnostics"]])

    def test_late_overlapping_root_retarget_makes_sibling_layout_unknown(self):
        ancestor = self.root / "avd"
        (ancestor / "snapshots" / "default_boot").mkdir(parents=True)
        selected = ancestor / "selected"
        selected.mkdir()
        replacement = self.base / "replacement"
        (replacement / selected.name).mkdir(parents=True)
        original_stat = os.stat
        lookups = 0

        def stat_with_late_retarget(path, *, dir_fd=None, follow_symlinks=True):
            nonlocal lookups
            if path == str(selected) and dir_fd is None:
                lookups += 1
                if lookups == 2:
                    ancestor.rename(self.base / "old-avd")
                    ancestor.symlink_to(replacement, target_is_directory=True)
            return original_stat(path, dir_fd=dir_fd, follow_symlinks=follow_symlinks)

        with replace_stat(stat_with_late_retarget):
            status, report, _ = invoke(self.root, selected)

        self.assertEqual(status, 1)
        self.assertFalse(report["complete"])
        observations = report["external_snapshot_directories"]
        self.assertIsNone(observations["observations"][0]["regular_ram_observed"])
        self.assertEqual(observations["without_regular_ram_paths"], 0)
        self.assertIn(("changed", str(ancestor)),
                      [(item["code"], item["path"]) for item in report["diagnostics"]])

    def test_root_replacement_at_final_resolution_makes_ram_unknown(self):
        (self.root / "snapshots" / "default_boot").mkdir(parents=True)
        original_realpath = os.path.realpath
        resolutions = 0

        def realpath_with_replacement(path, *, strict=False):
            nonlocal resolutions
            resolutions += 1
            if resolutions == 2:
                moved = self.base / "old-avd"
                self.root.rename(moved)
                self.root.symlink_to(moved, target_is_directory=True)
            return original_realpath(path, strict=strict)

        with mock.patch.object(os.path, "realpath", realpath_with_replacement):
            status, report, _ = invoke(self.root)

        self.assertEqual(status, 1)
        self.assertFalse(report["complete"])
        observations = report["external_snapshot_directories"]
        self.assertIsNone(observations["observations"][0]["regular_ram_observed"])
        self.assertEqual(observations["without_regular_ram_paths"], 0)
        self.assertIn(("root_alias_changed", str(self.root)),
                      [(item["code"], item["path"]) for item in report["diagnostics"]])

    def test_alias_retarget_between_stat_and_realpath_leaves_identity_unknown(self):
        original_realpath = os.path.realpath
        for directory in (True, False):
            with self.subTest(directory=directory):
                original = self.base / f"original-{directory}"
                replacement = self.base / f"replacement-{directory}"
                for target in (original, replacement):
                    if directory:
                        target.mkdir()
                    else:
                        target.touch()
                alias = self.base / f"alias-{directory}"
                alias.symlink_to(original)

                def realpath_with_retarget(path, *, strict=False):
                    if path == str(alias):
                        alias.unlink()
                        alias.symlink_to(replacement)
                    return original_realpath(path, strict=strict)

                with mock.patch.object(os.path, "realpath", realpath_with_retarget):
                    status, report, _ = invoke(alias)

                self.assertEqual(status, 1)
                self.assertFalse(report["complete"])
                self.assertIn(("changed", str(replacement)),
                              [(item["code"], item["path"]) for item in report["diagnostics"]])
                root = report["roots"][0]
                self.assertEqual(root["canonical"], str(replacement))
                self.assertIsNone(root["identity"])
                self.assertIsNone(root["accounting"])

    def test_regular_root_identity_cannot_follow_replaced_canonical_ancestor(self):
        original = self.root / "ram.bin"
        original.touch()
        replacement = self.base / "replacement"
        replacement.mkdir()
        other_ram = replacement / original.name
        other_ram.touch()
        alias = self.base / "alias"
        alias.symlink_to(original)
        original_realpath = os.path.realpath

        def realpath_with_replacement(path, *, strict=False):
            alias.unlink()
            alias.symlink_to(other_ram)
            resolved = original_realpath(path, strict=strict)
            replacement.rename(self.base / "moved-replacement")
            replacement.symlink_to(self.root, target_is_directory=True)
            return resolved

        with mock.patch.object(os.path, "realpath", realpath_with_replacement):
            status, report, _ = invoke(alias)

        self.assertEqual(status, 1)
        self.assertEqual(alias.resolve(), original)
        root = report["roots"][0]
        self.assertEqual(root["canonical"], str(other_ram))
        self.assertIsNone(root["identity"])
        self.assertIsNone(root["accounting"])
        self.assertIn(("root_alias_changed", str(alias)),
                      [(item["code"], item["path"]) for item in report["diagnostics"]])

    def test_alias_retarget_after_final_realpath_marks_mapping_partial(self):
        layout = self.root / "snapshots" / "default_boot"
        child = layout / "child"
        other = self.base / "other" / "child"
        child.mkdir(parents=True)
        other.mkdir(parents=True)
        alias = self.base / "alias"
        alias.symlink_to(child, target_is_directory=True)
        requested = alias / ".."
        original_realpath = os.path.realpath

        for retarget in (False, True):
            with self.subTest(retarget=retarget):
                resolutions = 0

                def realpath_then_retarget(path, *, strict=False):
                    nonlocal resolutions
                    resolved = original_realpath(path, strict=strict)
                    resolutions += 1
                    if retarget and resolutions == 2:
                        alias.unlink()
                        alias.symlink_to(other, target_is_directory=True)
                    return resolved

                with mock.patch.object(os.path, "realpath", realpath_then_retarget):
                    status, report, _ = invoke(requested)

                self.assertEqual(requested.resolve(), other.parent if retarget else layout)
                self.assertEqual(status, int(retarget))
                self.assertEqual(report["complete"], not retarget)
                self.assertEqual(report["roots"][0]["canonical"], str(layout))
                observations = report["external_snapshot_directories"]
                self.assertIs(observations["observations"][0]["regular_ram_observed"],
                              None if retarget else False)
                self.assertEqual(observations["without_regular_ram_paths"], int(not retarget))
                if retarget:
                    self.assertIn(("root_alias_changed", str(requested)),
                                  [(item["code"], item["path"]) for item in report["diagnostics"]])

    def test_ancestor_replaced_during_final_binding_check_makes_ram_unknown(self):
        snapshots = self.root / "snapshots"
        layout = snapshots / "default_boot"
        layout.mkdir(parents=True)
        moved = self.base / "moved-snapshots"
        original_stat = os.stat
        original_realpath = os.path.realpath
        inode = layout.stat().st_ino

        for replace in (False, True):
            with self.subTest(replace=replace):
                resolutions = 0
                replaced = False

                def realpath_before_recheck(path, *, strict=False):
                    nonlocal resolutions
                    resolved = original_realpath(path, strict=strict)
                    if path == str(layout):
                        resolutions += 1
                    return resolved

                def stat_with_replacement(path, *, dir_fd=None, follow_symlinks=True):
                    nonlocal replaced
                    if (replace and not replaced and resolutions == 2
                            and path in (str(layout), layout.name)):
                        snapshots.rename(moved)
                        snapshots.symlink_to(moved, target_is_directory=True)
                        replaced = True
                    return original_stat(path, dir_fd=dir_fd, follow_symlinks=follow_symlinks)

                def lstat_with_replacement(path, *, dir_fd=None):
                    return stat_with_replacement(path, dir_fd=dir_fd, follow_symlinks=False)

                with (
                    replace_stat(stat_with_replacement),
                    mock.patch.object(os, "lstat", lstat_with_replacement),
                    mock.patch.object(os.path, "realpath", realpath_before_recheck),
                ):
                    status, report, _ = invoke(layout)

                self.assertEqual(replaced, replace)
                self.assertEqual(layout.stat().st_ino, inode)
                self.assertEqual(report["roots"][0]["canonical"], str(layout))
                self.assertEqual(status, int(replace), report["diagnostics"])
                self.assertEqual(report["complete"], not replace)
                observations = report["external_snapshot_directories"]
                self.assertIs(observations["observations"][0]["regular_ram_observed"],
                              None if replace else False)
                self.assertEqual(observations["without_regular_ram_paths"], int(not replace))
                if replace:
                    self.assertIn(("changed", str(snapshots)),
                                  [(item["code"], item["path"]) for item in report["diagnostics"]])

    def test_overlapping_root_gets_its_own_depth_allowance(self):
        nested = self.root / "A"
        ram = nested / "B" / "C" / "ram.bin"
        ram.parent.mkdir(parents=True)
        ram.write_bytes(b"ram")

        status, report, _ = invoke("--max-depth", "3", self.root, nested)

        self.assertEqual(status, 1)
        self.assertFalse(report["complete"])
        self.assertIn(("max_depth", str(ram)),
                      [(item["code"], item["path"]) for item in report["diagnostics"]])
        self.assertEqual(report["ram_files"]["path_count"], 1)
        self.assertEqual(report["ram_files"]["unique_inode_count"], 1)
        self.assertEqual(report["ram_files"]["apparent_bytes"], 3)
        self.assertEqual(report["accounting"]["total"]["path_count"], 5)
        self.assertEqual(
            [root["accounting"]["regular_files"]["path_count"] for root in report["roots"]],
            [0, 1],
        )

    def test_accounting_matches_gnu_tools_without_modifying_fixture(self):
        snapshots = self.root / "snapshots"
        default = snapshots / "default_boot"
        backup = snapshots / "default_boot.backup"
        named = snapshots / 'named\n"\\\udcff'
        for layout in (default, backup, named):
            layout.mkdir(parents=True)
        ram = default / "ram.bin"
        ram.write_bytes(b"host RAM file")
        os.link(ram, backup / "ram.bin")
        sparse = self.root / "disk.img"
        with sparse.open("wb") as handle:
            handle.truncate(256 * 1024 + 1)
        outside = self.base / "outside"
        outside.mkdir()
        (outside / "ram.bin").write_bytes(b"outside fixture")
        (named / "ram.bin").symlink_to(outside / "ram.bin")
        (self.root / "escape").symlink_to(outside, target_is_directory=True)
        link = self.base / "alias-to-snapshots"
        link.symlink_to(snapshots, target_is_directory=True)
        alias = link / ".."
        before = fixture_state(self.base)

        status, report, output = invoke(self.root, snapshots, alias)

        self.assertEqual(status, 0, report["diagnostics"])
        self.assertTrue(report["complete"])
        self.assertEqual(output.count("\n"), 1)
        self.assertTrue(output.isascii())
        self.assertEqual(report["roots"][2]["requested"], str(alias))
        self.assertEqual(report["roots"][2]["canonical"], str(self.root))
        self.assertEqual(report["roots"][2]["identity"], report["roots"][0]["identity"])
        self.assertEqual(report["roots"][2]["accounting"], report["roots"][0]["accounting"])
        self.assertEqual(report["roots"][1]["accounting"]["total"]["path_count"], 7)
        self.assertEqual(report["unknown"]["disposal_eligibility"], "Unknown")
        self.assertTrue(all(value == "Unknown" for value in report["unknown"].values()))
        total = report["accounting"]["total"]
        allocated = int(gnu_output("du", ("-s", "-B1"), self.root).split()[0])
        apparent = int(gnu_output("du", ("-s", "-B1", "--apparent-size"), self.root).split()[0])
        directories = (self.root, snapshots, default, backup, named)
        directory_sizes = sum(map(int, gnu_output("stat", ("-c", "%s"), *directories).split()))
        self.assertEqual(total["allocated_bytes"], allocated)
        self.assertEqual(total["apparent_bytes"], apparent + directory_sizes)
        self.assertEqual(report["accounting"]["directories"]["apparent_bytes"], directory_sizes)
        for field in ("apparent_bytes", "allocated_bytes"):
            overhead = sum(report["accounting"][group][field]
                           for group in ("directories", "symlinks", "other"))
            self.assertEqual(total[field], report["accounting"]["regular_files"][field] + overhead)
        self.assertEqual(total["path_count"], 10)
        self.assertEqual(total["unique_inode_count"], 9)
        self.assertEqual(report["accounting"]["symlinks"]["path_count"], 2)
        self.assertEqual(total["allocated_known_bytes"], total["allocated_bytes"])
        self.assertTrue(total["allocation_complete"])
        for path in (ram, sparse):
            size, blocks, unit = map(int, gnu_output("stat", ("-c", "%s %b %B"), path).split())
            if path == ram:
                self.assertEqual(report["ram_files"], {
                    "path_count": 2, "unique_inode_count": 1, "apparent_bytes": size,
                    "allocated_bytes": blocks * unit, "allocated_known_bytes": blocks * unit,
                    "allocation_complete": True,
                })
            else:
                self.assertLess(blocks * unit, size)
                self.assertEqual(
                    report["accounting"]["regular_files"]["apparent_bytes"]
                    - report["ram_files"]["apparent_bytes"],
                    size,
                )
                self.assertEqual(
                    report["accounting"]["regular_files"]["allocated_bytes"]
                    - report["ram_files"]["allocated_bytes"],
                    blocks * unit,
                )
        layouts = report["external_snapshot_directories"]
        self.assertEqual(layouts["default_boot_paths"], 1)
        self.assertEqual(layouts["named_paths"], 2)
        self.assertEqual(layouts["without_regular_ram_paths"], 1)
        self.assertEqual(
            {item["path"]: (item["category"], item["regular_ram_observed"])
             for item in layouts["observations"]},
            {
                str(default): ("default_boot", True),
                str(backup): ("named", True),
                str(named): ("named", False),
            },
        )
        self.assertEqual(fixture_state(self.base), before)

    def test_entry_budget_charges_failed_metadata_attempts(self):
        for index in range(4):
            (self.root / str(index)).touch()
        root_metadata = self.root.stat()
        attempts = []
        original_stat = os.stat

        def deny_children(path, *, dir_fd=None, follow_symlinks=True):
            if dir_fd is not None and os.path.samestat(os.fstat(dir_fd), root_metadata):
                attempts.append(path)
                raise PermissionError(errno.EACCES, "injected metadata denial")
            return original_stat(path, dir_fd=dir_fd, follow_symlinks=follow_symlinks)

        with replace_stat(deny_children):
            status, report, _ = invoke("--max-entries", "2", self.root)

        self.assertEqual(status, 1)
        self.assertEqual(report["accounting"]["total"]["path_count"], 1)
        self.assertEqual(report["bounds"]["max_entries"], 2)
        self.assertEqual(len(attempts), 1)
        self.assertEqual([item["code"] for item in report["diagnostics"]],
                         ["unavailable_or_replaced", "max_entries"])

    def test_unavailable_roots_respect_diagnostic_budget(self):
        missing = self.root / "absent"
        status, report, _ = invoke(*([missing] * 23))

        self.assertEqual(status, 1)
        self.assertFalse(report["complete"])
        self.assertEqual(len(report["roots"]), 23)
        self.assertIsNone(report["roots"][0]["canonical"])
        self.assertIsNone(report["roots"][0]["identity"])
        self.assertIsNone(report["roots"][0]["accounting"])
        self.assertEqual(len(report["diagnostics"]), 20)
        self.assertTrue(all(item["code"] == "unavailable" for item in report["diagnostics"]))
        self.assertEqual(report["diagnostics_omitted"], 3)

    def test_explicit_root_symlink_loop_reports_recheck_limit(self):
        alias = self.base / "loop"
        alias.symlink_to(alias.name)

        status, report, _ = invoke(self.root, alias)

        self.assertEqual(status, 1)
        self.assertFalse(report["complete"])
        self.assertIsNone(report["roots"][1]["canonical"])
        self.assertIn(("root_symlink_limit", str(alias)),
                      [(item["code"], item["path"]) for item in report["diagnostics"]])

    def test_missing_blocks_remain_unknown_across_hardlinks(self):
        nested = self.root / "nested"
        nested.mkdir()
        unknown = nested / "unknown.img"
        unknown.write_bytes(b"unavailable allocation")
        os.link(unknown, self.root / "hardlink.img")
        known = self.root / "known.img"
        known.write_bytes(b"known allocation")
        original_stat = os.stat

        def stat_with_missing_blocks(path, *, dir_fd=None, follow_symlinks=True):
            nonlocal observations
            metadata = original_stat(path, dir_fd=dir_fd, follow_symlinks=follow_symlinks)
            if path == unknown.name and dir_fd is not None:
                observations += 1
                if observations == missing_observation:
                    return SimpleNamespace(**{
                        name: getattr(metadata, name) for name in dir(metadata)
                        if name.startswith("st_") and name != "st_blocks"
                    })
            return metadata

        blocks, unit = map(int, gnu_output("stat", ("-c", "%b %B"), known).split())
        # Fail the first read, its binding check, then the overlapping root's read.
        for missing_observation in (1, 2, 3):
            with self.subTest(missing_observation=missing_observation):
                observations = 0
                with replace_stat(stat_with_missing_blocks):
                    status, report, _ = invoke(self.root, nested)

                self.assertEqual(status, 1)
                self.assertFalse(report["complete"])
                regular = report["accounting"]["regular_files"]
                self.assertEqual(regular["unique_inode_count"], 2)
                self.assertIsNone(regular["allocated_bytes"])
                self.assertFalse(regular["allocation_complete"])
                self.assertEqual(regular["allocated_known_bytes"], blocks * unit)
                self.assertIsNone(report["accounting"]["total"]["allocated_bytes"])
                self.assertIsNone(report["roots"][1]["accounting"]["total"]["allocated_bytes"])
                self.assertEqual([item["code"] for item in report["diagnostics"]],
                                 ["allocation_unavailable"])

    def test_missing_blocks_on_recheck_of_unverified_inode(self):
        nested = self.root / "nested"
        control = self.base / "control"
        outside = self.base / "unaccounted"
        for directory in (nested, control, outside):
            directory.mkdir()
        ram = control / "ram.bin"
        ram.write_bytes(b"known allocation")
        measurements = gnu_output("stat", ("-c", "%b %B"), self.root, control, ram).splitlines()
        root_bytes, control_bytes, ram_bytes = (
            int(blocks) * int(unit) for blocks, unit in map(str.split, measurements)
        )
        original_stat, original_fstat = os.stat, os.fstat
        accounted, unrelated = nested.stat(), outside.stat()

        def observation(metadata, *, missing=False):
            fields = {name: getattr(metadata, name) for name in dir(metadata) if name.startswith("st_")}
            if os.path.samestat(metadata, accounted):
                fields["st_blocks"] = 8  # Keep the accounted directory nonzero on every fixture FS.
                if changed and checking_root:
                    fields["st_mtime_ns"] += 1
            if missing:
                fields.pop("st_blocks", None)
            return SimpleNamespace(**fields)

        def stat_observation(path, *, dir_fd=None, follow_symlinks=True):
            nonlocal checking_root, rechecks
            metadata = original_stat(path, dir_fd=dir_fd, follow_symlinks=follow_symlinks)
            if not os.path.samestat(metadata, accounted):
                return metadata
            if dir_fd is None and path == str(nested):
                checking_root = True
            if dir_fd is not None and checking_root:
                rechecks += 1
                if rechecks == missing_at:
                    return observation(unrelated if different_inode else metadata, missing=True)
            return observation(metadata)

        def fstat_observation(descriptor):
            metadata = original_fstat(descriptor)
            return observation(metadata) if os.path.samestat(metadata, accounted) else metadata

        # The first anchored pair sees known blocks. Reads 3 and 4 are the final
        # lookup and its reverse recheck, after the changed record was rejected.
        for changed, missing_at, different_inode in (
            (False, None, False), (True, None, False), (False, 4, False),
            (True, 3, False), (True, 4, False), (True, 4, True),
        ):
            with self.subTest(changed=changed, missing_at=missing_at, different_inode=different_inode):
                checking_root, rechecks = False, 0
                with (
                    replace_stat(stat_observation),
                    mock.patch.object(os, "fstat", fstat_observation),
                ):
                    status, report, _ = invoke(self.root, nested, control)

                unknown = missing_at is not None and not different_inode
                self.assertEqual(rechecks, 4)
                self.assertEqual(status, int(changed or unknown), report["diagnostics"])
                self.assertEqual(report["complete"], not (changed or unknown))
                parent, selected, separate = (root["accounting"] for root in report["roots"])
                grand = report["accounting"]
                for totals, other_bytes, includes_nested in (
                    (grand["total"], root_bytes + control_bytes + ram_bytes, True),
                    (grand["directories"], root_bytes + control_bytes, True),
                    (parent["total"], root_bytes, True), (selected["total"], 0, True),
                    (separate["total"], control_bytes + ram_bytes, False),
                    (grand["regular_files"], ram_bytes, False), (report["ram_files"], ram_bytes, False),
                ):
                    incomplete = unknown and includes_nested
                    known = other_bytes + (4096 if includes_nested and not unknown else 0)
                    self.assertEqual(totals["allocated_bytes"], None if incomplete else known)
                    self.assertEqual(totals["allocated_known_bytes"], known)
                    self.assertEqual(totals["allocation_complete"], not incomplete)
                self.assertEqual(
                    [item["path"] for item in report["diagnostics"]
                     if item["code"] == "allocation_unavailable"],
                    [str(nested)] if unknown else [],
                )

    def test_missing_blocks_before_failed_root_resolution_remain_unknown(self):
        nested = self.root / "nested"
        nested.mkdir()
        root_bytes = self.root.stat().st_blocks * 512
        original_stat, original_realpath = os.stat, os.path.realpath

        def stat_without_blocks(path, *, dir_fd=None, follow_symlinks=True):
            metadata = original_stat(path, dir_fd=dir_fd, follow_symlinks=follow_symlinks)
            if dir_fd is None and path == str(nested):
                return SimpleNamespace(**{
                    name: getattr(metadata, name) for name in dir(metadata)
                    if name.startswith("st_") and name != "st_blocks"
                })
            return metadata

        def realpath_with_failure(path, *, strict=False):
            if path == str(nested):
                raise PermissionError(errno.EACCES, "injected root resolution denial")
            return original_realpath(path, strict=strict)

        for roots in ((self.root, nested), (nested, self.root), (nested,)):
            with self.subTest(roots=roots):
                with (
                    replace_stat(stat_without_blocks),
                    mock.patch.object(os.path, "realpath", realpath_with_failure),
                ):
                    status, report, _ = invoke(*roots)

                self.assertEqual(status, 1)
                self.assertIsNone(report["roots"][roots.index(nested)]["canonical"])
                counted = self.root in roots
                groups = [report["accounting"]]
                if counted:
                    groups.append(report["roots"][roots.index(self.root)]["accounting"])
                for group in groups:
                    for totals in (group["directories"], group["total"]):
                        self.assertEqual(totals["unique_inode_count"], 2 if counted else 0)
                        self.assertEqual(totals["allocated_bytes"], None if counted else 0)
                        self.assertEqual(totals["allocated_known_bytes"], root_bytes if counted else 0)
                        self.assertEqual(totals["allocation_complete"], not counted)
                self.assertEqual(
                    [item["path"] for item in report["diagnostics"]
                     if item["code"] == "allocation_unavailable"],
                    [str(nested)] if counted else [],
                )

    def test_selected_root_below_search_only_directory(self):
        ancestor = self.root / "ancestor"
        selected = ancestor / "selected"
        selected.mkdir(parents=True)
        (selected / "ram.bin").write_bytes(b"ram")
        ancestor.chmod(0o100)
        try:
            status, report, _ = invoke(selected)
        finally:
            ancestor.chmod(0o700)

        self.assertEqual(status, 0, report["diagnostics"])
        self.assertTrue(report["complete"])
        self.assertEqual(report["ram_files"]["path_count"], 1)

    def test_replacement_symlink_is_never_traversed(self):
        child = self.root / "child"
        child.mkdir()
        outside = self.base / "outside"
        outside.mkdir()
        (outside / "ram.bin").write_bytes(b"outside fixture")
        original_stat = os.stat
        replaced = False

        def stat_then_replace(path, *, dir_fd=None, follow_symlinks=True):
            nonlocal replaced
            metadata = original_stat(path, dir_fd=dir_fd, follow_symlinks=follow_symlinks)
            if path == child.name and dir_fd is not None and not replaced:
                child.rename(self.base / "previous-child")
                child.symlink_to(outside, target_is_directory=True)
                replaced = True
            return metadata

        with replace_stat(stat_then_replace):
            status, report, _ = invoke(self.root)

        self.assertTrue(replaced)
        self.assertEqual(status, 1)
        self.assertFalse(report["complete"])
        self.assertEqual(report["ram_files"]["path_count"], 0)
        self.assertIn(("unavailable_or_replaced", str(child)),
                      [(item["code"], item["path"]) for item in report["diagnostics"]])
        self.assertIn(("changed", str(self.root)),
                      [(item["code"], item["path"]) for item in report["diagnostics"]])

    def test_argument_errors_and_default_bounds(self):
        for arguments in (("--max-entries", "0"), ("--max-depth", "-1"),
                          ("",), ("bad\0root",), (self.root,) * 33):
            with self.subTest(arguments=arguments):
                status, report, output = invoke(*arguments)
                self.assertEqual(status, 2)
                self.assertEqual(report["status"], "invalid")
                self.assertFalse(report["complete"])
                self.assertEqual(output.count("\n"), 1)

        def fixture_default(path):
            self.assertIn(path, ("~/.android/avd", str(self.root)))
            return str(self.root)

        with (
            mock.patch.object(os.path, "expanduser", side_effect=fixture_default) as expand,
            mock.patch.object(
                inventory, "timestamp",
                side_effect=["2026-01-01T00:00:00+00:00", "2026-01-01T00:00:01+00:00"],
            ),
        ):
            status, report, _ = invoke()

        expand.assert_any_call("~/.android/avd")
        self.assertEqual(status, 0)
        self.assertTrue(report["complete"])
        self.assertEqual(report["roots"][0]["canonical"], str(self.root))
        self.assertEqual(report["bounds"], {
            "max_entries": 100000, "max_depth": 64, "max_roots": 32, "max_diagnostics": 20,
            "max_root_symlinks": 40,
        })
        measurement = report["measurement"]
        self.assertLess(datetime.fromisoformat(measurement["started_at"]),
                        datetime.fromisoformat(measurement["ended_at"]))


if __name__ == "__main__":
    unittest.main()
