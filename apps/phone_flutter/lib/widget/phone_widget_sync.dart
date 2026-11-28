import 'dart:async';

import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

import '../dashboard/connection_snapshot_cache.dart';
import '../dashboard/dashboard_models.dart';
import '../sync/data_mode.dart';
import 'phone_widget_payload.dart';
import 'phone_widget_preferences.dart';

/// Android AppWidgetProvider simple class name (see `WardPulseAppWidget`).
const phoneWidgetProviderName = 'WardPulseAppWidget';

/// Fully-qualified Android provider for [HomeWidget.updateWidget].
const phoneWidgetQualifiedAndroidName = 'app.wardpulse.WardPulseAppWidget';

/// `developer.log` channel for launcher-widget failures.
const phoneWidgetLogName = 'WardPulse.PhoneWidget';

const _publicationChannel = MethodChannel('app.wardpulse/widget_publication');

/// A load's claim on the shared launcher publication, taken before it reads
/// settings or provider data.
///
/// Android orders replacement of the shared accepted snapshot by [load]
/// across engines ([accept]) and issues a publication ticket only while that
/// snapshot, its source selection and the settings it read stay current
/// through the commit. A sync run in [run] carries the claim to the ticket.
final class PhoneWidgetPublicationInput {
  const PhoneWidgetPublicationInput({
    this.load,
    this.settingsRevision,
    this.observed,
    this.established = true,
    this.awaitingDelivery = false,
    this.selection,
  });

  /// No native authority orders publications on this host.
  static const unordered = PhoneWidgetPublicationInput();

  /// Unavailable order: no ticket and no STALE mark.
  static const unavailable = PhoneWidgetPublicationInput(
    load: -1,
    observed: -1,
  );

  final int? load;

  /// The settled settings revision the published rows were built from; `-1`
  /// when a save was in flight.
  final int? settingsRevision;

  /// The committed publication this load observed before it read anything;
  /// its failure may mark only those rows STALE.
  final int? observed;

  /// Whether the current mode already owns a full publication of the saved
  /// settings that every installed widget holds a frame of; STALE marks,
  /// unpublished saves and undelivered widgets leave it unset. A skipped poll
  /// still publishes the retained input until it does ([isEstablished]).
  final bool established;

  /// Whether this load began while committed rows of the saved settings
  /// still awaited an installed widget's first delivery, which accepting a
  /// newer load retires.
  final bool awaitingDelivery;

  /// [snapshotSelectionProof] arguments for a Live ticket.
  final Map<String, Object>? selection;

  static final _zoneKey = Object();

  static PhoneWidgetPublicationInput? get current =>
      Zone.current[_zoneKey] as PhoneWidgetPublicationInput?;

