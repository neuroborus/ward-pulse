"""Cheap delivery/inventory/metadata/protocol regressions; no Java, DEX or devices."""

import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import tempfile
import time
import unittest
from xml.etree import ElementTree as ET


OWNER = Path(__file__).resolve().parent
JAVA = (OWNER / 'WorkSnapshot.java').read_text()
SHELL_SOURCE = Path(os.environ.get('WARDPULSE_SYNC_TEST_SOURCE', OWNER / 'run.sh'))
SHELL = SHELL_SOURCE.read_text()
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


class DeliveryTests(unittest.TestCase):
    """The same wait_for_summary entry and assertions also run against bound old source."""

    def hierarchy(self, settings=False, view=0, mode='cached'):
        root = ET.Element('hierarchy', rotation='0')

        def node(parent, box, label='', **attrs):
            values = {'package': 'app.wardpulse', 'bounds': box, 'text': '',
                      'content-desc': label, 'enabled': 'true', 'clickable': 'false',
                      'selected': 'false', 'scrollable': 'false'}
            values.update(attrs)
            return ET.SubElement(parent, 'node', values)

        body = node(root, '[0,0][400,800]')
        for label, left, selected in [('Dashboard', 0, not settings),
                                      ('Settings', 300, settings)]:
            node(body, f'[{left},700][{left + 100},780]', label + '\nTab',
                 clickable='true', selected=str(selected).lower())
        if not settings:
            # Test both Android text and Flutter's merged content descriptions.
            node(body, '[16,100][300,140]', **{'text': 'Usage dashboard'})
            node(body, '[16,145][300,180]', 'Updated 12:00')
        else:
            content = node(body, '[0,80][400,700]', scrollable='true',
                           enabled='false' if mode == 'scroll-disabled' else 'true')
            if view == 0:
                node(content, '[16,200][384,280]', 'Mock data\nDebug only',
                     clickable='true', checkable='true',
                     checked='true' if mode == 'mock-on' else 'false')
            else:
                node(content, '[16,100][300,130]', 'Diagnostics')
                # Initially clip just one pixel of the action. A reveal must
                # clear the high-density drag threshold before moving content.
                top = 646 if view == 1 else 629
                # Card's default semantic container can merge all static labels,
                # including the status title Sync, but retain the button as a child.
                card = node(content, f'[16,140][384,{top + 70}]',
                            'Sync\n12:00\nWatch summary\nWidget summary\n'
                            'Send to watch\nDevelopment only')
                node(content if mode == 'foreign-sync' else card,
                     f'[300,{top + 5}][380,{top + 55}]', 'Sync',
                     clickable='true', enabled='false' if mode == 'disabled' else 'true')
        return ET.tostring(root, encoding='unicode')

    def delivery(self, mode='cached', obstruction=None, interrupt=False):
        with tempfile.TemporaryDirectory(prefix='work-delivery-', dir=OWNER) as scratch:
            directory = Path(scratch) / 'owned'
            directory.mkdir()
            for settings, view, name in [(False, 0, 'dashboard'),
                                         (True, 0, 'settings0'),
                                         (True, 1, 'settings1'),
                                         (True, 2, 'settings2')]:
                (directory / name).write_text(self.hierarchy(settings, view, mode))
            native = """Physical size: 400x800
Physical density: 160
Override density: 480
WINDOW MANAGER WINDOWS (dumpsys window windows)
  Window #0 Window{abc u0 app.wardpulse/app.wardpulse.MainActivity}:
    mOwnerUid=10123 mViewVisibility=0x0 mHaveFrame=true mObscured=false
    Frames: parent=[0,0][400,800] display=[0,0][400,800] frame=[0,0][400,800]
    mHasSurface=true isOnScreen=true isVisible=true
  mCurrentFocus=Window{abc u0 app.wardpulse/app.wardpulse.MainActivity}
  mFocusedApp=ActivityRecord{def u0 app.wardpulse/.MainActivity t1}
WINDOW MANAGER DISPLAY CONTENTS (dumpsys window displays)
  frame=[0,0][200,300]
"""
            if mode == 'wrong-host':
                native = native.replace('mCurrentFocus=Window{abc u0 app.wardpulse/',
                                        'mCurrentFocus=Window{abc u0 other.app/')
            if mode in ('obstructed', 'obstructed-closed'):
                native += '''  Window #1 Window{aaa u0 captured-private-label}:
    mHasSurface=true isOnScreen=true isVisible=true
    mFrame=[300,700][400,780]
'''
            if obstruction:
                native += ('  Window #1 Window{bbb u0 unclassified}:\n'
                           '    mHasSurface=true isOnScreen=true isVisible=true\n'
                           f'    mFrame={obstruction}\n')
            (directory / 'native').write_text(native)
            # A windows-only capture can lack service-level focus. Do not hand
            # the fake caller full-service evidence for the wrong acquisition.
            (directory / 'native-windows').write_text(native.split('  mCurrentFocus=', 1)[0])
            script = r'''
set -euo pipefail
SCRATCH=$1/owned TRACE=$1/trace MODE=$2 APP_ID=app.wardpulse
PHONE_SERIAL=phone WEAR_SERIAL=wear
unset SECONDS
SECONDS=10
OBSERVING=0 PRE_DEATH_DEADLINE=0 LEDGER_READY=0 RETAINING=0
DELIVERING=1 FRESH_PUBLICATION=0 FRESH_RECEIPT=0 PHONE_ACTIVITY=0
DELIVERY_ACTIVE=0 DELIVERY_REPORTED=0 DELIVERY_UI_DIR= DELIVERY_TARGET=
DELIVERY_UI_CAPTURED=0 LIFECYCLE_ACTION=
READER_HOST= READER_DIAG_HOST= READER_DEVICE_PID= READER_STAGE_ACTIVE=0
READER_INPUT_FD= READER_OUTPUT_FD= READER_STDERR_FD= READER_STDERR_DRAIN_FD=
READER_DIAG_OUTPUT_FAILED=0 DEVICE_SCRATCH=
MONITORS=(4242)
declare -A UIDS=([phone]=10123 [wear]=10124)
declare -A RUNNING=([phone]='41 100 app.wardpulse' [wear]='51 200 app.wardpulse')
declare -A CURSOR=([phone]=0 [wear]=0) DELIVERY_BOUNDARY=() DELIVERY_COVERAGE=()
view=0 INTERRUPT=0
# Stale modes age evidence by five ticks, the first rejected age; aged modes by their suffix.
AGE=5
[[ "$MODE" != aged-* ]] || AGE=${MODE##*-}
printf 'dashboard\n' >"$SCRATCH/page"
barrier() {
  local role=$1 page
  printf 'barrier caller=%s role=%s at=%s\n' "${FUNCNAME[1]}" "$role" "$SECONDS" >>"$TRACE"
  EVENTS=
  if [[ -f "$SCRATCH/qualified" && ( "$MODE" == qualified-both ||
        "$MODE" == boundary-both || "${FUNCNAME[1]}" != delivery_observe ) ]]; then
    SECONDS=40
    printf 'EXTRA_AFTER_QUALIFICATION\n' >>"$TRACE"
    return
  fi
  CURSOR[$role]=$((CURSOR[$role] + 1))
  # Stale modes age already qualified evidence at the boundary before its input:
  # once for the reveal scroll and the Sync tap, or before every input. Aged modes
  # age it once, before the Settings tap or the second reveal scroll.
  if [[ "$MODE" == stale-* || "$MODE" == aged-tap-* || "$MODE" == aged-scroll-* ]] &&
      [[ "${FUNCNAME[1]}" == wait_for_summary ]]; then
    read -r page <"$SCRATCH/page"
    if [[ "$MODE" == stale-always || ! -f "$SCRATCH/aged-$page" && (
          "$MODE" == stale-once && "$page" == settings[12] ||
          "$MODE" == aged-tap-* && "$page" == dashboard ||
          "$MODE" == aged-scroll-* && "$page" == settings1 ) ]]; then
      : >"$SCRATCH/aged-$page"
      SECONDS=$((SECONDS + AGE))
    fi
  fi
  if [[ "$MODE" == gap && "$role" == phone ||
        "$MODE" == late-gap && "$role" == wear && -f "$SCRATCH/synced" ]]; then
    hold 'Event loss or monitoring gap.'
  fi
  if [[ "$role" == phone ]]; then
    if [[ "$MODE" == already || "$MODE" == send-only || -f "$SCRATCH/synced" && ( "$MODE" == cached || "$MODE" == stale-once || "$MODE" == late-gap ) ]]; then
      EVENTS=PUBLICATION
    elif [[ "$MODE" == race && -f "$SCRATCH/settings2-seen" ]]; then
      EVENTS=PUBLICATION
    fi
  elif [[ "$MODE" == already || "$MODE" == receipt-only ||
          -f "$SCRATCH/synced" && ( "$MODE" == cached || "$MODE" == stale-once ) ||
          "$MODE" == race && -f "$SCRATCH/settings2-seen" ]]; then
    EVENTS=RECEIPT
  fi
  if [[ -f "$SCRATCH/qualifying" ]]; then
    case "$MODE:$role:${FUNCNAME[1]}" in
      qualified-*:phone:delivery_observe) EVENTS=PUBLICATION ;;
      qualified-both:wear:delivery_observe|qualified-expired:wear:delivery_observe|boundary-both:wear:delivery_observe)
        EVENTS=RECEIPT ;;
      boundary-*:phone:wait_for_summary) EVENTS=PUBLICATION ;;
    esac
    if [[ "$role" == wear && "${FUNCNAME[1]}" == delivery_observe ||
          "$MODE" == boundary-* && "${FUNCNAME[1]}" == wait_for_summary ]]; then
      case "$MODE" in
        qualified-both) SECONDS=39 ;;
        boundary-both) if [[ "${FUNCNAME[1]}" == wait_for_summary ]]; then SECONDS=39; fi ;;
        qualified-expired) SECONDS=40 ;;
        qualified-publication|boundary-publication)
          if [[ -f "$SCRATCH/qualified" && "${FUNCNAME[1]}" == delivery_observe ]]; then
            EVENTS=RECEIPT SECONDS=21
          elif [[ "$MODE" == qualified-publication || "${FUNCNAME[1]}" == wait_for_summary ]]; then
            SECONDS=20
          fi ;;
      esac
      # Boundary modes first accept publication at the retained phone boundary.
      if [[ "$MODE" != boundary-* || "${FUNCNAME[1]}" == wait_for_summary ]]; then
        : >"$SCRATCH/qualified"
      fi
    fi
  fi
  record_sync_events "$role"
}
app_processes() {
  printf 'process role=%s at=%s\n' "$2" "$SECONDS" >>"$TRACE"
  printf '%s' "${RUNNING[$2]}"
}
sleep() { SECONDS=$((SECONDS + 1)); }
timeout() {
  # All effects are local fakes; keep the real production budget selection.
  printf 'budget at=%s grace=%s limit=%s\n' "$SECONDS" "$1" "$2" >>"$TRACE"
  shift 2
  "$@"
}
adb_on() {
  local command="${*:4}" page
  local -a input=()
  if [[ "$command" == 'input '* ]]; then
    # Each input names its evidence's capture tick; input on aged evidence is flagged.
    printf 'input captured=%s at=%s\n' "$DELIVERY_UI_CAPTURED" "$SECONDS" >>"$TRACE"
    (( SECONDS - DELIVERY_UI_CAPTURED < 5 )) || printf 'STALE_INPUT\n' >>"$TRACE"
  fi
  case "$command" in
    'cmd package list packages -U app.wardpulse')
      if [[ "$MODE" == acquisition-timeout ]]; then return 124; fi
      if [[ "$MODE" == uid-invalid ]]; then printf 'package:app.wardpulse uid:invalid\n'
      else printf 'package:app.wardpulse uid:10123\n'; fi ;;
    'cmd package list packages -U --uid 10123') printf 'package:app.wardpulse uid:10123\n' ;;
    'mktemp -d /data/local/tmp/wardpulse-sync-XXXXXXXX') printf '/data/local/tmp/wardpulse-sync-abcdefgh\n' ;;
    'wm size; wm density; dumpsys window -a')
      printf 'native full\n' >>"$TRACE"
      cat "$SCRATCH/native" ;;
    'wm size; dumpsys window -a windows')
      printf 'native windows\n' >>"$TRACE"
      cat "$SCRATCH/native-windows" ;;
    *uiautomator*)
      read -r page <"$SCRATCH/page"
      cat "$SCRATCH/$page"
      if [[ "$MODE" == qualified-* || "$MODE" == boundary-* ]]; then : >"$SCRATCH/qualifying"; fi
      if [[ "$MODE" == expiry ]]; then SECONDS=$((SECONDS + 30)); fi
      # The first Mock proof capture, or an aged mode's first Dashboard capture, ages
      # before its own qualification completes.
      if [[ "$MODE" == stale-once && "$page" == settings0 ||
            "$MODE" == aged-qualification-* && "$page" == dashboard ]] &&
          [[ ! -f "$SCRATCH/aged-$page" ]]; then
        : >"$SCRATCH/aged-$page"
        SECONDS=$((SECONDS + AGE))
      fi
      if [[ "$page" == settings2 ]]; then : >"$SCRATCH/settings2-seen"; fi ;;
    'input tap '*)
      printf 'tap %s\n' "$command" >>"$TRACE"
      read -r page <"$SCRATCH/page"
      if [[ "$page" == dashboard ]]; then printf 'settings0\n' >"$SCRATCH/page"
      else : >"$SCRATCH/synced"; printf 'SYNC\n' >>"$TRACE"; fi ;;
    'input swipe '*)
      printf 'scroll %s\n' "$command" >>"$TRACE"
      read -r -a input <<< "$command"
      # At 480 dpi, 18 logical pixels consume 54 physical pixels. A shorter
      # gesture must leave the clipped action in place rather than fake a reveal.
      if (( input[3] - input[5] > 54 )); then
        view=$((view + 1))
        printf 'settings%s\n' "$view" >"$SCRATCH/page"
      fi ;;
    'rm -f /data/local/tmp/wardpulse-sync-abcdefgh/hierarchy.xml'|'rmdir /data/local/tmp/wardpulse-sync-abcdefgh')
      printf 'device %s\n' "$command" >>"$TRACE" ;;
    *) printf 'UNEXPECTED_EFFECT\n' >&2; return 2 ;;
  esac
}
finish() {
  local status=$?
  printf 'state publication=%s receipt=%s elapsed=%s\n' "$FRESH_PUBLICATION" "$FRESH_RECEIPT" "$((SECONDS - 10))" >>"$TRACE"
  if [[ "$MODE" == obstructed* || "$MODE" == acquisition-timeout ||
        "$MODE" == uid-invalid || "$MODE" == scroll-disabled ]] || (( INTERRUPT )); then
    return "$status"
  fi
}
reader_diagnostic() { :; }
kill() { printf 'kill %s\n' "$*" >>"$TRACE"; }
wait() { printf 'wait %s\n' "$*" >>"$TRACE"; }
'''
            # Optional additions are extracted only when present. Old source uses
            # its unmodified common entry: absent new helpers cannot be RED.
            names = ['bounded', 'hold', 'record_sync_events', 'package_uid']
            names += re.findall(r'^(delivery_[a-z_]+|parse_package_uid)\(\) \{', SHELL, re.M)
            script += '\n'.join(shell_function(name) for name in names)
            script += '\n' + shell_function('wait_for_summary')
            script += '\n' + shell_function('cleanup')
            script += '\ntrap finish EXIT\n'
            if mode in ('obstructed', 'obstructed-closed', 'acquisition-timeout',
                        'uid-invalid', 'scroll-disabled'):
                script += "trap 'finish || cleanup' EXIT\n"
            if mode == 'obstructed-closed':
                script += 'exec 2>&-\n'
            if interrupt:
                # The production signal trap leads into the same failing EXIT cleanup. A
                # real TERM arrives at the first command boundary where an attempt after a
                # discard has exposed its route: the report then reads every transition
                # published before that route. Function tracing reaches that boundary
                # inside the production functions; only the parent shell signals, once.
                script += "trap 'finish || cleanup' EXIT\ntrap 'exit 143' TERM\nINTERRUPT=1\n"
                script += ('set -o functrace\n'
                           "trap 'if (( BASHPID == $$ && ${DELIVERY_UI_STALE:-0} > 0 )) && "
                           '[[ ${DELIVERY_PHASE:-delivery} != delivery ]]; then '
                           "trap - DEBUG; builtin kill -TERM \"$$\"; fi' DEBUG\n")
            script += 'wait_for_summary\n'
            result = subprocess.run(['bash', '-c', script, 'work-delivery', scratch, mode],
                                    text=True, capture_output=True, timeout=5)
            trace = (Path(scratch) / 'trace').read_text()
            if not directory.exists():
                trace += 'scratch removed\n'
            return result, trace

    def assert_executed(self, result, trace):
        self.assertIn('state publication=', trace)
        for error in ('command not found', 'unbound variable', 'SyntaxError',
                      'Traceback', 'UNEXPECTED_EFFECT', 'No such file'):
            self.assertNotIn(error, result.stderr)

    def test_cached_data_gets_one_sync_then_distinct_events(self):
        result, trace = self.delivery()
        self.assert_executed(result, trace)
        # This is the old/fixed assertion witness. A historical HOLD, missing
        # helper or subprocess/setup error cannot satisfy this action assertion.
        self.assertEqual(trace.splitlines().count('SYNC'), 1, trace + result.stderr)
        self.assertEqual(sum(line.startswith('scroll ') for line in trace.splitlines()), 2, trace)
        self.assertIn('state publication=1 receipt=1', trace)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_publication_observed_before_route_or_before_sync_avoids_action(self):
        for mode in ('already', 'race'):
            with self.subTest(mode=mode):
                result, trace = self.delivery(mode)
                self.assert_executed(result, trace)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn('SYNC', trace)
                if mode == 'already':
                    self.assertNotIn('tap ', trace)
                    self.assertNotIn('scroll ', trace)

    def test_qualified_delivery_completes_before_expiry_without_more_effects(self):
        for mode in ('qualified-both', 'boundary-both'):
            with self.subTest(mode=mode):
                result, trace = self.delivery(mode)
                self.assert_executed(result, trace)
                self.assertIn('state publication=1 receipt=1', trace)
                if mode == 'qualified-both':
                    self.assertIn('process role=wear at=39', trace)
                self.assertEqual(result.returncode, 0, trace + result.stderr)
                self.assertIn('state publication=1 receipt=1 elapsed=29', trace)
                self.assertEqual(trace.splitlines().count('native full'), 2, trace)
                self.assertNotIn('EXTRA_AFTER_QUALIFICATION', trace)
                self.assertNotIn('tap ', trace)
                self.assertNotIn('scroll ', trace)
                self.assertNotIn('SYNC', trace)
                if mode == 'qualified-both':
                    self.assertNotIn('barrier caller=wait_for_summary', trace)

    def test_qualified_publication_waits_for_receipt_without_more_input_work(self):
        for mode in ('qualified-publication', 'boundary-publication'):
            with self.subTest(mode=mode):
                result, trace = self.delivery(mode)
                self.assert_executed(result, trace)
                self.assertEqual(result.returncode, 0, trace + result.stderr)
                self.assertIn('state publication=1 receipt=1 elapsed=11', trace)
                self.assertNotIn('EXTRA_AFTER_QUALIFICATION', trace)
                self.assertNotIn('tap ', trace)
                self.assertNotIn('scroll ', trace)
                self.assertEqual(trace.splitlines().count('native full'), 2, trace)

    def test_accepted_events_cannot_bypass_qualification_deadline(self):
        result, trace = self.delivery('qualified-expired')
        self.assert_executed(result, trace)
        self.assertIn('state publication=1 receipt=1 elapsed=30', trace)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Delivery deadline expired.', result.stderr)
        self.assertNotIn('tap ', trace)
        self.assertNotIn('scroll ', trace)

    def test_obstructed_target_retains_closed_facts_through_cleanup(self):
        result, trace = self.delivery('obstructed')
        self.assert_executed(result, trace)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('scratch removed', trace)
        self.assertIn('kill 4242\nwait 4242\n', trace)
        self.assertIn('device rm -f /data/local/tmp/wardpulse-sync-abcdefgh/hierarchy.xml', trace)
        self.assertIn('device rmdir /data/local/tmp/wardpulse-sync-abcdefgh', trace)
        self.assertNotIn('tap ', trace)
        self.assertNotIn('scroll ', trace)
        self.assertNotIn('SYNC', trace)
        self.assertEqual(result.stdout, '')
        records = [line for line in result.stderr.splitlines() if line.startswith('Delivery UI:')]
        self.assertEqual(len(records), 1, result.stderr)
        record = records[0]
        self.assertLessEqual(len(record), 2200)
        self.assertRegex(record, r'phase=dashboard invocation=\d+:1 status=1 ')
        self.assertRegex(record, r'producer_pid=\d+ ')
        for fact in ('guard=target_unobstructed', 'failure=predicate', 'error=GuardRejected',
                     'read=Hierarchy', 'producer=PythonTarget', 'focus_count=1',
                     'host_count=1', 'host_owner_match=True', 'action_owner_match=True',
                     'native_stable=True',
                     'match_count=1', 'enabled=True', 'clickable=True', 'visible=True',
                     'obstruction_count=1', 'overlap_count=1', 'target=300,700,400,780',
                     'blocking=300,700,400,780', 'viewport=Unknown', 'semantic_match=Unknown'):
            self.assertIn(fact, record)
        for raw in ('captured-private-label', 'Window{', '<hierarchy', 'MainActivity',
                    'Updated 12:00', 'Traceback'):
            self.assertNotIn(raw, result.stdout + result.stderr)

    def test_fringe_overlap_taps_the_unobstructed_interior(self):
        # The Settings control spans y=700..780; this full-width window covers y>=770.
        result, trace = self.delivery(obstruction='[0,770][400,800]')
        self.assert_executed(result, trace)
        taps = re.findall(r'^tap input tap (\d+) (\d+)$', trace, re.M)
        self.assertEqual(len(taps), 2, trace + result.stderr)
        x, y = map(int, taps[0])
        self.assertTrue(300 <= x < 400 and 700 <= y < 770, taps)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_overlap_reaching_the_would_be_center_holds_before_input(self):
        # Covering the would-be center at y=740, the same window is no fringe to exclude.
        result, trace = self.delivery(obstruction='[0,730][400,800]')
        self.assert_executed(result, trace)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('tap ', trace)
        self.assertNotIn('scroll ', trace)
        records = [line for line in result.stderr.splitlines() if line.startswith('Delivery UI:')]
        self.assertEqual(len(records), 1, result.stderr)
        for fact in ('guard=target_unobstructed', 'overlap_count=1', 'target=300,700,400,780',
                     'hit_area=300,700,400,780', 'blocking=0,730,400,800'):
            self.assertIn(fact, records[0])

    def test_acquisition_timeout_is_not_a_predicate_rejection(self):
        result, trace = self.delivery('acquisition-timeout')
        self.assert_executed(result, trace)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('guard=package_uid failure=acquisition status=124 error=Timeout', result.stderr)
        self.assertIn('read=Uid producer=AdbPackageList', result.stderr)
        self.assertIn('producer_pid=Unknown', result.stderr)
        self.assertIn('target=Unknown viewport=Unknown blocking=Unknown', result.stderr)
        self.assertEqual(result.stderr.count('Delivery UI:'), 1)
        self.assertNotIn('failure=predicate', result.stderr)
        self.assertNotIn('tap ', trace)
        self.assertNotIn('scroll ', trace)
        self.assertIn('scratch removed', trace)
        self.assertIn('kill 4242\nwait 4242\n', trace)

    def test_uid_inventory_rejection_is_not_an_acquisition_failure(self):
        result, trace = self.delivery('uid-invalid')
        self.assert_executed(result, trace)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('guard=uid_inventory failure=predicate status=1 error=GuardRejected', result.stderr)
        self.assertIn('read=Uid producer=AwkPackageUid', result.stderr)
        self.assertEqual(result.stderr.count('Delivery UI:'), 1)
        self.assertNotIn('failure=acquisition', result.stderr)
        self.assertNotIn('tap ', trace)
        self.assertNotIn('scroll ', trace)
        self.assertEqual(result.stdout, '')
        self.assertIn('scratch removed', trace)
        self.assertIn('kill 4242\nwait 4242\n', trace)

    def test_disabled_scroll_reports_its_own_control_facts(self):
        result, trace = self.delivery('scroll-disabled')
        self.assert_executed(result, trace)
        self.assertNotEqual(result.returncode, 0)
        records = [line for line in result.stderr.splitlines() if line.startswith('Delivery UI:')]
        self.assertEqual(len(records), 1, result.stderr)
        for fact in ('phase=mock', 'guard=settings_scroll_owner_enabled', 'failure=predicate',
                     'control_scope=SettingsScroll', 'action_owner_match=True', 'enabled=False',
                     'clickable=Unknown', 'visible=Unknown', 'target=Unknown', 'viewport=Unknown'):
            self.assertIn(fact, records[0])
        # Opening Settings is allowed; the disabled list cannot receive input.
        self.assertEqual(sum(line.startswith('tap ') for line in trace.splitlines()), 1, trace)
        self.assertNotIn('scroll ', trace)
        self.assertNotIn('SYNC', trace)
        self.assertEqual(result.stdout, '')
        self.assertIn('scratch removed', trace)
        self.assertIn('kill 4242\nwait 4242\n', trace)

    def test_native_acquisition_includes_service_focus_and_separates_window_records(self):
        result, trace = self.delivery()
        self.assert_executed(result, trace)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertGreaterEqual(trace.splitlines().count('native full'), 2)
        self.assertNotIn('native windows', trace)
        self.assertEqual(trace.splitlines().count('SYNC'), 1, trace)

    def test_guards_reject_before_the_intended_input(self):
        for mode in ('wrong-host', 'mock-on', 'disabled', 'foreign-sync'):
            with self.subTest(mode=mode):
                result, trace = self.delivery(mode)
                self.assert_executed(result, trace)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('HOLD:', result.stderr)
                self.assertNotIn('SYNC', trace)
                if mode == 'foreign-sync':
                    records = [line for line in result.stderr.splitlines()
                               if line.startswith('Delivery UI:')]
                    self.assertEqual(len(records), 1, result.stderr)
                    for fact in ('guard=sync_card_owner', 'semantic_match=False',
                                 'target=300,651,380,701', 'viewport=0,80,400,700'):
                        self.assertIn(fact, records[0])
                if mode == 'wrong-host':
                    self.assertNotIn('tap ', trace)
                    self.assertNotIn('scroll ', trace)

    def test_timeout_retains_independent_facts_and_original_deadline(self):
        for mode, publication, receipt in [('neither', 0, 0), ('send-only', 1, 0),
                                           ('receipt-only', 0, 1)]:
            with self.subTest(mode=mode):
                result, trace = self.delivery(mode)
                self.assert_executed(result, trace)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('HOLD:', result.stderr)
                self.assertIn(f'state publication={publication} receipt={receipt} elapsed=30', trace)
                self.assertIn(f'FRESH_PUBLICATION={publication} FRESH_RECEIPT={receipt}', result.stderr)
                self.assertIn('coverage=CompleteThroughBoundary', result.stderr)
                self.assertIn('causal absence remain Unknown', result.stderr)
                self.assertLessEqual(trace.splitlines().count('SYNC'), 1)
                for at, grace, limit in re.findall(r'budget at=(\d+) grace=([^ ]+) limit=(\d+)s', trace):
                    self.assertEqual(grace, '--kill-after=1s')
                    self.assertLessEqual(int(at) + int(limit) + 2, 40)

    def test_ui_readiness_cannot_renew_the_delivery_deadline(self):
        result, trace = self.delivery('expiry')
        self.assert_executed(result, trace)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Delivery deadline expired.', result.stderr)
        self.assertIn('elapsed=30', trace)
        self.assertNotIn('tap ', trace)
        self.assertNotIn('scroll ', trace)

    def test_stale_evidence_requalifies_from_a_new_complete_capture(self):
        # The first Mock proof capture ages during qualification. The proof performs
        # no input, so only the post-qualification check can discard it. The reveal
        # scroll and the Sync tap age at their input boundaries.
        result, trace = self.delivery('stale-once')
        self.assert_executed(result, trace)
        # Old/fixed assertion witness: only replacement captures can reach the one Sync.
        self.assertEqual(trace.splitlines().count('SYNC'), 1, trace + result.stderr)
        self.assertNotIn('STALE_INPUT', trace)
        self.assertEqual(sum(line.startswith('scroll ') for line in trace.splitlines()), 2, trace)
        # Five accepted captures plus a new complete one per discarded snapshot. Discards
        # spend their own ticks of the original budget, without added pacing.
        self.assertEqual(trace.splitlines().count('native full'), 16, trace)
        self.assertIn('state publication=1 receipt=1 elapsed=20', trace)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_persistent_stale_evidence_holds_without_input_at_the_original_deadline(self):
        result, trace = self.delivery('stale-always')
        self.assert_executed(result, trace)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('tap ', trace)
        self.assertNotIn('scroll ', trace)
        self.assertNotIn('SYNC', trace)
        # Requalification spends the same budget; it never resets or extends it.
        self.assertIn('state publication=0 receipt=0 elapsed=30', trace)
        self.assertIn('HOLD: Delivery deadline expired.', result.stderr)
        self.assertIn('stale_ui_snapshots=5', result.stderr)

    def test_persistent_stale_discards_retain_each_capture_and_the_unfinished_stage(self):
        result, trace = self.delivery('stale-always')
        self.assert_executed(result, trace)
        # Attribution witness: old and fixed source reach the same HOLD and count; only
        # the report's retained closed facts differ.
        self.assertIn('HOLD: Delivery deadline expired.', result.stderr)
        self.assertIn('stale_ui_snapshots=5', result.stderr)
        discards = [line for line in result.stderr.splitlines()
                    if line.startswith('Delivery UI discard:')]
        self.assertEqual(len(discards), 5, result.stderr)
        for number, record in enumerate(discards, 1):
            # Each replacement keeps its own capture tick and pre-input aging, while the
            # original deadline's remaining ticks only shrink.
            checked = 10 + 5 * number
            self.assertRegex(record, rf'^Delivery UI discard: invocation=\d+:{number} route=dashboard '
                             rf'site=before_tap captured={checked - 5} acquisition=0 parse=0 '
                             rf'qualification=0 pre_input=5 checked={checked} age=5 '
                             rf'remaining={40 - checked}$')
        # The deadline interrupts the sixth attempt before input; that stage keeps no duration.
        self.assertRegex(result.stderr, r'\nDelivery UI attempt: invocation=\d+:6 route=dashboard '
                         r'captured=35 acquisition=0 parse=0 qualification=0 pre_input=Unknown '
                         r'unfinished=pre_input since=35 remaining=5\n')

    def test_stale_discards_retain_their_check_site_and_aged_stage(self):
        # A window covering the revealed Sync control ends the once-stale sequence with its
        # own typed rejection, after the Mock-proof and reveal-scroll discards.
        result, trace = self.delivery('stale-once', obstruction='[300,640][390,690]')
        self.assert_executed(result, trace)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('SYNC', trace)
        self.assertIn('stale_ui_snapshots=2', result.stderr)
        rejections = [line for line in result.stderr.splitlines() if line.startswith('Delivery UI:')]
        self.assertEqual(len(rejections), 1, result.stderr)
        self.assertIn('guard=target_unobstructed', rejections[0])
        discards = [line for line in result.stderr.splitlines()
                    if line.startswith('Delivery UI discard:')]
        self.assertEqual(len(discards), 2, result.stderr)
        # The Mock proof aged during acquisition and never reached pre-input; the reveal
        # scroll aged at its pre-input boundary.
        self.assertRegex(discards[0], r'invocation=\d+:2 route=mock site=after_qualification '
                         r'captured=11 acquisition=5 parse=0 qualification=0 pre_input=Unknown '
                         r'checked=16 age=5 remaining=24$')
        self.assertRegex(discards[1], r'invocation=\d+:5 route=sync site=before_scroll '
                         r'captured=18 acquisition=0 parse=0 qualification=0 pre_input=5 '
                         r'checked=23 age=5 remaining=17$')
        self.assertRegex(result.stderr, r'\nDelivery UI attempt: invocation=\d+:7 route=sync '
                         r'captured=24 acquisition=0 parse=Unknown qualification=Unknown '
                         r'pre_input=Unknown unfinished=parse since=24 remaining=16\n')

    def test_each_age_check_accepts_four_ticks_and_discards_five(self):
        # Each mode ages one capture once, by its final tick count, after every earlier check
        # has accepted it: the first Dashboard capture during acquisition, or qualified
        # evidence before the Settings tap or the second reveal scroll. No events arrive, so
        # the report at the original deadline retains any discard.
        for mode, site, invocation, route, captured in [
                ('aged-qualification', 'after_qualification', 1, 'dashboard', 10),
                ('aged-tap', 'before_tap', 1, 'dashboard', 10),
                ('aged-scroll', 'before_scroll', 4, 'sync', 13)]:
            for age in (4, 5):
                with self.subTest(site=site, age=age):
                    result, trace = self.delivery(f'{mode}-{age}')
                    self.assert_executed(result, trace)
                    discards = [line for line in result.stderr.splitlines()
                                if line.startswith('Delivery UI discard:')]
                    if age == 4:
                        # Old/fixed assertion witness: the input acts on the original capture
                        # at age 4, without a discard or replacement capture.
                        self.assertIn(f'input captured={captured} at={captured + 4}\n', trace,
                                      trace + result.stderr)
                        self.assertEqual(discards, [], result.stderr)
                        self.assertIn('stale_ui_snapshots=0', result.stderr)
                    else:
                        # The aged capture receives no input; its own check site discards it.
                        self.assertNotIn(f'input captured={captured} ', trace)
                        self.assertEqual(len(discards), 1, result.stderr)
                        stages = ('acquisition=5 parse=0 qualification=0 pre_input=Unknown'
                                  if site == 'after_qualification' else
                                  'acquisition=0 parse=0 qualification=0 pre_input=5')
                        self.assertRegex(discards[0], rf'^Delivery UI discard: invocation=\d+:{invocation} '
                                         rf'route={route} site={site} captured={captured} {stages} '
                                         rf'checked={captured + 5} age=5 remaining={35 - captured}$')
                        self.assertIn('stale_ui_snapshots=1', result.stderr)
                    self.assertNotIn('STALE_INPUT', trace)
                    # Either way the route still reaches its two reveal scrolls and one Sync.
                    self.assertEqual(sum(line.startswith('scroll ') for line in trace.splitlines()),
                                     2, trace)
                    self.assertEqual(trace.splitlines().count('SYNC'), 1, trace)
                    self.assertIn('state publication=0 receipt=0 elapsed=30', trace)

    def test_signal_at_the_next_route_reports_only_that_attempt_through_cleanup(self):
        # A real TERM at the first boundary exposing the route after a discard reaches the
        # signal trap and the failing EXIT cleanup, whose report reads that transition.
        result, trace = self.delivery('stale-always', interrupt=True)
        self.assert_executed(result, trace)
        self.assertEqual(result.returncode, 143, result.stderr)
        self.assertEqual(result.stdout, '')
        self.assertNotIn('HOLD:', result.stderr)
        self.assertNotIn('tap ', trace)
        self.assertIn('device rmdir /data/local/tmp/wardpulse-sync-abcdefgh', trace)
        self.assertIn('kill 4242\nwait 4242\n', trace)
        self.assertIn('scratch removed', trace)
        reports = [line for line in result.stderr.splitlines() if line.startswith('Delivery: ')]
        self.assertEqual(len(reports), 1, result.stderr)
        # Coherence witness: that route pairs only with its own new invocation, Unknown
        # facts and the open preparation stage, never the discarded attempt's capture,
        # closed durations or stage.
        attempts = [line for line in result.stderr.splitlines()
                    if line.startswith('Delivery UI attempt:')]
        self.assertEqual(len(attempts), 1, result.stderr)
        self.assertRegex(attempts[0], r'^Delivery UI attempt: invocation=\d+:2 route=dashboard '
                         r'captured=Unknown acquisition=Unknown parse=Unknown qualification=Unknown '
                         r'pre_input=Unknown unfinished=preparation since=15 remaining=25$')
        # The discarded attempt's closed durations stay in its own record.
        discards = [line for line in result.stderr.splitlines()
                    if line.startswith('Delivery UI discard:')]
        self.assertEqual(len(discards), 1, result.stderr)
        self.assertRegex(discards[0], r'^Delivery UI discard: invocation=\d+:1 route=dashboard '
                         r'site=before_tap captured=10 acquisition=0 parse=0 qualification=0 '
                         r'pre_input=5 checked=15 age=5 remaining=25$')
        self.assertRegex(reports[0], r'^Delivery: phase=dashboard elapsed=5s remaining=25s '
                         r'process_proof=Unknown .* stale_ui_snapshots=1$')

    def test_observation_loss_is_strict_and_coverage_is_unknown(self):
        for mode in ('gap', 'late-gap'):
            with self.subTest(mode=mode):
                result, trace = self.delivery(mode)
                self.assert_executed(result, trace)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Event loss or monitoring gap.', result.stderr)
                if mode == 'gap':
                    self.assertIn('role=phone last_completed=Unknown coverage=Incomplete', result.stderr)
                    self.assertNotIn('tap ', trace)
                    self.assertNotIn('scroll ', trace)
                else:
                    self.assertIn('FRESH_PUBLICATION=1 FRESH_RECEIPT=0', result.stderr)
                    self.assertRegex(result.stderr, r'role=wear last_completed=\d+@\d+ coverage=Incomplete')

    def test_failed_delivery_diagnostics_do_not_abandon_cleanup(self):
        for mode, expected in [('report', 23), ('remove-failed', 1)]:
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(
                    prefix='work-delivery-cleanup-', dir=OWNER) as scratch:
                directory = Path(scratch)
                owned = directory / 'owned'
                owned.mkdir()
                script = r'''
set -euo pipefail
SCRATCH=$1/owned TRACE=$1/trace MODE=$2 PHONE_SERIAL=phone
unset SECONDS
SECONDS=20
DELIVERY_ACTIVE=1 DELIVERY_REPORTED=0 DELIVERY_STARTED=10 DELIVERY_DEADLINE=40
DELIVERY_PHASE=delivery DELIVERY_PROCESS_PROOF=Unknown DELIVERY_SYNC_ATTEMPTED=0
DELIVERY_UI_DIR=/data/local/tmp/wardpulse-sync-abcdefgh
FRESH_PUBLICATION=0 FRESH_RECEIPT=0
declare -A DELIVERY_BOUNDARY=() DELIVERY_COVERAGE=()
READER_HOST= READER_DIAG_HOST= READER_DEVICE_PID= READER_STAGE_ACTIVE=0
READER_INPUT_FD= READER_OUTPUT_FD= READER_STDERR_FD= READER_STDERR_DRAIN_FD=
READER_DIAG_OUTPUT_FAILED=0 DEVICE_SCRATCH=
MONITORS=(4242)
adb_on() {
  printf 'device %s\n' "$*" >>"$TRACE"
  [[ "$MODE" != remove-failed || "$*" != *'rm -f'* ]]
}
reader_diagnostic() { :; }
kill() { printf 'kill %s\n' "$*" >>"$TRACE"; }
wait() { printf 'wait %s\n' "$*" >>"$TRACE"; }
'''
                script += '\n'.join(shell_function(name) for name in
                                    ['delivery_report', 'cleanup'])
                script += '\ntrap cleanup EXIT\nexec 2>&-\nexit 23\n'
                result = subprocess.run(['bash', '-c', script, 'delivery-cleanup', scratch, mode],
                                        text=True, capture_output=True, timeout=5)
                self.assertEqual(result.returncode, expected, result.stderr)
                trace = (directory / 'trace').read_text()
                self.assertIn('rm -f /data/local/tmp/wardpulse-sync-abcdefgh/hierarchy.xml', trace)
                self.assertIn('kill 4242\nwait 4242\n', trace)
                self.assertFalse(owned.exists())
        result, trace = self.delivery('obstructed-closed')
        self.assertEqual(result.returncode, 1)
        self.assertIn('scratch removed', trace)
        self.assertIn('device rm -f /data/local/tmp/wardpulse-sync-abcdefgh/hierarchy.xml', trace)
        self.assertIn('device rmdir /data/local/tmp/wardpulse-sync-abcdefgh', trace)
        self.assertIn('kill 4242\nwait 4242\n', trace)
        self.assertNotIn('tap ', trace)
        self.assertNotIn('scroll ', trace)

    def test_undrained_stderr_cannot_stall_failed_delivery_cleanup(self):
        # Unlike a closed stream, an open full pipe blocks every unbounded write. Expired
        # delivery must still attempt both owned staging removals, keep their failure and
        # retire the monitor with its original status.
        with tempfile.TemporaryDirectory(prefix='work-delivery-backpressure-', dir=OWNER) as scratch:
            directory = Path(scratch)
            owned = directory / 'owned'
            owned.mkdir()
            (directory / 'trace').write_text('')
            script = r'''
set -euo pipefail
SCRATCH=$1/owned TRACE=$1/trace PHONE_SERIAL=phone OBSERVING=0
unset SECONDS
SECONDS=40
DELIVERY_ACTIVE=1 DELIVERY_REPORTED=0 DELIVERY_STARTED=10 DELIVERY_DEADLINE=40
DELIVERY_PHASE=delivery DELIVERY_PROCESS_PROOF=Unknown DELIVERY_SYNC_ATTEMPTED=0
DELIVERY_UI_DIR=/data/local/tmp/wardpulse-sync-abcdefgh
FRESH_PUBLICATION=0 FRESH_RECEIPT=0
declare -A DELIVERY_BOUNDARY=() DELIVERY_COVERAGE=()
READER_HOST= READER_DIAG_HOST= READER_DEVICE_PID= READER_STAGE_ACTIVE=0
READER_INPUT_FD= READER_OUTPUT_FD= READER_STDERR_FD= READER_STDERR_DRAIN_FD=
READER_DIAG_OUTPUT_FAILED=0 DEVICE_SCRATCH=/data/local/tmp/wardpulse-sync.abcdefgh
MONITORS=(4242)
adb_on() { printf 'device %s\n' "$*" >>"$TRACE"; return 1; }
reader_diagnostic() { printf "$@" >>"$TRACE"; }
kill() { printf 'kill %s\n' "$*" >>"$TRACE"; }
wait() { printf 'wait %s\n' "$*" >>"$TRACE"; }
'''
            script += '\n'.join(shell_function(name) for name in
                                ['hold', 'delivery_report', 'delivery_check_time',
                                 'remove_reader_staging', 'cleanup'])
            script += '\ntrap cleanup EXIT\ndelivery_check_time\n'
            read_end, write_end = os.pipe()
            try:
                # Fill without blocking, then hand writers ordinary blocking backpressure.
                os.set_blocking(write_end, False)
                try:
                    while True:
                        os.write(write_end, bytes(65536))
                except BlockingIOError:
                    pass
                os.set_blocking(write_end, True)
                try:
                    status = subprocess.run(
                        ['bash', '-c', script, 'delivery-backpressure', scratch],
                        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                        stderr=write_end, timeout=5).returncode
                except subprocess.TimeoutExpired:
                    status = None
            finally:
                os.close(read_end)
                os.close(write_end)
            trace = (directory / 'trace').read_text()
            # Cleanup effects precede the status: a blocked source fails on the first
            # missing effect, never on the subprocess bound alone.
            self.assertIn('device phone shell -n rm -f '
                          '/data/local/tmp/wardpulse-sync-abcdefgh/hierarchy.xml\n', trace)
            self.assertIn('device phone shell -n rm -f '
                          '/data/local/tmp/wardpulse-sync.abcdefgh/reader.dex\n', trace)
            self.assertIn('staging=failed result=1\n', trace)
            self.assertIn('kill 4242\nwait 4242\n', trace)
            self.assertFalse(owned.exists())
            self.assertEqual(status, 1, trace)


class InventoryTests(unittest.TestCase):
    def inventory(self, lists=None, starts=None, absence=None, released=1,
                  observer=True, boots=None, role='phone', header='UID PID NAME',
                  phase='', action='', acquisition=0):
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
# Fixture exhaustion stays visible even where the device body discards read errors.
exec 9>&2
take() {
  local key=$1 index=0 value
  if [[ -f "$SCENARIO/$key.index" ]]; then read -r index <"$SCENARIO/$key.index"; fi
  printf '%s\n' "$((index + 1))" >"$SCENARIO/$key.index"
  value=$(command cat "$SCENARIO/$key.$index" 2>&9) || return 1
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
OBSERVER=$5 OBSERVER_RELEASED=$6 OBSERVING=0 PHASE=$7 LIFECYCLE_ACTION=$8 ACQUISITION=$9
hold() { printf 'HOLD: %s\n' "$*" >&2; exit 1; }
# Asserted records cannot depend on the diagnostic writer's wall-clock bound.
timeout() { shift 2; "$@"; }
adb_on() {
  (( ! ACQUISITION )) || return "$ACQUISITION"
  bash -c "$DEVICE"$'\n'"$4"$'\n'"$5"
}
export SCENARIO
'''
            result = subprocess.run([
                'bash', '-c', script + '\n'.join(shell_function(name) for name in
                                                 ['process_diagnostic', 'processes', 'app_processes'])
                + '\napp_processes device "$ROLE" "$PHASE"\n',
                'work-inventory', scratch, device, role, BOOT_ID,
                f'42 200 {OBSERVER_NAME}' if observer else '', str(released),
                phase, action, str(acquisition),
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

    def test_distinct_rejections_retain_only_their_own_closed_facts(self):
        # Representative distinct rejection paths. Facts come only from each failing
        # sample; injected rows, stat records and boot identities never leave it.
        other_boot = '00000000-0000-0000-0000-000000000002'
        foreign = '10999 77 private.other\n'
        for kwargs, facts in [
                ({'acquisition': 124, 'role': 'wear', 'observer': False,
                  'phase': 'post-update', 'action': 'wear:update'},
                 'role=wear action=wear:update phase=post-update guard=acquisition '
                 'traversal=Unknown boundary=Unknown subject=Unknown status=124'),
                ({'lists': [foreign + '10123 41 private-name'] * 4},
                 'guard=list_rows traversal=first boundary=before subject=Unknown status=1'),
                ({'starts': {'start.41': ['100', '100', None]}},
                 'guard=stat_read traversal=second boundary=before subject=app status=1'),
                ({'starts': {'start.41': ['01']}},
                 'guard=start_value traversal=first boundary=before subject=app status=1'),
                ({'starts': {'start.42': ['201']}},
                 'guard=observer_start traversal=first boundary=before subject=observer status=1'),
                ({'lists': [APP_ROW] * 3 + [APP_ROW + '\n10123 43 app.wardpulse:private'],
                  'starts': {'start.43': ['300']}},
                 'guard=boundary_mismatch traversal=second boundary=after subject=Unknown status=1'),
                ({'boots': [BOOT_ID, other_boot]},
                 'guard=boot_continuity traversal=Unknown boundary=Unknown subject=Unknown status=1'),
                ({'boots': [other_boot] * 2},
                 'guard=expected_boot traversal=Unknown boundary=Unknown subject=Unknown status=0')]:
            with self.subTest(facts=facts):
                result = self.inventory(**kwargs)
                self.assert_rejected(result)
                records = [line for line in result.stderr.splitlines()
                           if line.startswith('Process identity: ')]
                self.assertEqual(len(records), 1, result.stderr)
                self.assertIn(facts, records[0])
                for raw in ('private', '(process)', '300', OBSERVER_NAME, BOOT_ID, other_boot):
                    self.assertNotIn(raw, result.stderr)

    def test_undrained_stderr_cannot_stall_process_rejection_cleanup(self):
        # Ordinary HOLDs run with OBSERVING=0 and DELIVERY_ACTIVE=0. An open full pipe
        # blocks every unbounded write; a rejected pre-update sample must still pass its
        # own HOLD and the outer update HOLD into owned cleanup with its original status.
        with tempfile.TemporaryDirectory(prefix='work-inventory-backpressure-', dir=OWNER) as scratch:
            directory = Path(scratch)
            owned = directory / 'owned'
            owned.mkdir()
            (directory / 'app.apk').write_text('apk\n')
            (directory / 'trace').write_text('')
            script = r'''
set -euo pipefail
SCRATCH=$1/owned TRACE=$1/trace APP_ID=app.wardpulse PHONE_SERIAL=phone
OBSERVING=0 DELIVERY_ACTIVE=0 DELIVERY_UI_DIR= LIFECYCLE_ACTION= OBSERVER= OBSERVER_RELEASED=0
declare -A UIDS=([phone]=10123) BOOT=([phone]=00000000-0000-0000-0000-000000000001)
READER_HOST= READER_DIAG_HOST= READER_DEVICE_PID= READER_STAGE_ACTIVE=0
READER_INPUT_FD= READER_OUTPUT_FD= READER_STDERR_FD= READER_STDERR_DRAIN_FD=
READER_DIAG_OUTPUT_FAILED=0 DEVICE_SCRATCH=/data/local/tmp/wardpulse-sync.abcdefgh
MONITORS=(4242)
adb_on() {
  case "${*:4}" in
    'cmd package list packages -U app.wardpulse') printf 'package:app.wardpulse uid:10123\n' ;;
    'dumpsys package app.wardpulse') printf '  lastUpdateTime=2026-01-01 00:00:00\n' ;;
    'uid=10123 '*)
      # The device rejects its first list with one closed record and status 1.
      printf 'device %s processes\n' "$1" >>"$TRACE"
      printf 'reject list_rows first before Unknown\n'
      return 1 ;;
    'rm -f /data/local/tmp/wardpulse-sync.abcdefgh/reader.dex'|'rmdir /data/local/tmp/wardpulse-sync.abcdefgh')
      printf 'device %s\n' "$*" >>"$TRACE" ;;
    *) printf 'UNEXPECTED_EFFECT\n' >>"$TRACE"; return 2 ;;
  esac
}
barrier() { printf 'barrier %s\n' "$1" >>"$TRACE"; }
sleep() { :; }
reader_diagnostic() { printf "$@" >>"$TRACE"; }
kill() { printf 'kill %s\n' "$*" >>"$TRACE"; }
wait() { printf 'wait %s\n' "$*" >>"$TRACE"; }
'''
            # Production HOLD, writers, update and cleanup, with the real timeout bound.
            script += '\n'.join(shell_function(name) for name in
                                ['hold', 'process_diagnostic', 'processes', 'app_processes',
                                 'package_uid', 'parse_package_uid', 'package_update_time',
                                 'update_install', 'remove_reader_staging', 'cleanup'])
            script += '\ntrap cleanup EXIT\nupdate_install phone "$PHONE_SERIAL" "$1/app.apk"\n'
            read_end, write_end = os.pipe()
            try:
                # Fill without blocking, then hand writers ordinary blocking backpressure.
                os.set_blocking(write_end, False)
                try:
                    while True:
                        os.write(write_end, bytes(65536))
                except BlockingIOError:
                    pass
                os.set_blocking(write_end, True)
                try:
                    status = subprocess.run(
                        ['bash', '-c', script, 'inventory-backpressure', scratch],
                        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                        stderr=write_end, timeout=5).returncode
                except subprocess.TimeoutExpired:
                    status = None
            finally:
                os.close(read_end)
                os.close(write_end)
            trace = (directory / 'trace').read_text()
            # Setup reaches exactly one rejected sample, without retry or another effect.
            self.assertEqual(trace.count('device phone processes\n'), 1, trace)
            self.assertNotIn('UNEXPECTED_EFFECT', trace)
            # Cleanup effects precede the status: a blocked source fails on the first
            # missing effect, never on the subprocess bound alone.
            self.assertIn('device phone shell -n rm -f '
                          '/data/local/tmp/wardpulse-sync.abcdefgh/reader.dex\n'
                          'device phone shell -n rmdir /data/local/tmp/wardpulse-sync.abcdefgh\n',
                          trace)
            self.assertIn('staging=removed result=1\n', trace)
            self.assertIn('kill 4242\nwait 4242\n', trace)
            self.assertFalse(owned.exists())
            self.assertEqual(status, 1, trace)


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
                                ['process_diagnostic', 'processes', 'app_processes',
                                 'check_separation', 'work_snapshot'])
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

    def undrained_cleanup(self, mode):
        # Production reader lifecycle, HOLD and cleanup under an open, full, undrained
        # stderr. Only the trace outside the owned scratch survives cleanup.
        with tempfile.TemporaryDirectory(prefix='work-reader-backpressure-', dir=OWNER) as scratch:
            directory = Path(scratch)
            owned = directory / 'owned'
            owned.mkdir()
            (directory / 'trace').write_text('')
            adb = directory / 'adb'
            adb.write_text('''#!/bin/bash