  Future<T> run<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_zoneKey: this});

  PhoneWidgetPublicationInput _withSelection(Map<String, Object>? selection) =>
      PhoneWidgetPublicationInput(
        load: load,
        settingsRevision: settingsRevision,
        observed: observed,
        established: established,
        awaitingDelivery: awaitingDelivery,
        selection: selection,
      );

  /// This claim for rows built from settings at [revision], such as the
  /// foreground's confirmed in-memory choices.
  PhoneWidgetPublicationInput withSettingsRevision(int? revision) =>
      PhoneWidgetPublicationInput(
        load: load,
        settingsRevision: revision ?? -1,
        observed: observed,
        established: established,
        awaitingDelivery: awaitingDelivery,
        selection: selection,
      );

  /// Records [snapshot] as the shared accepted input once its source is
  /// validated, whether or not a surface publishes it.
  ///
  /// Returns `false` when a newer load was accepted or the source retired.
  Future<bool> accept(DashboardSnapshot snapshot) async {
    final load = this.load;
    if (load == null) return true;
    if (load < 0) return false;
    final operation = DataModeOperation.current;
    try {
      final accepted = await _publicationChannel.invokeMethod<bool>('accept', {
        'load': load,
        if (operation?.mode == DataMode.live)
          'selection': snapshotSelectionProof(snapshot),
        ...?operation?.fetchArguments,
      });
      return accepted == true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  /// [established], rechecked on an ordered load once it was [accept]ed:
  /// that acceptance retires the first delivery of rows a widget has not
  /// received, so only a fresh publication still reaches it, while a widget
  /// framed since the claim needs none.
  Future<bool> isEstablished() async {
    final load = this.load;
    if (load == null || load < 0) return established;
    try {
      return await _publicationChannel.invokeMethod<bool>('established') ==
          true;
    } on MissingPluginException {
      return established;
    } on PlatformException {
      return false;
    }
  }

  /// [awaitingDelivery], read again on an ordered load once it was
  /// [accept]ed: rows committed since the claim may await a first delivery
  /// that acceptance retired, while rows delivered since then await none.
  Future<bool> isAwaitingDelivery() async {
    final load = this.load;
    if (load == null || load < 0) return awaitingDelivery;
    try {
      final awaiting = await _publicationChannel.invokeMethod<bool>(
        'awaitingDelivery',
      );
      return awaiting == true;
    } on MissingPluginException {
      return awaitingDelivery;
    } on PlatformException {
      return awaitingDelivery;
    }
  }

  /// Takes the next load ordinal before the load reads settings or providers.
  static Future<PhoneWidgetPublicationInput> begin() async {
    final Object? reply;
    try {
      reply = await _publicationChannel.invokeMethod<Object?>('beginLoad');
    } on MissingPluginException {
      return unordered;
    } on PlatformException {
      return unavailable;
    }
    if (reply case {
      'load': final int load,
      'observed': final int observed,
      'established': final bool established,
    }) {
      final revision = (reply as Map)['settingsRevision'];
      return PhoneWidgetPublicationInput(
        load: load,
        // A save in flight retires the read; no revision matches it.
        settingsRevision: revision is int ? revision : -1,
        observed: observed,
        established: established,
        awaitingDelivery: reply['awaitingDelivery'] == true,
      );
    }
    return unavailable;
  }

  /// Orders [save] against revision-tagged reads in every engine.
  ///
  /// Returns the settled revision after it, or `null` while another save is
  /// in flight or without a native authority. Unless [watch] is `false`, for
  /// a save that leaves the watch summary's content alone, the desired watch
  /// item is retired durably too. A failed [save], or one native could not
  /// begin, throws [SettingsWriteFailure].
  static Future<int?> saveSettings(
    Future<void> Function() save, {
    bool watch = true,
  }) async {
    final Object? token;
    try {
      token = await _publicationChannel.invokeMethod<Object?>(
        'beginSettingsWrite',
        watch ? null : const {'watch': false},
      );
    } on MissingPluginException {
      await save();
      return null;
    } on PlatformException catch (error, stackTrace) {
      // Native finished the save it could not begin; [save] never runs.
      final revision = error.details;
      throw SettingsWriteFailure(
        error,
        stackTrace,
        revision is int ? revision : null,
      );
    }
    Future<int?> finish() async {
      final revision = await _publicationChannel.invokeMethod<Object?>(
        'finishSettingsWrite',
        {'token': token},
      );
      return revision is int ? revision : null;
    }

    try {
      await save();
    } catch (error, stackTrace) {
      throw SettingsWriteFailure(error, stackTrace, await finish());
    }
    return finish();
  }
}

/// A settings write that failed after a native authority began it, or that
/// the authority could not begin.
///
/// Native may have retired what the settings feed, and it advanced the shared
/// revision. With a settled [settingsRevision], a caller notes it and
/// schedules the replacement a successful save would before reporting
/// [error]; without one, the save still in flight settles the revision and
/// replaces what both retired.
final class SettingsWriteFailure implements Exception {
  const SettingsWriteFailure(
    this.error,
    this.stackTrace,
    this.settingsRevision,
  );

  final Object error;
  final StackTrace stackTrace;
  final int? settingsRevision;

  @override
  String toString() => 'SettingsWriteFailure: $error';
}

/// Pushes [snapshot] metrics onto the Android home-screen widget.
///
/// Throws when the write fails. Callers decide what a stale launcher tile is
/// worth to them: the foreground app keeps rendering, the headless worker keeps
/// its run green.
abstract interface class PhoneWidgetSyncService {
  /// Publishes under the [PhoneWidgetPublicationInput.current] claim.
  ///
  /// Completes with `false` when no committed rows represent the request:
  /// [isCurrent] retired it, a newer request superseded it, or the native
  /// authority refused it because its mode generation retired or a newer
  /// accepted load, a settings save or a retired source owns the launcher.
  Future<bool> sync(
    DashboardSnapshot snapshot,
    PhoneWidgetPreferences preferences, {
    PhoneWidgetSyncGuard isCurrent = _alwaysCurrent,
  });

  Future<PhoneWidgetPublicationInput> beginLoad();

  /// Orders a widget, ring or alert-rule save before later publication
  /// tickets. A save with [watch] `false` leaves the watch summary's content
  /// alone, so its desired item stays answerable to Wear.
  ///
  /// Returns the settled settings revision after it, when known. A failed
  /// write that a native authority began throws [SettingsWriteFailure].
  Future<int?> saveSettings(Future<void> Function() save, {bool watch = true});

  /// Redraws installed widgets from current-generation rows, or empty.
  Future<void> redraw();
}

/// No-op for widget tests and hosts without a launcher surface.
final class DisabledPhoneWidgetSyncService implements PhoneWidgetSyncService {
  const DisabledPhoneWidgetSyncService();

  @override
  Future<bool> sync(
    DashboardSnapshot snapshot,
    PhoneWidgetPreferences preferences, {
    PhoneWidgetSyncGuard isCurrent = _alwaysCurrent,
  }) async => true;

  @override
  Future<PhoneWidgetPublicationInput> beginLoad() async =>
      PhoneWidgetPublicationInput.unordered;

  @override
  Future<int?> saveSettings(
    Future<void> Function() save, {
    bool watch = true,
  }) async {
    await save();
    return null;
  }

  @override
  Future<void> redraw() async {}
}

/// Whether a request still owns the widget; checked before each plugin call.
typedef PhoneWidgetSyncGuard = Future<bool> Function();

Future<bool> _alwaysCurrent() async => true;

/// Persists a widget payload; completes with `true` once its rows committed.
typedef PhoneWidgetPayloadWriter =
    Future<bool> Function(
      PhoneWidgetPayload payload, {
      required PhoneWidgetSyncGuard isCurrent,
    });

/// Serializes overlapping syncs in one Flutter isolate (latest wins).
///
/// Foreground UI and headless WorkManager each get their own isolate, so this
/// only coalesces callers that share the same engine. Across engines, native
/// publication tickets order complete publications. Each request keeps its
/// own guard and claim; once the guard expires, subsequent effects stop. A
/// call already dispatched cannot be retracted.
final class PhoneWidgetSyncCoordinator {
  PhoneWidgetSyncCoordinator({required PhoneWidgetPayloadWriter write})
    : _write = write;

  final PhoneWidgetPayloadWriter _write;

  int _epoch = 0;
  DashboardSnapshot? _latestSnapshot;
  PhoneWidgetPreferences? _latestPreferences;
  PhoneWidgetSyncGuard _latestIsCurrent = _alwaysCurrent;
  Future<void> _chain = Future<void>.value();

  /// Queues a write. Overlapping callers coalesce to the newest args.
  ///
  /// Completes with `true` only once the request's own rows committed; a
  /// request the guard retired, the native authority refused or a newer
  /// request superseded completes with `false`. A failure reaches the caller
  /// but must not poison the queue, so the chain continues from a settled
  /// future while the returned one still throws.
  Future<bool> sync(
    DashboardSnapshot snapshot,
    PhoneWidgetPreferences preferences, {
    PhoneWidgetSyncGuard isCurrent = _alwaysCurrent,
  }) {
    _latestSnapshot = snapshot;
    _latestPreferences = preferences;
    _latestIsCurrent = isCurrent;
    final epoch = ++_epoch;
    final run = _chain.then((_) => _runIfCurrent(epoch));
    _chain = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<bool> _runIfCurrent(int epoch) async {
    // A superseded request cannot vouch for rows the newer one may not commit.
    if (epoch != _epoch) {
      return false;
    }
    final snapshot = _latestSnapshot;
    final preferences = _latestPreferences;
    final isCurrent = _latestIsCurrent;
    if (snapshot == null || preferences == null) {
      return false;
    }
    // Ownership can expire while the request waits in the queue.
    if (!await isCurrent()) {
      return false;
    }
    if (epoch != _epoch) {
      return false;
    }
    Future<bool> write() => _write(
      buildPhoneWidgetPayload(snapshot, preferences),
      isCurrent: isCurrent,
    );
    // The newest caller's zone runs this epoch; its claim proves the selection.
    final input = PhoneWidgetPublicationInput.current;
    if (input == null) return write();
    final live = DataModeOperation.current?.mode == DataMode.live;
    return input
        ._withSelection(live ? snapshotSelectionProof(snapshot) : null)
        .run(write);
  }
}

/// Publishes complete payloads for the Android widget, then redraws via home_widget.
final class HomeWidgetPhoneWidgetSyncService implements PhoneWidgetSyncService {
  HomeWidgetPhoneWidgetSyncService({PhoneWidgetSyncCoordinator? coordinator})
    : _coordinator = coordinator ?? _sharedCoordinator;

  static final PhoneWidgetSyncCoordinator _sharedCoordinator =
      PhoneWidgetSyncCoordinator(write: writeHomeWidgetPayload);

  final PhoneWidgetSyncCoordinator _coordinator;

  static const _maxRows = phoneWidgetSlotCount;
  static const _publication = _publicationChannel;

  /// Marks retained launcher rows after a failed poll, without inventing data.
  ///
  /// Only the status flag changes; an empty or cleared payload stays empty.
  /// Native eligibility and the flag-only commit share the publication monitor,
  /// and a newer publication than the claim observed keeps its status.
  static Future<void> markExistingRowsStale({
    PhoneWidgetSyncGuard isCurrent = _alwaysCurrent,
  }) async {
    if (!await isCurrent()) {
      return;
    }
    final operation = DataModeOperation.current;
    final observed = PhoneWidgetPublicationInput.current?.observed;
    bool? saved;
    if (!await DataModeOperation.guardCurrent(() async {
      saved = await _publication.invokeMethod<bool>('markStale', {
        ...?operation?.fetchArguments,
        if (observed != null) 'observed': observed,
      });
    }))
      return;
    if (saved == null) {
      return;
    }
    if (saved != true) {
      throw StateError('Could not save widget stale status.');
    }
    if (!await isCurrent()) {
      return;
    }
    await DataModeOperation.guardCurrent(_redraw);
  }

  @override
  Future<bool> sync(
    DashboardSnapshot snapshot,
    PhoneWidgetPreferences preferences, {
    PhoneWidgetSyncGuard isCurrent = _alwaysCurrent,
  }) {
    return _coordinator.sync(snapshot, preferences, isCurrent: isCurrent);
  }

  @override
  Future<PhoneWidgetPublicationInput> beginLoad() =>
      PhoneWidgetPublicationInput.begin();

  @override
  Future<int?> saveSettings(
    Future<void> Function() save, {
    bool watch = true,
  }) => PhoneWidgetPublicationInput.saveSettings(save, watch: watch);

  @override
  Future<void> redraw() => _redraw();

  /// Persists [payload] under a publication ticket and asks the launcher to
  /// redraw.
  ///
  /// Completes with `true` once the rows committed. Completes with `false`,
  /// publishing and redrawing nothing, when [isCurrent] retired the request
  /// first, a retired or draining mode generation refused the effect, in Dart
  /// or native, or the native authority refused its ticket or commit. Storage
  /// failures still throw. A dispatched publication may finish after
  /// ownership expires; no retraction.
  static Future<bool> writeHomeWidgetPayload(
    PhoneWidgetPayload payload, {
    PhoneWidgetSyncGuard isCurrent = _alwaysCurrent,
  }) async {
    final rows = payload.rows.take(_maxRows).toList(growable: false);
    final publication = <String, Object>{
      'stale': payload.stale ? '1' : '0',
      'empty': payload.isEmpty ? '1' : '0',
      'row_count': rows.length,
    };
    for (var i = 0; i < _maxRows; i++) {
      final row = i < rows.length ? rows[i] : null;
      final fields = <String, String>{
        'kind': row?.kind.name ?? '',
        'spent_minor': row?.spent?.minorUnits.toString() ?? '',
        'spent_currency': row?.spent?.currency ?? '',
        'cap_minor': row?.cap?.minorUnits.toString() ?? '',
        'cap_currency': row?.cap?.currency ?? '',
        'extra_used_value': row?.extraUsed?.value ?? '',
        'extra_used_unit': row?.extraUsed?.unit ?? '',
        'extra_cap_value': row?.extraCap?.value ?? '',
        'extra_cap_unit': row?.extraCap?.unit ?? '',
        'percent': row?.percentText ?? '',
        'credits': row?.creditsSuffix ?? '',
        'label': row?.label ?? '',
        'family': row?.familyLabel ?? '',
        'pool': row?.poolLabel ?? '',
        'resets_at': row?.resetsAt?.toUtc().toIso8601String() ?? '',
        // Hex string — ARGB ints with the high bit set arrive as Long on
        // Android and ClassCastException SharedPreferences.getInt.
        'color': row?.accentArgb.toRadixString(16).padLeft(8, '0') ?? '',
      };
      for (final entry in fields.entries) {
        publication['row_${i}_${entry.key}'] = entry.value;
      }
    }
    if (!await isCurrent()) {
      return false;
    }
    final operation = DataModeOperation.current;
    final input = PhoneWidgetPublicationInput.current;
    var published = false;
    // A switch that retired the generation refuses admission; nothing commits.
    if (!await DataModeOperation.guardCurrent(() async {
      int? ticket;
      if (input != null && input.load != null) {
        ticket = await _publication.invokeMethod<int>('issue', {
          'load': input.load,
          'settingsRevision': input.settingsRevision ?? -1,
          if (input.selection case final selection?) 'selection': selection,
          ...?operation?.fetchArguments,
        });
        // A newer load, a settings save or a stale selection owns the widget.
        if (ticket == null) return;
      }
      final bool? saved;
      try {
        saved = await _publication.invokeMethod<bool>('publish', {
          ...publication,
          ...?operation?.fetchArguments,
          if (ticket != null) 'ticket': ticket,
        });
      } on PlatformException catch (error) {
        // A switch began draining before native admitted the commit.
        if (error.code == 'widget_publication_retired') return;
        rethrow;
      }
      // A newer ticket or a retired input owns the widget; no redraw.
      if (saved == null && ticket != null) return;
      if (saved != true) throw StateError('Could not save widget publication.');
      published = true;
    })) {
      return false;
    }
    if (!published) return false;
    if (await isCurrent()) await DataModeOperation.guardCurrent(_redraw);
    return true;
  }

  static Future<void> _redraw() async {
    final updated = await HomeWidget.updateWidget(
      name: phoneWidgetProviderName,
      androidName: phoneWidgetProviderName,
      qualifiedAndroidName: phoneWidgetQualifiedAndroidName,
    );
    if (updated != true) {
      throw StateError('Could not redraw the widget.');
    }
  }
}