set -eu
if [[ "$MODE" == pre-handshake ]]; then
  # The failing reader leaves another app-UID process before any handshake.
  : >"$SCENARIO/lingering"
  printf 'HOLD READER_UNSUPPORTED_OR_RACED\\n'
  exit 1
fi
printf 'READER 42 200\\n'
IFS= read -r go
[[ "$go" == GO ]] || exit 1
printf 'END 42 200\\n'
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
  if [[ "$uid" == 10123 && -e "$SCENARIO/lingering" ]]; then printf '10123 43 app.wardpulse\n'; fi
}
awk() {
  if [[ "${!#}" == /proc/*/stat ]]; then printf '200\n'; else command awk "$@"; fi
}
cat() {
  if [[ "$*" == /proc/sys/kernel/random/boot_id ]]; then printf '%s\n' "$EXPECTED_BOOT"
  else command cat "$@"; fi
}
'''
            script = r'''
set -euo pipefail
SCRATCH=$1/owned TRACE=$1/trace SCENARIO=$1 ADB=$1/adb MODE=$2 DEVICE=$3 EXPECTED_BOOT=$4
export SCENARIO MODE EXPECTED_BOOT
unset SECONDS
SECONDS=10
PHONE_SERIAL=phone WEAR_SERIAL=wear
declare -A UIDS=([phone]=10123 [wear]=10124) BOOT=([phone]=$4 [wear]=$4)
RETAINING=0 PRE_DEATH_DEADLINE=0 OBSERVER= OBSERVER_RELEASED=0 EVENTS=
OBSERVING=0 DELIVERY_ACTIVE=0 DELIVERY_UI_DIR= LIFECYCLE_ACTION=
READER_HOST= READER_DIAG_HOST= READER_DEVICE_PID= READER_STAGE_ACTIVE=0 READER_BEFORE_PHONE=
READER_INPUT_FD= READER_OUTPUT_FD= READER_STDERR_FD= READER_STDERR_DRAIN_FD=
READER_DIAG_OUTPUT_FAILED=0 DEVICE_SCRATCH=/data/local/tmp/wardpulse-sync.abcdefgh
MONITORS=(4242)
barrier() { EVENTS=; }
installed_apk() { printf 'apk'; }
reader_diagnostic() { printf "$@" >>"$TRACE"; }
reader_stderr() { :; }
reader_stderr_collect() { cat >/dev/null; }
# The controlled clock crosses each unchanged eight-second budget after one retry.
sleep() { printf 'sleep %s\n' "$1" >>"$TRACE"; SECONDS=$((SECONDS + 8)); }
adb_on() {
  case "$4" in
    uid=*) printf 'device %s\n' "${4%% *}" >>"$TRACE"; bash -c "$DEVICE"$'\n'"$4"$'\n'"$5" ;;
    # Reader PID absence stays unproved; staging removal would be traced as an effect.
    *) printf 'device %s\n' "${*:4}" >>"$TRACE"; return 1 ;;
  esac
}
# Only the owned monitor is fake; reader jobs keep the real kill/wait.
kill() { if [[ "$*" == 4242 ]]; then printf 'kill %s\n' "$*" >>"$TRACE"; else builtin kill "$@"; fi; }
wait() { if [[ "$*" == 4242 ]]; then printf 'wait %s\n' "$*" >>"$TRACE"; else builtin wait "$@"; fi; }
'''
            script += '\n'.join(shell_function(name) for name in
                                ['hold', 'process_diagnostic', 'processes', 'app_processes',
                                 'work_snapshot', 'remove_reader_staging', 'cleanup'])
            script += '\ntrap cleanup EXIT\nwork_snapshot sample\n'
            read_end, write_end = os.pipe()
            try:
                # Fill without blocking, then hand writers ordinary blocking backpressure.
                os.set_blocking(write_end, False)
                try:
                    while True:
                        os.write(write_end, bytes(65536))
                except BlockingIOError:
                    pass
                os.set_blocking(write_end, True)
                try:
                    status = subprocess.run(
                        ['bash', '-c', script, 'reader-backpressure', scratch, mode, device, BOOT_ID],
                        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                        stderr=write_end, timeout=5).returncode
                except subprocess.TimeoutExpired:
                    status = None
            finally:
                os.close(read_end)
                os.close(write_end)
            return status, (directory / 'trace').read_text(), owned.exists()

    def test_undrained_stderr_cannot_stall_unproved_reader_cleanup(self):
        # Each case leaves work_snapshot with its reader flags populated and reaches one
        # cleanup retirement HOLD. Staging stays retained, and the remaining owned cleanup
        # must still retire the monitor and scratch with status 1.
        cases = [
            # After the qualified handshake, the reader PID's absence stays unproved.
            ('unproved-retirement', 'device test ! -e /proc/42\n', 3,
             'device_pid=unproved uid=unobserved'),
            # Before any handshake, a new identity stays in the app UID.
            ('pre-handshake', 'device uid=10123\n', 3, 'device_pid=unobserved uid=unproved'),
        ]
        for mode, attempt, attempts, retirement in cases:
            with self.subTest(mode=mode):
                status, trace, scratch_remains = self.undrained_cleanup(mode)
                # The reader failure reaches cleanup's loop, whose one retry ends its budget.
                self.assertEqual(trace.count(attempt), attempts, trace)
                self.assertEqual(trace.count('sleep 0.2\n'), 1, trace)
                self.assertNotIn('device rm', trace)
                # Owned cleanup precedes the wording and status: a blocked source fails on
                # the missing monitor retirement, never on the summary or subprocess bound.
                self.assertIn('kill 4242\nwait 4242\n', trace)
                self.assertFalse(scratch_remains)
                self.assertIn(f'Reader cleanup: descriptors=closed {retirement} '
                              'staging=retained result=1\n', trace)
                self.assertEqual(status, 1, trace)


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
    print(f'Shell source: {SHELL_SOURCE.resolve()} SHA256={hashlib.sha256(SHELL.encode()).hexdigest()}')
    started = time.monotonic()
    try:
        unittest.main()
    finally:
        print(f'Inventory/metadata/protocol regression elapsed: {time.monotonic() - started:.3f}s')
