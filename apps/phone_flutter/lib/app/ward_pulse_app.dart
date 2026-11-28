import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../dashboard/apply_alert_settings.dart';
import '../dashboard/dashboard_models.dart';
import '../dashboard/dashboard_repository.dart';
import '../dashboard/dashboard_screen.dart';
import '../dashboard/plan_recoveries.dart';
import '../dashboard/provider_status_color.dart';
import '../dashboard/provider_status_severity.dart';
import '../providers/claude_account_service.dart';
import '../providers/claude_plan_pause.dart';
import '../providers/codex_account_service.dart';
import '../providers/credential_dialog.dart';
import '../providers/connection_rejection_notice.dart';
import '../providers/connection_lifecycle.dart';
import '../providers/provider_connection.dart';
import '../providers/provider_credential_store.dart';
import '../providers/providers_screen.dart';
import '../settings/alert_notification_preferences.dart';
import '../settings/alert_threshold_preferences.dart';
import '../settings/settings_screen.dart';
import '../settings/recovery_notification_preferences.dart';
import '../settings/refresh_interval_preferences.dart';
import '../settings/watch_ring_preferences.dart';
import '../sync/alert_notifications.dart';
import '../sync/automatic_poll.dart';
import '../sync/data_mode.dart';
import '../sync/headless_provider_sync.dart';
import '../sync/manual_refresh_window.dart';
import '../sync/notification_coordinator.dart';
import '../sync/provider_sync_scheduler.dart';
import '../sync/recovery_notifications.dart';
import '../sync/recovery_wake.dart';
import '../sync/recovery_watchlist.dart';
import '../sync/watch_sync_service.dart';
import '../watchface/watchface_screen.dart';
import '../widget/phone_widget_preferences.dart';
import '../widget/phone_widget_navigation.dart';
import '../widget/phone_widget_payload.dart';
import '../widget/phone_widget_sync.dart';
import '../widget/widget_screen.dart';
import 'surface_order.dart';
import 'ward_pulse_theme.dart';

class WardPulseApp extends StatelessWidget {
  const WardPulseApp({
    super.key,
    required this.repository,
    this.watchSyncService = const MethodChannelWatchSyncService(),
    this.phoneWidgetSyncService = const DisabledPhoneWidgetSyncService(),
    this.phoneWidgetNavigationService =
        const MethodChannelPhoneWidgetNavigationService(),
    this.credentialStore = const EmptyProviderCredentialStore(),
    this.codexAccountService = const EmptyCodexAccountService(),
    this.claudeAccountService = const EmptyClaudeAccountService(),
    this.claudePlanPaused = claudePlanPausedInBuild,
    this.refreshIntervalStore = const DefaultRefreshIntervalPreferenceStore(),
    this.watchRingPreferenceStore = const DefaultWatchRingPreferenceStore(),
    this.phoneWidgetPreferenceStore = const DefaultPhoneWidgetPreferenceStore(),
    this.alertThresholdStore = const DefaultAlertThresholdPreferenceStore(),
    this.applyAlertSettings = applyUserAlertSettings,
    this.syncScheduler = const DisabledProviderSyncScheduler(),
    this.scheduleHeadlessSync = HeadlessProviderSync.schedule,
    this.debugDataAvailable = false,
    this.modeAuthority,
    this.mockRepository,
    this.demoRepository,
    this.prepareLive,
    this.clock,
    this.recoveryWatchlistStore = const DisabledRecoveryWatchlistStore(),
    this.recoveryNotifier = const SilentRecoveryNotifier(),
    this.recoveryWake = const DisabledRecoveryWakeScheduler(),
    this.readPlanRecoveries = planRecoveries,
    this.readExhaustedWindows = exhaustedWindows,
    this.recoveryNotificationStore =
        const DefaultRecoveryNotificationPreferenceStore(),
    this.alertNotificationStore =
        const DefaultAlertNotificationPreferenceStore(),
    this.alertConditionStore = const DisabledAlertConditionStore(),
    this.alertNotifier = const SilentAlertNotifier(),
    this.notificationCoordinator,
    this.rejectionNotices = const EmptyConnectionRejectionNoticeStore(),
  });

  final DashboardRepository repository;
  final WatchSyncService watchSyncService;
  final PhoneWidgetSyncService phoneWidgetSyncService;
  final PhoneWidgetNavigationService phoneWidgetNavigationService;
  final ProviderCredentialStore credentialStore;
  final CodexAccountService codexAccountService;
  final ClaudeAccountService claudeAccountService;
  final bool claudePlanPaused;
  final RefreshIntervalPreferenceStore refreshIntervalStore;
  final WatchRingPreferenceStore watchRingPreferenceStore;
  final PhoneWidgetPreferenceStore phoneWidgetPreferenceStore;
  final AlertThresholdPreferenceStore alertThresholdStore;
  final ApplyAlertSettings applyAlertSettings;
  final ProviderSyncScheduler syncScheduler;
  final Future<void> Function(Duration) scheduleHeadlessSync;
  final bool debugDataAvailable;
  final DataModeAuthority? modeAuthority;
  final DashboardRepository? mockRepository;

  /// The public Demo sample; without one, Demo shows the empty state.
  final DashboardRepository? demoRepository;
  final Future<void> Function()? prepareLive;

  /// The clock Wear refresh cooldown reads; the device clock by default.
  final DateTime Function()? clock;
  final RecoveryWatchlistStore recoveryWatchlistStore;
  final RecoveryNotifier recoveryNotifier;
  final RecoveryWakeScheduler recoveryWake;
  final ReadPlanRecoveries readPlanRecoveries;
  final ReadExhaustedWindows readExhaustedWindows;
  final RecoveryNotificationPreferenceStore recoveryNotificationStore;
  final AlertNotificationPreferenceStore alertNotificationStore;
  final AlertConditionStore alertConditionStore;
  final AlertNotifier alertNotifier;
  final PhoneNotificationCoordinator? notificationCoordinator;
  final ConnectionRejectionNoticeStore rejectionNotices;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WardPulse',
      debugShowCheckedModeBanner: false,
      theme: wardPulseLightTheme,
      darkTheme: wardPulseDarkTheme,
      home: DashboardHost(
        repository: repository,
        watchSyncService: watchSyncService,
        phoneWidgetSyncService: phoneWidgetSyncService,
        phoneWidgetNavigationService: phoneWidgetNavigationService,
        credentialStore: credentialStore,
        codexAccountService: codexAccountService,
        claudeAccountService: claudeAccountService,
        claudePlanPaused: claudePlanPaused,
        refreshIntervalStore: refreshIntervalStore,
        watchRingPreferenceStore: watchRingPreferenceStore,
        phoneWidgetPreferenceStore: phoneWidgetPreferenceStore,
        alertThresholdStore: alertThresholdStore,
        applyAlertSettings: applyAlertSettings,
        syncScheduler: syncScheduler,
        scheduleHeadlessSync: scheduleHeadlessSync,
        debugDataAvailable: debugDataAvailable,
        modeAuthority: modeAuthority,
        mockRepository: mockRepository,
        demoRepository: demoRepository,
        prepareLive: prepareLive,
        clock: clock,
        recoveryWatchlistStore: recoveryWatchlistStore,
        recoveryNotifier: recoveryNotifier,
        recoveryWake: recoveryWake,
        readPlanRecoveries: readPlanRecoveries,
        readExhaustedWindows: readExhaustedWindows,
        recoveryNotificationStore: recoveryNotificationStore,
        alertNotificationStore: alertNotificationStore,
        alertConditionStore: alertConditionStore,
        alertNotifier: alertNotifier,
        notificationCoordinator: notificationCoordinator,
        rejectionNotices: rejectionNotices,
      ),
    );
  }
}

class DashboardHost extends StatefulWidget {
  const DashboardHost({
    super.key,
    required this.repository,
    required this.watchSyncService,
    required this.phoneWidgetSyncService,
    required this.phoneWidgetNavigationService,
    required this.credentialStore,
    required this.codexAccountService,
    required this.claudeAccountService,
    this.claudePlanPaused = claudePlanPausedInBuild,
    required this.refreshIntervalStore,
    required this.watchRingPreferenceStore,
    required this.phoneWidgetPreferenceStore,
    required this.alertThresholdStore,
    required this.applyAlertSettings,
    required this.syncScheduler,
    required this.scheduleHeadlessSync,
    required this.debugDataAvailable,
    this.modeAuthority,
    this.mockRepository,
    this.demoRepository,
    this.prepareLive,
    this.clock,
    required this.recoveryWatchlistStore,
    required this.recoveryNotifier,
    required this.recoveryWake,
    required this.readPlanRecoveries,
    required this.readExhaustedWindows,
    required this.recoveryNotificationStore,
    required this.alertNotificationStore,
    required this.alertConditionStore,
    required this.alertNotifier,
    this.notificationCoordinator,
    this.rejectionNotices = const EmptyConnectionRejectionNoticeStore(),
  });

  final DashboardRepository repository;
  final WatchSyncService watchSyncService;
  final PhoneWidgetSyncService phoneWidgetSyncService;
  final PhoneWidgetNavigationService phoneWidgetNavigationService;
  final ProviderCredentialStore credentialStore;
  final CodexAccountService codexAccountService;
  final ClaudeAccountService claudeAccountService;
  final bool claudePlanPaused;
  final RefreshIntervalPreferenceStore refreshIntervalStore;
  final WatchRingPreferenceStore watchRingPreferenceStore;
  final PhoneWidgetPreferenceStore phoneWidgetPreferenceStore;
  final AlertThresholdPreferenceStore alertThresholdStore;
  final ApplyAlertSettings applyAlertSettings;
  final ProviderSyncScheduler syncScheduler;
  final Future<void> Function(Duration) scheduleHeadlessSync;
  final bool debugDataAvailable;
  final DataModeAuthority? modeAuthority;
  final DashboardRepository? mockRepository;

  /// The public Demo sample; without one, Demo shows the empty state.
  final DashboardRepository? demoRepository;
  final Future<void> Function()? prepareLive;

  /// The clock Wear refresh cooldown reads; the device clock by default.
  final DateTime Function()? clock;
  final RecoveryNotificationPreferenceStore recoveryNotificationStore;
  final RecoveryWakeScheduler recoveryWake;
  final RecoveryNotifier recoveryNotifier;
  final RecoveryWatchlistStore recoveryWatchlistStore;
  final ReadPlanRecoveries readPlanRecoveries;
  final ReadExhaustedWindows readExhaustedWindows;

  final AlertNotificationPreferenceStore alertNotificationStore;
  final AlertConditionStore alertConditionStore;
  final AlertNotifier alertNotifier;
  final PhoneNotificationCoordinator? notificationCoordinator;
  final ConnectionRejectionNoticeStore rejectionNotices;

  @override
  State<DashboardHost> createState() => _DashboardHostState();
}

/// One accepted load or reevaluation, even when it reuses the snapshot object.
final class _SnapshotAcceptance {
  _SnapshotAcceptance({
    required this.operation,
    required this.observationRevision,
    required this.input,
    required this.snapshot,
    required this.rules,
    required this.ruleGeneration,
    required this.surfaceRevision,
    required this.poll,
    required this.publication,
  });

  // Rule edits replace the acceptance while retaining the provider observation.
  final DataModeOperation operation;
  final int observationRevision;
  final DashboardSnapshot input;
  final DashboardSnapshot snapshot;
  final AlertThresholdPreferences? rules;
  final int ruleGeneration;
  final int surfaceRevision;
  final AutomaticPollContext? poll;

  /// The observation's launcher claim; edits republish under fresh tickets.
  final PhoneWidgetPublicationInput publication;
}

/// How one watch reply attempt ended.
enum _WatchReply {
  /// A summary was handed to the native sender.
  queued,

  /// Nothing current could be sent, which cannot authorize provider work.
  unavailable,

  /// A newer load, acceptance or mode should answer instead.
  superseded,
}

final class _RetiredDashboardLoad implements Exception {
  const _RetiredDashboardLoad({this.accepted = false});

  /// Whether native accepted the load before its source retired, which
  /// refuses the publications of the work that retired it.
  final bool accepted;
}

class _DashboardHostState extends State<DashboardHost>
    with WidgetsBindingObserver {
  static const _dashboardIndex = 0;
  static const _watchfaceIndex = 1;
  static const _widgetIndex = 2;
  static const _providersIndex = 3;
  static const _settingsIndex = 4;

  var _loadRevision = 0;
  var _surfaceRevision = 0;
  late Future<DashboardSnapshot> _snapshot;

  /// Settles with the newest explicit, startup or scheduled load.
  Future<void>? _activeLoad;

  /// Completes when a load starts or settles or the acceptance changes, so a
  /// waiting Wear reply follows the newest owner.
  var _replyOwnership = Completer<void>();
  late final DataModeAuthority _modeAuthority =
      widget.modeAuthority ?? MemoryDataModeAuthority();
  _SnapshotAcceptance? _acceptanceValue;
  _SnapshotAcceptance? get _acceptance => _acceptanceValue;
  set _acceptance(_SnapshotAcceptance? value) {
    if (identical(value, _acceptanceValue)) return;
    _acceptanceValue = value;
    _replyOwnershipChanged();
  }

  void _replyOwnershipChanged() {
    final changed = _replyOwnership;
    _replyOwnership = Completer<void>();
    changed.complete();
  }

  final _reportingUpdates = <ProviderConnectionId, ConnectionReportingUpdate>{};
  ProviderConnectionId? _editReportingConnection;
  ({ProviderConnectionId connection, int token})? _connectionReveal;
  var _connectionRevealToken = 0;
  var _noticeRevision = 0;
  List<ConnectionRejectionNotice> _rejectionNotices = const [];

  Future<void> _readRejectionNotices() async {
    if (!_modeReady || _mode.synthetic) return;
    final revision = ++_noticeRevision;
    try {
      final notices = await widget.rejectionNotices.read();
      if (mounted && !_mode.synthetic && revision == _noticeRevision) {
        setState(() => _rejectionNotices = notices);
      }
    } catch (_) {
      // A failed read retains the last confirmed notice view.
    }
  }

  Future<void> _dismissRejection(ConnectionRejectionNotice notice) async {
    ++_noticeRevision;
    try {
      await widget.rejectionNotices.dismiss(notice);
    } catch (_) {
      return;
    }
    await _readRejectionNotices();
  }

  void _revealConnection(ProviderConnectionId connection) {
    setState(() {
      _editReportingConnection = null;
      _connectionReveal = (
        connection: connection,
        token: ++_connectionRevealToken,
      );
      _selectedIndex = _providersIndex;
    });
  }

  final _reportingSaves = <ProviderConnectionId>{};

  /// Holds the Dashboard's card order for the run, so a poll that only moves
  /// spend leaves every card where the reader last saw it. Shared with the
  /// app-bar badge, which must point at the topmost flagged card.
  final _dashboardOrder = FrozenOrder();
  RefreshIntervalPreference _refreshInterval =
      const RefreshIntervalPreference();
  WatchRingPreferences? _ringPreferences;
  PhoneWidgetPreferences? _widgetPreferences;
  // Held exports survive a skipped poll that replaces their acceptance.
  var _watchPublicationPending = false;
  var _widgetPublicationPending = false;

  /// Watch-affecting saves begun; a send whose input predates one cannot
  /// cover the watch item that save retired.
  var _watchSettingsSaves = 0;
  var _widgetPublicationRevision = 0;
  var _widgetRepublishing = false;

  /// A saved widget selection no launcher publication represents yet.
  var _widgetEditUnpublished = false;

  /// The settled settings revision this engine's confirmed widget and rule
  /// choices correspond to; launcher tickets require it to stay current.
  int? _surfaceSettingsRevision;
  WatchRingPreferences? _pendingRingPreferences;
  PhoneWidgetPreferences? _pendingWidgetPreferences;
  Future<void> _ringPreferenceWork = Future<void>.value();
  Future<void> _widgetPreferenceWork = Future<void>.value();
  var _ringPreferenceRevision = 0;
  var _widgetPreferenceRevision = 0;
  AlertThresholdPreferences? _alertThresholds;
  var _ruleGeneration = 0;
  Future<void> _snapshotSettingsWork = Future<void>.value();
  DataMode _mode = DataMode.live;
  bool _modeReady = false;
  bool _livePrepared = false;
  bool get _mockDataEnabled => _mode == DataMode.mock;
  bool _modeChangeInFlight = false;
  bool _accountStorageUnresolved = false;

  DashboardRepository _source(DataModeOperation operation) =>
      operation.mode == DataMode.live
          ? widget.repository
          : _sampleSource(operation.mode) ??
              const NoProvidersDashboardRepository();

  /// The sample source a synthetic [mode] reads, if this host has one.
  DashboardRepository? _sampleSource(DataMode mode) => switch (mode) {
    DataMode.live => null,
    DataMode.demo => widget.demoRepository,
    DataMode.mock => widget.mockRepository,
  };

  /// Demo shows its sample as generated: live rules, which stay editable for
  /// the return to Live, neither shape nor gate it.
  static const _sampleRules = AlertThresholdPreferences();

  /// The rules [mode]'s acceptances are evaluated with; `null` while the
  /// live rules are unread.
  AlertThresholdPreferences? _rulesFor(DataMode mode) =>
      mode == DataMode.demo ? _sampleRules : _alertThresholds;

  /// Applies [rules] to [input]; Demo only clears alerts and conditions.
  DashboardSnapshot _evaluate(
    DataMode mode,
    DashboardSnapshot input,
    AlertThresholdPreferences rules,
  ) =>
      mode == DataMode.demo
          ? applyUserAlertSettings(input, _sampleRules)
          : widget.applyAlertSettings(input, rules);

  /// Demo follows the Play build's capabilities in every build, so its
  /// pickers, previews and publications match the reviewed release.
  bool _claudePlanPausedIn(DataMode mode) =>
      widget.claudePlanPaused || mode == DataMode.demo;

  bool _recoveryNotificationsEnabled = true;
  bool _alertNotificationsEnabled = true;
  var _alertNotificationRevision = 0;
  var _recoveryNotificationRevision = 0;
  var _notificationEligibilityRevision = 0;
  var _notificationReads = 0;
  var _notificationWrites = 0;
  var _notificationFrameRevision = 0;
  bool _notificationPreferencesResolved = false;
  bool _notificationFrameReady = false;
  bool? _androidNotificationsEnabled;
  var _notificationStatusRevision = 0;
  int _selectedIndex = 0;
  bool _widgetNavigationPending = false;
  ({String provider, int token})? _reveal;
  StreamSubscription<void>? _syncTicks;
  var _autoSyncInFlight = false;
  bool get _reportingCheckActive =>
      _reportingSaves.isNotEmpty ||
      _reportingUpdates.values.any((update) => update.checking);

  /// Latest Wear-accepted refresh tap; keeps the PollCadence floor honest while a
  /// reload is still in flight (before [DashboardSnapshot.generatedAt] advances).
  DateTime? _wearRefreshAnchorAt;

  /// Native automatic dispatch evidence by connection, with the credential
  /// version that claimed it, as a load or cold probe last observed it, even
  /// if that load failed or was rejected. It outlives the acceptance, so an
  /// older retained report cannot reopen the floor. A native correction such
  /// as a clock rollback replaces the superseded anchor, and a removed or
  /// replaced credential retires it. [order] is Android's observation order
  /// for the sample, so a load that started earlier but claimed later still
  /// replaces an older sample or correction, and late evidence cannot.
  final _automaticDispatches =
      <String, ({DateTime at, CredentialVersion version, int order})>{};

  DateTime? get _automaticDispatchAt {
    DateTime? latest;
    for (final (:at, version: _, order: _) in _automaticDispatches.values) {
      if (latest == null || at.isAfter(latest)) latest = at;
    }
    return latest;
  }

  /// Whether the scheduler confirmed this session's periodic background work.
  /// A resend-only launch, or a failed registration, defers it to the next
  /// ordinary Live trigger.
  var _headlessRegistered = false;
  var _headlessRegistering = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeNotifications();
    _queueNotificationFrame();
    _syncTicks = widget.syncScheduler.ticks.listen((_) {
      unawaited(_onScheduledSync());
    });
    final pending = widget.watchSyncService.bindWatchRefreshListener(
      (request) => unawaited(_onWatchRefreshRequested(request)),
    );
    _snapshot = _loadSnapshot(automatic: true, startupRequest: pending);
    widget.phoneWidgetNavigationService.bind(_openDashboardFromWidget);
  }

  void _initializeNotifications() {
    final coordinator = widget.notificationCoordinator;
    if (coordinator != null) {
      unawaited(coordinator.ensureReady().catchError((Object _) {}));
    }
  }

  bool get _notificationForegroundReady =>
      mounted &&
      _notificationFrameReady &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  void _queueNotificationFrame() {
    _notificationFrameReady = false;
    final revision = ++_notificationFrameRevision;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          revision != _notificationFrameRevision ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      _notificationFrameReady = true;
      _considerNotificationPermission();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _queueNotificationFrame();
    if (state == AppLifecycleState.resumed) {
      unawaited(_readRejectionNotices());
      unawaited(_resumeWatchPublication());
    }
    if (state == AppLifecycleState.resumed &&
        _selectedIndex == _settingsIndex) {
      unawaited(_refreshNotificationStatus());
    }
  }

  @override
  void didUpdateWidget(covariant DashboardHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
      oldWidget.notificationCoordinator,
      widget.notificationCoordinator,
    )) {
      _notificationStatusRevision++;
      _androidNotificationsEnabled = null;
      if (_selectedIndex == _settingsIndex) {
        unawaited(_refreshNotificationStatus());
      }
    }
    if (!identical(
          oldWidget.notificationCoordinator,
          widget.notificationCoordinator,
        ) ||
        !identical(
          oldWidget.alertNotificationStore,
          widget.alertNotificationStore,
        ) ||
        !identical(
          oldWidget.recoveryNotificationStore,
          widget.recoveryNotificationStore,
        )) {
      _alertNotificationRevision++;
      _recoveryNotificationRevision++;
      _invalidateNotificationEligibility();
      _initializeNotifications();
      unawaited(_readNotificationPreferences(_loadRevision));
    }
  }

  void _invalidateNotificationEligibility() {
    _notificationEligibilityRevision++;
    _notificationPreferencesResolved = false;
  }

  void _considerNotificationPermission() {
    final coordinator = widget.notificationCoordinator;
    if (coordinator == null) return;
    final revision = _notificationEligibilityRevision;
    bool eligible() =>
        _notificationForegroundReady &&
        _modeReady &&
        !_mode.synthetic &&
        identical(coordinator, widget.notificationCoordinator) &&
        revision == _notificationEligibilityRevision &&
        _notificationPreferencesResolved &&
        _notificationReads == 0 &&
        _notificationWrites == 0 &&
        (_alertNotificationsEnabled || _recoveryNotificationsEnabled);
    if (eligible()) {
      unawaited(
        _requestNotificationPermission(
          coordinator,
          isEligible: eligible,
          automatic: true,
        ),
      );
    }
  }

  Future<bool?> _requestNotificationPermission(
    PhoneNotificationCoordinator coordinator, {
    required bool Function() isEligible,
    bool automatic = false,
  }) async {
    final result = await coordinator.requestForeground(
      isEligible: isEligible,
      automatic: automatic,
    );
    if (result != null &&
        mounted &&
        identical(coordinator, widget.notificationCoordinator)) {
      unawaited(_refreshNotificationStatus());
    }
    return result;
  }

  Future<void> _refreshNotificationStatus() async {
    if (!mounted) return;
    final coordinator = widget.notificationCoordinator;
    final revision = ++_notificationStatusRevision;
    setState(() => _androidNotificationsEnabled = null);
    bool? enabled;
    try {
      enabled = await coordinator?.readAndroidNotificationStatus();
    } catch (_) {
      // Unsupported and failed reads leave the status unknown.
    }
    if (!mounted ||
        revision != _notificationStatusRevision ||
        !identical(coordinator, widget.notificationCoordinator)) {
      return;
    }
    setState(() => _androidNotificationsEnabled = enabled);
  }

  void _openDashboardFromWidget() {
    if (!mounted || _widgetNavigationPending) return;
    _widgetNavigationPending = true;
    // Ready delivery can arrive during the first build or a Navigator transition.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _widgetNavigationPending = false;
      if (!mounted) return;
      // Cancel the route before disposing the tab that owns its unsaved form.
      Navigator.of(context).popUntil((route) => route.isFirst);
      setState(() {
        _selectedIndex = _dashboardIndex;
      });
    });
    // An idle native message has no build of its own to drive that callback.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// The anchor Wear advertises for [snapshot]; without one, refresh is open.
  DateTime _manualRefreshAnchorAt(DashboardSnapshot snapshot) =>
      _refreshFloorAt(snapshot);

  /// Report times seen after the current clock. Each predates a verified
  /// rollback, so the same retained report proves no attempt even once the
  /// clock passes its time again.
  final _rolledBackReportTimes = <DateTime>{};

  /// Latest of the retained report's time, the last accepted Wear refresh tap
  /// and observed native automatic dispatch.
  ///
  /// Native dispatch anchors, which native corrects, and tap anchors keep the
  /// floor for the attempts behind a rolled-back report.
  DateTime _refreshFloorAt(DashboardSnapshot? report) {
    final now = _now();
    final reportAt = report?.generatedAt.toUtc();
    if (reportAt != null && reportAt.isAfter(now)) {
      _rolledBackReportTimes.add(reportAt);
    }
    return ManualRefreshWindow.anchorAt(
      reportAt: _rolledBackReportTimes.contains(reportAt) ? null : reportAt,
      attempts: [_wearTapAnchorAt(), _automaticDispatchAt],
      now: now,
    );
  }

  bool _refreshAllowed(DashboardSnapshot? report) =>
      ManualRefreshWindow.fromLastSync(
        lastSyncAt: _refreshFloorAt(report),
        now: _now(),
      ).allowed;

  DateTime _now() => (widget.clock ?? DateTime.now)().toUtc();

  /// The last accepted Wear tap. Like the native dispatch anchor, a tap
  /// recorded after the current time proves a clock rollback and is corrected
  /// to now, which keeps the floor for that attempt.
  DateTime? _wearTapAnchorAt() {
    final at = _wearRefreshAnchorAt;
    final now = _now();
    if (at == null || !at.isAfter(now)) return at;
    return _wearRefreshAnchorAt = now;
  }

  void _noteAutomaticDispatch(
    AutomaticPollContext? poll, [
    Set<String>? owned,
  ]) {
    if (poll == null) return;
    for (final MapEntry(key: connection, value: at)
        in poll.automaticAt.entries) {
      if (owned != null && !owned.contains(connection)) continue;
      final order = poll.samples[connection] ?? 0;
      final version =
          poll.admittedVersions[connection] ??
          poll.skipped[connection]?.version;
      final previous = _automaticDispatches[connection];
      if (version == null || (previous != null && previous.order > order)) {
        continue;
      }
      _automaticDispatches[connection] = (
        at: at,
        version: version,
        order: order,
      );
    }
  }

  /// Keeps the native claims a load recorded, whether its aggregate is then
  /// accepted, fails or is rejected, while the mode and each claiming
  /// credential still own them. Unavailable proof keeps the floor.
  Future<void> _noteOwnedAutomaticDispatch(
    DataModeOperation operation,
    AutomaticPollContext? poll,
  ) async {
    if (poll == null || operation.mode.synthetic) return;
    final owned = <String>{};
    for (final connection in poll.automaticAt.keys.toList()) {
      final version =
          poll.admittedVersions[connection] ??
          poll.skipped[connection]?.version;
      if (version == null) continue;
      try {
        if (!await _source(
          operation,
        ).ownsAutomaticCadence(connection, version)) {
          continue;
        }
      } catch (_) {
        // Unavailable proof keeps the floor.
      }
      owned.add(connection);
    }
    try {
      if (!mounted || !await operation.isCurrent()) return;
    } catch (_) {
      return;
    }
    if (mounted) _noteAutomaticDispatch(poll, owned);
  }

  /// Retires dispatch evidence whose connection or credential no longer owns
  /// its native cadence, so a removed or replaced source cannot hold the
  /// others in cooldown. A snapshot epoch change keeps it, like the native
  /// anchor. Unavailable proof keeps the floor.
  Future<void> _retireAutomaticDispatches(DataModeOperation operation) async {
    if (operation.mode.synthetic) return;
    for (final MapEntry(key: connection, value: dispatch)
        in _automaticDispatches.entries.toList()) {
      try {
        if (await _source(
              operation,
            ).ownsAutomaticCadence(connection, dispatch.version) ||
            !await operation.isCurrent()) {
          continue;
        }
      } catch (_) {
        continue;
      }
      if (_automaticDispatches[connection] == dispatch) {
        _automaticDispatches.remove(connection);
      }
    }
  }

  Future<void> _onWatchRefreshRequested(WatchRefreshIntent request) async {
    // A tap queued during a mode write must be interpreted against its outcome.
    await _snapshotSettingsWork;
    if (!mounted) return;
    final DataModeOperation operation;
    final bool resend;
    try {
      operation = await request.operation(_modeAuthority);
      resend = operation.cacheOnly || !await operation.isCurrent();
    } catch (_) {
      return;
    }
    // Neither the advertised floor nor this admission may follow a source
    // that no longer owns its dispatch.
    await _retireAutomaticDispatches(operation);
    if (!mounted) return;
    if (resend) {
      await _resendWatchSummary();
      return;
    }
    // A report retired outside this isolate cannot hold the floor. Without
    // it, the load probes current retained evidence instead.
    if (_acceptance case final previous?) {
      var owned = true;
      try {
        owned = await _isSourceCurrent(previous.operation, previous.snapshot);
      } catch (_) {
        // Unavailable proof keeps the floor.
      }
      if (!mounted) return;
      if (!owned && identical(previous, _acceptance)) _acceptance = null;
    }
    final acceptance = _acceptance;
    if (acceptance != null) {
      if (!_refreshAllowed(acceptance.snapshot)) {
        if (await _queueWatchSummaryIfAvailable(acceptance) ==
            _WatchReply.superseded) {
          await _resendWatchSummary();
        }
        return;
      }
      _wearRefreshAnchorAt = _now();
      unawaited(_syncWatch(acceptance));
    }
    _reload(operation: operation);
  }

  /// Whether the resend handed a current summary to the native sender.
  ///
  /// With [launcher], a save also owes the launcher frame, which publishes
  /// from the same acceptance, so neither surface retires the other's ticket.
  /// Without an acceptance to share, the launcher republishes on its own.
  Future<bool> _resendWatchSummary({bool launcher = false}) async {
    final launcherRevision = _widgetPublicationRevision;
    try {
      return await _answerWatch(launcher: launcher);
    } finally {
      if (launcher &&
          mounted &&
          _widgetPublicationPending &&
          launcherRevision == _widgetPublicationRevision) {
        unawaited(_republishPhoneWidget());
      }
    }
  }

  /// [_resendWatchSummary] without its launcher fallback.
  Future<bool> _answerWatch({required bool launcher}) async {
    // This may be a different settings transaction from the one present at
    // handoff. Let its replacement load supply a summary if it already can.
    await _snapshotSettingsWork;
    while (mounted) {
      // Replacing a newer explicit or scheduled load would retire its work.
      // A newer load replacing the awaited one answers as soon as it settles.
      if (_activeLoad != null) {
        await _replyOwnership.future;
        continue;
      }
      final acceptance = _acceptance;
      if (acceptance != null) {
        final reply = await _queueWatchSummaryIfAvailable(acceptance);
        if (reply != _WatchReply.superseded) {
          if (launcher) unawaited(_syncPhoneWidget(acceptance));
          return reply == _WatchReply.queued;
        }
      }
      if (!mounted) return false;
      if (_activeLoad != null || !identical(acceptance, _acceptance)) continue;
      // No eligible load or acceptance answers. Dashboard keeps its own state.
      final reply = await _replyFromRetained(acceptance, launcher: launcher);
      if (reply != _WatchReply.superseded) return reply == _WatchReply.queued;
    }
    return false;
  }

  /// Cache reads a Wear reply may make when work outside this isolate, such as
  /// headless sync, retires a retained report's proof.
  static const _retainedReplyAttempts = 3;

  /// Sends Wear the current retained or empty summary without a Dashboard load.
  /// With [launcher], its acceptance publishes the launcher frame a save owes
  /// too, where that input supplies launcher rows.
  ///
  /// Returns [_WatchReply.superseded] when a newer load, acceptance or mode
  /// should answer.
  Future<_WatchReply> _replyFromRetained(
    _SnapshotAcceptance? acceptance, {
    bool launcher = false,
  }) async {
    final preferences = _ringPreferences;
    final launcherPreferences = _widgetPreferences;
    if (preferences == null) return _WatchReply.unavailable;
    final DataModeOperation operation;
    try {
      operation = await _modeAuthority.begin(
        cacheOnly: true,
        waitForSwitch: true,
      );
    } catch (_) {
      // Unavailable mode storage cannot authorize a publication.
      return _WatchReply.unavailable;
    }
    final rules = _rulesFor(operation.mode);
    if (rules == null) return _WatchReply.unavailable;
    bool superseded() =>
        !mounted ||
        _activeLoad != null ||
        !identical(acceptance, _acceptance) ||
        !identical(preferences, _ringPreferences) ||
        !identical(rules, _rulesFor(operation.mode));
    // [proof] runs again at the native send boundary, once Google Play
    // services is ready; a retired proof reads again, as does a summary whose
    // accepted [publication] or settings revision native already replaced.
    Future<bool> send(
      PhoneWidgetPublicationInput publication,
      int? settingsRevision,
      int saves,
      DashboardSnapshot snapshot,
      Future<bool> Function() proof, {
      bool absence = false,
    }) async {
      final owed =
          launcher &&
          launcherPreferences != null &&
          _suppliesLauncherRows(
            operation,
            absence ? null : snapshot,
            launcherPreferences,
          );
      // Choices beyond capacity send Wear nothing; unless a launcher frame is
      // owed, accepting this read would only retire one.
      if (!owed) {
        await _requireWatchRingCapacity(snapshot, preferences, operation.mode);
      }
      if (!await operation.run(() => publication.accept(snapshot))) {
        return false;
      }
      unawaited(
        _replaceRetiredLauncherFrame(
          operation,
          publication,
          settingsRevision,
          rules,
          snapshot,
          proof,
          owed: owed,
        ),
      );
      if (owed) {
        await _requireWatchRingCapacity(snapshot, preferences, operation.mode);
      }
      bool? owned;
      try {
        await operation.run(
          () => publication
              .withSettingsRevision(settingsRevision)
              .run(
                () => widget.watchSyncService.sync(
                  snapshot,
                  preferences,
                  manualRefreshAnchorAt: _manualRefreshAnchorAt(snapshot),
                  mockDataMode: operation.mode == DataMode.mock,
                  isCurrent:
                      () async =>
                          owned =
                              !superseded() && await proof() && !superseded(),
                ),
              ),
        );
      } on WatchSummarySuperseded {
        return false;
      }
      if (owned == false) return false;
      // The publication the accepted load still owed is covered too, unless
      // a save began after this input was read.
      if (!superseded() && saves == _watchSettingsSaves) {
        _watchPublicationPending = false;
      }
      return true;
    }

    try {
      // No Dashboard event follows a proof retired outside this isolate, so
      // the cache is read again rather than awaiting one.
      for (var attempt = 0; attempt < _retainedReplyAttempts; attempt++) {
        // A cache read through the shared repository would retire a newer load.
        if (superseded()) return _WatchReply.superseded;
        if (!await operation.isCurrent()) return _WatchReply.superseded;
        // A load may start while the mode proof is pending.
        if (superseded()) return _WatchReply.superseded;
        // Ordered before the cache read; a newer load's acceptance wins. A
        // save that settled since an earlier attempt, such as a launcher-only
        // one, tags these unchanged choices with its revision.
        final settingsRevision = _surfaceSettingsRevision;
        final saves = _watchSettingsSaves;
        final publication = await widget.phoneWidgetSyncService.beginLoad();
        if (superseded()) return _WatchReply.superseded;
        final DashboardSnapshot loaded;
        try {
          loaded = await operation.run(_source(operation).load);
        } on DashboardLoadException catch (failure) {
          if (superseded()) return _WatchReply.superseded;
          if (!await _source(operation).isFailureCurrent(failure)) continue;
          if (superseded()) return _WatchReply.superseded;
          // Confirmed absence clears Wear instead of leaving an obsolete
          // summary. Its failure's selection is the native send proof.
          final cleared = await send(
            publication,
            settingsRevision,
            saves,
            failure.selection,
            () async =>
                await operation.isCurrent() &&
                await _source(operation).isFailureCurrent(failure),
            absence: true,
          );
          if (cleared) return _WatchReply.queued;
          if (superseded()) return _WatchReply.superseded;
          continue;
        }
        final snapshot = _evaluate(operation.mode, loaded, rules);
        if (superseded()) return _WatchReply.superseded;
        if (!await _isSourceCurrent(operation, snapshot)) continue;
        if (superseded()) return _WatchReply.superseded;
        final sent = await send(
          publication,
          settingsRevision,
          saves,
          snapshot,
          () => _isSourceCurrent(operation, snapshot),
        );
        if (sent) return _WatchReply.queued;
        if (superseded()) return _WatchReply.superseded;
      }
    } on DataModeRetired {
      return _WatchReply.superseded;
    } catch (_) {
      // An unavailable cache or watch cannot authorize provider work.
    }
    return _WatchReply.unavailable;
  }

  /// A Wear resend's acceptance, warm or cold, retires the first delivery of
  /// launcher rows a widget has not received yet, so the launcher publishes
  /// the same accepted input; publishing under a newer load would retire the
  /// resend in turn. Native is asked after that acceptance, since rows may
  /// commit after the load began. A launcher with no such frame then was not
  /// retired by it and is left to its own loads, unless [owed], for a save
  /// whose pending frame this acceptance publishes. The frame carries
  /// the [settingsRevision] its input was read under and is refused once
  /// [rules] are replaced, so a newer save's own reply publishes; unread
  /// [rules] build none. A refused publication stays pending for the next
  /// load.
  Future<void> _replaceRetiredLauncherFrame(
    DataModeOperation operation,
    PhoneWidgetPublicationInput publication,
    int? settingsRevision,
    AlertThresholdPreferences? rules,
    DashboardSnapshot snapshot,
    Future<bool> Function() proof, {
    bool owed = false,
  }) async {
    final preferences = _widgetPreferences;
    try {
      if (preferences == null) return;
      if (!owed || !_widgetPublicationPending) {
        if (!await publication.isAwaitingDelivery()) return;
        if (await publication.isEstablished()) return;
      }
      if (!mounted ||
          !identical(preferences, _widgetPreferences) ||
          rules == null ||
          !identical(rules, _rulesFor(operation.mode))) {
        return;
      }
      _widgetPublicationPending = true;
      final publicationRevision = ++_widgetPublicationRevision;
      await _dispatchPhoneWidget(
        operation,
        snapshot,
        publication,
        preferences,
        settingsRevision,
        accepted:
            () =>
                mounted &&
                publicationRevision == _widgetPublicationRevision &&
                identical(preferences, _widgetPreferences) &&
                identical(rules, _rulesFor(operation.mode)),
        proof: proof,
      );
    } catch (_) {
      developer.log(
        'Wear resend could not update the widget.',
        name: phoneWidgetLogName,
      );
    }
  }

  Future<_WatchReply> _queueWatchSummaryIfAvailable(
    _SnapshotAcceptance acceptance,
  ) async {
    try {
      if (_ringPreferences == null) {
        // Unread ring choices build no summary from any input. While this
        // acceptance can still publish the launcher, nothing newer answers;
        // otherwise the retained reply and its launcher fallback do.
        final publishes =
            _hasCurrentRules(acceptance) &&
            await _isSourceCurrent(acceptance.operation, acceptance.snapshot);
        return publishes ? _WatchReply.unavailable : _WatchReply.superseded;
      }
      return await _queueWatchSummary(acceptance)
          ? _WatchReply.queued
          : _WatchReply.superseded;
    } on DataModeRetired {
      return _WatchReply.superseded;
    } on WatchSummarySuperseded {
      return _WatchReply.superseded;
    } catch (_) {
      // An unavailable watch does not turn a resend into a provider poll.
      return _WatchReply.unavailable;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _replyOwnershipChanged();
    _notificationStatusRevision++;
    _notificationFrameRevision++;
    _invalidateNotificationEligibility();
    widget.watchSyncService.unbindWatchRefreshListener();
    widget.phoneWidgetNavigationService.unbind();
    unawaited(_syncTicks?.cancel());
    unawaited(widget.syncScheduler.cancel());
    super.dispose();
  }

  Future<void> _readRefreshInterval() async {
    try {
      _refreshInterval = await widget.refreshIntervalStore.read();
    } catch (_) {
      _refreshInterval = const RefreshIntervalPreference();
    }
  }

  Future<void> _readRingPreferences() {
    if (!mounted || _pendingRingPreferences != null)
      return Future<void>.value();
    final revision = _ringPreferenceRevision;
    return _ringPreferenceWork = _ringPreferenceWork.then((_) async {
      if (!mounted || revision != _ringPreferenceRevision) return;
      try {
        final value = await widget.watchRingPreferenceStore.read();
        final previous = _ringPreferences;
        if (mounted &&
            revision == _ringPreferenceRevision &&
            (previous?.usesDefaults != value.usesDefaults ||
                !listEquals(previous?.migratedIds, value.migratedIds))) {
          setState(() {
            _ringPreferences = value;
            if (previous != null) _watchPublicationPending = true;
          });
        }
      } catch (_) {
        // Retain the last confirmed selection.
        if (mounted && _ringPreferences == null) {
          _watchPublicationPending = true;
        }
      }
    });
  }

  Future<void> _readWidgetPreferences() {
    if (!mounted || _pendingWidgetPreferences != null)
      return Future<void>.value();
    final revision = _widgetPreferenceRevision;
    return _widgetPreferenceWork = _widgetPreferenceWork.then((_) async {
      if (!mounted || revision != _widgetPreferenceRevision) return;
      try {
        final value = await widget.phoneWidgetPreferenceStore.read();
        final previous = _widgetPreferences;
        if (mounted &&
            revision == _widgetPreferenceRevision &&
            (previous?.usesDefaults != value.usesDefaults ||
                !listEquals(previous?.migratedIds, value.migratedIds))) {
          setState(() {
            _widgetPreferences = value;
            if (previous != null) _widgetPublicationPending = true;
          });
        }
      } catch (_) {
        // Retain the last confirmed selection.
        if (mounted && _widgetPreferences == null) {
          _widgetPublicationPending = true;
        }
      }
    });
  }

  Future<void> _readAlertThresholds() async {
    try {
      _confirmAlertThresholds(await widget.alertThresholdStore.read());
    } catch (_) {
      // Retain the last confirmed rules.
      if (mounted && _alertThresholds == null) {
        _watchPublicationPending = true;
        _widgetPublicationPending = true;
      }
    }
  }

  void _confirmAlertThresholds(AlertThresholdPreferences value) {
    final previous = _alertThresholds;
    if (!mounted || previous?.sameSettings(value) == true) return;
    setState(() {
      _alertThresholds = value;
      _ruleGeneration++;
      // A later acceptance must replace publications made with the old rules.
      if (previous != null) {
        _watchPublicationPending = true;
        _widgetPublicationPending = true;
      }
    });
  }

  Future<void> _readNotificationPreferences(int loadRevision) async {
    if (!mounted || loadRevision != _loadRevision) return;
    _invalidateNotificationEligibility();
    final revision = _notificationEligibilityRevision;
    _notificationReads++;
    var resolved = true;
    bool current() =>
        mounted &&
        loadRevision == _loadRevision &&
        revision == _notificationEligibilityRevision &&
        _notificationWrites == 0;
    try {
      try {
        final enabled = await widget.recoveryNotificationStore.read();
        if (current()) _recoveryNotificationsEnabled = enabled;
      } catch (_) {
        resolved = false;
      }
      try {
        final enabled = await widget.alertNotificationStore.read();
        if (current()) _alertNotificationsEnabled = enabled;
      } catch (_) {
        resolved = false;
      }
      // Failed reads keep the last known UI choice, but cannot authorize an ask.
      if (current() && resolved) _notificationPreferencesResolved = true;
    } finally {
      _notificationReads--;
      _considerNotificationPermission();
    }
  }

  Future<bool> _updateAlertNotifications(bool enabled) async {
    final wasEnabled = _alertNotificationsEnabled;
    final revision = ++_alertNotificationRevision;
    _invalidateNotificationEligibility();
    _notificationWrites++;
    try {
      await widget.alertNotificationStore.write(enabled);
    } finally {
      _notificationWrites--;
      _invalidateNotificationEligibility();
    }
    if (revision == _alertNotificationRevision) {
      // Invalidate reads that began while the write was awaiting storage too.
      _alertNotificationRevision++;
      if (mounted) setState(() => _alertNotificationsEnabled = enabled);
    }
    if (mounted && widget.notificationCoordinator != null) {
      unawaited(_readNotificationPreferences(_loadRevision));
    }
    if (enabled &&
        !wasEnabled &&
        mounted &&
        revision + 1 == _alertNotificationRevision) {
      final coordinator = widget.notificationCoordinator;
      if (coordinator == null) return widget.alertNotifier.requestPermission();
      return await _requestNotificationPermission(
            coordinator,
            isEligible:
                () =>
                    _notificationForegroundReady &&
                    identical(coordinator, widget.notificationCoordinator) &&
                    revision + 1 == _alertNotificationRevision &&
                    _alertNotificationsEnabled,
          ) ??
          true;
    }
    return true;
  }

  /// Writes the switch, and asks Android for the permission when it goes on.
  ///
  /// The asking happens here because only a foreground Activity can ask, while
  /// the poll that posts runs in a background isolate with none.
  /// Answers whether a recovery may actually reach the reader now: the switch
  /// is the reader's wish, and Android has the last word on it.
  Future<bool> _updateRecoveryNotifications(bool enabled) async {
    final wasEnabled = _recoveryNotificationsEnabled;
    final revision = ++_recoveryNotificationRevision;
    _invalidateNotificationEligibility();
    _notificationWrites++;
    try {
      await widget.recoveryNotificationStore.write(enabled);
    } finally {
      _notificationWrites--;
      _invalidateNotificationEligibility();
    }
    if (revision == _recoveryNotificationRevision) {
      _recoveryNotificationRevision++;
      if (mounted) setState(() => _recoveryNotificationsEnabled = enabled);
    }
    if (mounted && widget.notificationCoordinator != null) {
      unawaited(_readNotificationPreferences(_loadRevision));
    }
    if (enabled &&
        !wasEnabled &&
        mounted &&
        revision + 1 == _recoveryNotificationRevision) {
      final coordinator = widget.notificationCoordinator;
      if (coordinator == null)
        return widget.recoveryNotifier.requestPermission();
      return await _requestNotificationPermission(
            coordinator,
            isEligible:
                () =>
                    _notificationForegroundReady &&
                    identical(coordinator, widget.notificationCoordinator) &&
                    revision + 1 == _recoveryNotificationRevision &&
                    _recoveryNotificationsEnabled,
          ) ??
          true;
    }
    return true;
  }

  Future<void> _updateRefreshInterval(RefreshIntervalPreference value) async {
    await widget.refreshIntervalStore.write(value);
    if (mounted) {
      setState(() {
        _refreshInterval = value;
      });
    }
    await _scheduleAutoSync(value.interval);
  }

  Future<void> _updateRingPreferences(
    _SnapshotAcceptance? acceptance,
    WatchRingPreferences Function(WatchRingPreferences current) update, {
    required String ringId,
    required bool selected,
  }) async {
    if (!mounted) return;
    final current = _pendingRingPreferences ?? _ringPreferences;
    final requiresCurrentRules =
        current?.usesDefaults == true ||
        (selected && ringId.startsWith('budget.'));
    if (current == null ||
        (requiresCurrentRules && !_hasCurrentRules(acceptance))) {
      throw StateError('Ring preferences are unavailable.');
    }
    final value = update(current);
    if (identical(value, current)) return;
    final revision = ++_ringPreferenceRevision;
    final store = widget.watchRingPreferenceStore;
    setState(() => _pendingRingPreferences = value);
    final work = _ringPreferenceWork.then((_) async {
      final int? settled;
      try {
        // A summary read before this save, in any engine, cannot follow it.
        settled = await _saveSurfaceSettings(
          () => store.write(value),
          retired: () => _replaceRetiredSurfaces(launcher: true),
        );
      } catch (_) {
        if (mounted && revision == _ringPreferenceRevision) {
          setState(() => _pendingRingPreferences = null);
        }
        rethrow;
      }
      if (!mounted) return;
      _noteSurfaceSettingsRevision(settled);
      // A settled native revision retires the launcher's committed frame, one
      // awaiting its first delivery included, so the widget publishes again.
      final launcherRetired = settled != null;
      setState(() {
        _ringPreferences = value;
        _watchPublicationPending = true;
        if (launcherRetired) _widgetPublicationPending = true;
        if (revision == _ringPreferenceRevision) _pendingRingPreferences = null;
      });
      // The accepted load publishes both while its source is current; once
      // work elsewhere retired it, the current retained input does.
      unawaited(_resendWatchSummary(launcher: launcherRetired));
    });
    // A failed save is reported to its picker but cannot poison later work.
    _ringPreferenceWork = work.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return work;
  }

  Future<void> _updateWidgetPreferences(
    _SnapshotAcceptance? acceptance,
    PhoneWidgetPreferences Function(PhoneWidgetPreferences current) update,
  ) async {
    if (!mounted) return;
    final current = _pendingWidgetPreferences ?? _widgetPreferences;
    if (current == null ||
        (current.usesDefaults &&
            (acceptance == null || !_isAccepted(acceptance)))) {
      throw StateError('Widget preferences are unavailable.');
    }
    final value = update(current);
    if (identical(value, current)) return;
    final revision = ++_widgetPreferenceRevision;
    final store = widget.phoneWidgetPreferenceStore;
    setState(() => _pendingWidgetPreferences = value);
    final work = _widgetPreferenceWork.then((_) async {
      final int? settled;
      try {
        // Launcher choices leave the watch summary's content alone.
        settled = await _saveSurfaceSettings(
          () => store.write(value),
          watch: false,
          retired: () => _publishLauncherSave(settled: true),
        );
      } catch (_) {
        if (mounted && revision == _widgetPreferenceRevision) {
          setState(() => _pendingWidgetPreferences = null);
        }
        rethrow;
      }
      if (!mounted) return;
      _noteSurfaceSettingsRevision(settled);
      setState(() {
        _widgetPreferences = value;
        _widgetEditUnpublished = true;
        if (revision == _widgetPreferenceRevision)
          _pendingWidgetPreferences = null;
      });
      _publishLauncherSave(settled: settled != null);
    });
    _widgetPreferenceWork = work.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return work;
  }

  /// Saves through the shared settings transaction. A failed write that
  /// native settled anyway is noted as a successful one would be and runs
  /// [retired], that save's replacement, before its own error is rethrown.
  /// One that overlaps a save still in flight, failed or not, leaves what it
  /// retired owed, so the save that settles replaces it too.
  Future<int?> _saveSurfaceSettings(
    Future<void> Function() save, {
    required void Function() retired,
    bool watch = true,
  }) async {
    if (watch) _watchSettingsSaves++;
    try {
      final settled = await widget.phoneWidgetSyncService.saveSettings(
        save,
        watch: watch,
      );
      // A native authority settled a revision before, so no revision now
      // means another save is still in flight.
      if (settled == null && mounted && _surfaceSettingsRevision != null) {
        if (watch) _watchPublicationPending = true;
        _widgetPublicationPending = true;
      }
      return settled;
    } on SettingsWriteFailure catch (failure) {
      if (mounted) {
        final settled = failure.settingsRevision;
        if (settled != null) {
          _noteSurfaceSettingsRevision(settled);
          retired();
        } else {
          if (watch) _watchPublicationPending = true;
          _widgetPublicationPending = true;
        }
      }
      Error.throwWithStackTrace(failure.error, failure.stackTrace);
    }
  }

  /// Replaces the watch item and, with [launcher], the launcher frame a
  /// settled save retired natively: the accepted load publishes both while
  /// its source is current, and otherwise one retained acceptance does.
  void _replaceRetiredSurfaces({required bool launcher}) {
    _watchPublicationPending = true;
    if (launcher) _widgetPublicationPending = true;
    unawaited(_resendWatchSummary(launcher: launcher));
  }

  /// Publishes the launcher frame a widget save owes. A launcher-only save
  /// that [settled] a revision keeps the watch item's content and a current
  /// send authority, so the watch is replaced too only when a publication is
  /// still owed, as one an overlapping or abandoned save left, from the same
  /// acceptance.
  void _publishLauncherSave({required bool settled}) {
    _widgetPublicationPending = true;
    final acceptance = _acceptance;
    if (settled && _watchPublicationPending) {
      // Both surfaces publish from one acceptance, the Dashboard's or the
      // current retained input's.
      unawaited(_resendWatchSummary(launcher: true));
    } else if (acceptance != null && _isAccepted(acceptance)) {
      unawaited(_syncPhoneWidget(acceptance));
    } else {
      // A failed or replaced Dashboard load leaves no input to publish.
      unawaited(_republishPhoneWidget());
    }
  }

  // Snapshot acceptance and preference transactions share one order. Provider
  // loads stay outside the queue so they can fetch while a save is pending.
  Future<T> _serializeSnapshotSettings<T>(
    Future<T> Function() operation,
  ) async {
    final previous = _snapshotSettingsWork;
    final done = Completer<void>();
    _snapshotSettingsWork = done.future;
    await previous;
    try {
      return await operation();
    } finally {
      done.complete();
    }
  }

  Future<void> _updateAlertThresholds(
    AlertThresholdPreferences Function(AlertThresholdPreferences current)
    update,
  ) => _serializeSnapshotSettings(() async {
    final current = _alertThresholds;
    if (!mounted || current == null) {
      throw StateError('Alert thresholds are unavailable.');
    }
    final value = update(current);
    final previous = _acceptance;
    final surfaceRevision = _surfaceRevision;
    // Evaluate before persisting so a core/FFI failure does not leave the
    // store ahead of in-memory prefs / dashboard alerts. Live rules never
    // shape a Demo sample, whose acceptance publishes as it is.
    final withAlerts =
        previous == null || previous.operation.mode == DataMode.demo
            ? null
            : widget.applyAlertSettings(previous.input, value);
    final settled = await _saveSurfaceSettings(
      () => widget.alertThresholdStore.write(value),
      retired: () => _replaceRetiredSurfaces(launcher: true),
    );
    if (!mounted) return;
    _noteSurfaceSettingsRevision(settled);
    _confirmAlertThresholds(value);
    // A settled revision retired both surfaces natively. Without an
    // acceptance that can publish the saved rules, the current acceptance or
    // retained input replaces them once this transaction settles.
    if (previous == null || withAlerts == null) {
      if (settled != null) _replaceRetiredSurfaces(launcher: true);
      return;
    }
    try {
      if (!await _isSourceCurrent(previous.operation, withAlerts)) {
        // Work elsewhere retired the accepted load, which can no longer
        // publish the saved rules.
        if (mounted) _replaceRetiredSurfaces(launcher: true);
        return;
      }
    } catch (_) {
      // The write is saved even if ownership cannot be confirmed.
      if (mounted && settled != null) _replaceRetiredSurfaces(launcher: true);
      return;
    }
    // A new load request may retain this accepted input as its owned fallback.
    if (!mounted ||
        surfaceRevision != _surfaceRevision ||
        !identical(previous, _acceptance)) {
      // A failed load or credential change cleared the acceptance meanwhile.
      if (mounted && settled != null) _replaceRetiredSurfaces(launcher: true);
      return;
    }
    final acceptance = _SnapshotAcceptance(
      operation: previous.operation,
      observationRevision: previous.observationRevision,
      input: previous.input,
      snapshot: withAlerts,
      rules: _alertThresholds,
      ruleGeneration: _ruleGeneration,
      surfaceRevision: surfaceRevision,
      poll: previous.poll,
      publication: previous.publication,
    );
    setState(() => _acceptance = acceptance);
    unawaited(_syncSurfaces(acceptance));
    unawaited(_syncAlerts(acceptance));
  });

  /// Publishes a save's [acceptance] to Wear, then to the launcher. Once
  /// native refuses it, one retained acceptance replaces both, so neither
  /// surface's fallback retires the other's ticket.
  Future<void> _syncSurfaces(_SnapshotAcceptance acceptance) async {
    if (!_isAccepted(acceptance)) return;
    _watchPublicationPending = true;
    if (await _queueWatchSummaryIfAvailable(acceptance) ==
        _WatchReply.superseded) {
      _widgetPublicationPending = true;
      await _resendWatchSummary(launcher: true);
    } else {
      await _syncPhoneWidget(acceptance);
    }
  }

  Future<_SnapshotAcceptance> _acceptSnapshot(
    DashboardSnapshot repositorySnapshot,
    int revision,
    AutomaticPollContext? poll,
    Set<ProviderConnectionId> retiredUpdates,
    DataModeOperation operation,
    PhoneWidgetPublicationInput publication,
  ) => _serializeSnapshotSettings(() async {
    if (!mounted || revision != _loadRevision) {
      throw const _RetiredDashboardLoad();
    }
    final rules = _rulesFor(operation.mode);
    final snapshot =
        rules == null
            ? repositorySnapshot
            : _evaluate(operation.mode, repositorySnapshot, rules);
    final current = await _ownsLoad(
      revision,
      () => _isSourceCurrent(operation, snapshot),
    );
    if (!current || !mounted || revision != _loadRevision) {
      throw const _RetiredDashboardLoad();
    }
    final acceptance = _SnapshotAcceptance(
      operation: operation,
      observationRevision: revision,
      input: repositorySnapshot,
      snapshot: snapshot,
      rules: rules,
      ruleGeneration: _ruleGeneration,
      surfaceRevision: _surfaceRevision,
      poll: poll,
      publication: publication,
    );
    await _retireAutomaticDispatches(operation);
    if (!await operation.guard(() async {
      // A refused acceptance still shows; its launcher request republishes.
      // Ownership is checked after it: the host or load may have retired.
      final accepted = await publication.accept(snapshot);
      // Rechecked after acceptance, which retires the first delivery of rows
      // a widget is still owed.
      final established =
          poll?.whollySkipped == true && await publication.isEstablished();
      if (!await _ownsLoad(
        revision,
        () => _source(operation).isSnapshotCurrent(snapshot),
      )) {
        throw _RetiredDashboardLoad(
          accepted: accepted && publication.load != null,
        );
      }
      setState(() {
        _acceptance = acceptance;
        _reportingUpdates.removeWhere((id, _) => retiredUpdates.contains(id));
        for (final outcome in repositorySnapshot.reportingOutcomes) {
          final key = outcome.connection.storageKey;
          _reportingUpdates[outcome
              .connection] = ConnectionReportingUpdate.completed(
            outcome,
            repositorySnapshot.snapshotOrdering[key],
          );
        }
        // Either surface may have to wait while a newer load takes over.
        if (poll?.whollySkipped != true) {
          _watchPublicationPending = true;
          _widgetPublicationPending = true;
        } else if (!established) {
          // An upgrade, a mode return or a widget still owed a frame
          // publishes the retained input once.
          _widgetPublicationPending = true;
        }
      });
    })) {
      throw const _RetiredDashboardLoad();
    }
    return acceptance;
  });

  Future<bool> _isSourceCurrent(
    DataModeOperation operation,
    DashboardSnapshot snapshot,
  ) async =>
      await operation.isCurrent() &&
      await _source(operation).isSnapshotCurrent(snapshot);

  Future<DashboardSnapshot> _loadSnapshot({
    bool automatic = false,
    bool cacheOnly = false,
    Future<WatchRefreshIntent?>? startupRequest,
    DataModeOperation? operation,
  }) {
    final load = _loadForegroundSnapshot(
      automatic: automatic,
      cacheOnly: cacheOnly,
      startupRequest: startupRequest,
      captured: operation,
    );
    _trackLoad(load);
    // FutureBuilder subscribes on the next build. Observe classified failures
    // immediately while preserving the original future for its error UI.
    load.ignore();
    return load;
  }

  /// Marks [load] as the newest one; a Wear reply waits for it to settle.
  void _trackLoad(Future<Object?> load) {
    late final Future<void> settled;
    settled = load.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      if (!identical(_activeLoad, settled)) return;
      _activeLoad = null;
      _replyOwnershipChanged();
    });
    _activeLoad = settled;
    _replyOwnershipChanged();
  }

  AutomaticPollContext _automaticPoll() => AutomaticPollContext(
    readInterval:
        () async => (await widget.refreshIntervalStore.read()).interval,
  );

  Future<DashboardSnapshot> _loadForegroundSnapshot({
    required bool automatic,
    required bool cacheOnly,
    Future<WatchRefreshIntent?>? startupRequest,
    DataModeOperation? captured,
  }) async {
    final revision = ++_loadRevision;
    _invalidateNotificationEligibility();
    var fromWatch = false;
    DataModeOperation? watchOperation;
    try {
      final request = await startupRequest;
      fromWatch = request != null || captured != null;
      var operation =
          captured ??
          (request == null
              ? await _modeAuthority.begin(cacheOnly: cacheOnly)
              : await request.operation(_modeAuthority));
      if (captured != null && !await captured.isCurrent()) {
        operation = await const WatchRefreshIntent.resend().operation(
          _modeAuthority,
        );
      }
      if (fromWatch) watchOperation = operation;
      if (!mounted || revision != _loadRevision)
        throw const _RetiredDashboardLoad();
      if (!_modeReady || _mode != operation.mode) {
        // Installed widgets may still show rows from before a mode write.
        if (!_modeReady) unawaited(_redrawPhoneWidget());
        setState(() {
          _mode = operation.mode;
          _modeReady = true;
        });
      }
      unawaited(_readRejectionNotices());
      // Wear taps are explicit: they bypass automatic admission and its anchor.
      final poll =
          automatic && request == null && !operation.mode.synthetic
              ? _automaticPoll()
              : null;
      await _readRefreshInterval();
      await _readRingPreferences();
      await _readWidgetPreferences();
      await _serializeSnapshotSettings(_readAlertThresholds);
      await _readNotificationPreferences(revision);
      DashboardSnapshot? retained;
      final needsWearAnchor =
          fromWatch && _acceptance == null && operation.allowsLiveWork;
      if (needsWearAnchor) {
        // A tap arriving before Dashboard acceptance has no refresh anchor.
        // The shared repository belongs to the newest load, so a retired tap
        // cannot probe it.
        if (!mounted || revision != _loadRevision) {
          throw const _RetiredDashboardLoad();
        }
        final cacheRead = operation.asCacheOnly();
        // A cache-only claim reports native dispatch anchors without
        // admitting or advancing them.
        final cadence = AutomaticPollContext(
          readInterval: () async => ManualRefreshWindow.floor,
        );
        final DashboardSnapshot probed;
        try {
          probed = await cacheRead.run(
            () => cadence.run(_source(cacheRead).load),
          );
        } catch (_) {
          // Dispatch evidence read before the failure still keeps the floor.
          if (mounted && revision == _loadRevision) {
            _noteAutomaticDispatch(cadence);
          }
          // The foreground timer can still recover. Background work waits for
          // a load that may reach providers.
          unawaited(
            _scheduleAutoSync(
              _refreshInterval.interval,
              registerHeadless: false,
            ),
          );
          rethrow;
        }
        await _retireAutomaticDispatches(cacheRead);
        if (!mounted || revision != _loadRevision) {
          throw const _RetiredDashboardLoad();
        }
        // The newest attempt, retained report or native dispatch is the floor.
        _noteAutomaticDispatch(cadence);
        if (!_refreshAllowed(probed.accounts.isEmpty ? null : probed)) {
          // The retained report and dispatch evidence keep advertising this
          // floor; a later native correction can still replace the dispatch.
          retained = probed;
          operation = watchOperation = cacheRead;
        } else {
          // The admitted attempt is the cooldown anchor, even if it fails and
          // only an older retained report remains.
          _wearRefreshAnchorAt = _now();
        }
      }
      if (fromWatch && !await operation.isCurrent()) throw DataModeRetired();
      // Registering missing periodic work can run its first callback immediately.
      unawaited(
        _scheduleAutoSync(
          _refreshInterval.interval,
          registerHeadless: !(fromWatch && operation.cacheOnly),
        ),
      );
      final context = poll;
      Future<_SnapshotAcceptance> load() =>
          _observedLoad(revision, operation, retained: retained);
      final acceptance = await operation.run(
        () => context == null ? load() : context.run(load),
      );
      if (!operation.cacheOnly) unawaited(_syncRecoveries(acceptance));
      if (fromWatch) {
        // The native sender rechecks after readiness, where a switch can
        // retire either kind of Wear request.
        unawaited(_publishWatchReply(acceptance));
      } else if (_watchPublicationPending) {
        unawaited(_syncWatch(acceptance));
      } else if (context?.whollySkipped == true) {
        unawaited(_seedWatchSummary(acceptance));
      }
      if (fromWatch && operation.cacheOnly) {
        // A watch-only resend replaces only a launcher frame it retired.
        final snapshot = acceptance.snapshot;
        unawaited(
          _replaceRetiredLauncherFrame(
            operation,
            acceptance.publication,
            acceptance.publication.settingsRevision,
            acceptance.rules,
            snapshot,
            () => _isSourceCurrent(operation, snapshot),
          ),
        );
      } else if (_widgetPublicationPending) {
        unawaited(_syncPhoneWidget(acceptance));
      }
      if (!operation.cacheOnly && context?.whollySkipped != true) {
        unawaited(_syncAlerts(acceptance));
      }
      return acceptance.snapshot;
    } catch (error) {
      // Work elsewhere, such as a headless poll, wrote the source after native
      // accepted this load. Unless a newer load replaces it, the retained
      // input that work left replaces both surfaces.
      final replaced =
          error is _RetiredDashboardLoad &&
          error.accepted &&
          mounted &&
          revision == _loadRevision;
      if (replaced) _replaceRetiredSurfaces(launcher: true);
      if (mounted && watchOperation != null && !replaced) {
        try {
          // A newer load or mode answers the tap with current evidence. A
          // failed resend-only read leaves the watch-only reply to answer.
          if (error is DataModeRetired ||
              (error is _RetiredDashboardLoad && revision != _loadRevision) ||
              (error is DashboardLoadException && watchOperation.cacheOnly) ||
              !await watchOperation.isCurrent()) {
            unawaited(_resendWatchSummary());
          }
        } catch (_) {
          // Unavailable mode storage cannot authorize another publication.
        }
      }
      if (mounted && revision == _loadRevision && !_modeChangeInFlight) {
        _acceptance = null;
      }
      if (error is _RetiredDashboardLoad || error is DataModeRetired) {
        throw const DashboardLoadException(
          details: 'Connection changed during refresh.',
        );
      }
      rethrow;
    } finally {
      await _readRejectionNotices();
    }
  }

  Future<bool> _ownsLoad(int revision, Future<bool> Function() validate) async {
    if (!mounted || revision != _loadRevision) return false;
    try {
      return await validate() && mounted && revision == _loadRevision;
    } catch (_) {
      // Unavailable proof cannot authorize publication.
      return false;
    }
  }

  Future<_SnapshotAcceptance> _observedLoad(
    int revision,
    DataModeOperation operation, {
    DashboardSnapshot? retained,
  }) async {
    final repository = _source(operation);
    final poll = AutomaticPollContext.current;
    if (!mounted || revision != _loadRevision || !await operation.isCurrent()) {
      throw const _RetiredDashboardLoad();
    }
    if (!mounted || revision != _loadRevision)
      throw const _RetiredDashboardLoad();
    final prepare = widget.prepareLive;
    if (!_livePrepared &&
        prepare != null &&
        !operation.mode.synthetic &&
        !operation.cacheOnly) {
      if (!await operation.guard(prepare)) throw const _RetiredDashboardLoad();
      _livePrepared = true;
      if (!mounted || revision != _loadRevision)
        throw const _RetiredDashboardLoad();
    }
    // Ordered before the repository read; a newer load's acceptance wins.
    final publication = await widget.phoneWidgetSyncService.beginLoad();
    if (!mounted || revision != _loadRevision)
      throw const _RetiredDashboardLoad();
    _noteSurfaceSettingsRevision(publication.settingsRevision);
    // A superseded request cannot leave a row spinning without active work.
    _reportingUpdates.removeWhere((_, update) => update.checking);
    final observed = <ProviderConnectionId, ConnectionReportingUpdate?>{};
    Future<void> reconcileObserved() async {
      Future<bool> current(DashboardSnapshot proof) =>
          _ownsLoad(revision, () => _isSourceCurrent(operation, proof));

      // A connection can retire even if the rejected load never observed it.
      final retained = {
        for (final entry in _reportingUpdates.entries)
          if (!observed.containsKey(entry.key) &&
              !entry.value.checking &&
              entry.value.credentialVersion != null)
            entry.key: entry.value,
      };
      for (final MapEntry(key: id, value: previous) in observed.entries) {
        // A completed row can still be current when a sibling retires the
        // aggregate. Unfinished work can only fall back to verified feedback.
        for (final update in [_reportingUpdates[id], previous]) {
          if (update == null ||
              update.checking ||
              update.credentialVersion == null) {
            continue;
          }
          if (await current(reportingUpdatesProof([update]))) {
            retained[id] = update;
            break;
          }
        }
      }
      await pruneUnverifiedReportingUpdates(retained, current);
      if (await operation.isCurrent() && mounted && revision == _loadRevision) {
        setState(() {
          _reportingUpdates.removeWhere(
            (id, update) =>
                observed.containsKey(id) || update.credentialVersion != null,
          );
          _reportingUpdates.addAll(retained);
        });
      }
    }

    try {
      final DashboardSnapshot snapshot;
      try {
        snapshot =
            retained ??
            await repository.loadObserved((update) {
              if (!mounted || revision != _loadRevision) return;
              final id = update.connection;
              observed.putIfAbsent(id, () => _reportingUpdates[id]);
              setState(() => _reportingUpdates[id] = update);
            });
      } on DashboardLoadException catch (failure) {
        // A native claim recorded before the failure still keeps the floor,
        // even when a sibling retires the aggregate failure.
        await _noteOwnedAutomaticDispatch(operation, poll);
        final current = await _ownsLoad(
          revision,
          () async =>
              await operation.isCurrent() &&
              await repository.isFailureCurrent(failure),
        );
        if (!current || !mounted || revision != _loadRevision) {
          throw const _RetiredDashboardLoad();
        }
        setState(() {
          _reportingUpdates.clear();
          for (final outcome in failure.reportingOutcomes) {
            _reportingUpdates[outcome
                .connection] = ConnectionReportingUpdate.completed(
              outcome,
              failure.snapshotOrdering[outcome.connection.storageKey],
            );
          }
        });
        rethrow;
      } catch (_) {
        await _noteOwnedAutomaticDispatch(operation, poll);
        await reconcileObserved();
        throw const DashboardLoadException();
      }
      // Acceptance may still reject the aggregate.
      await _noteOwnedAutomaticDispatch(operation, poll);
      final retired = <ProviderConnectionId>{};
      for (final entry in _reportingUpdates.entries.toList()) {
        final id = entry.key;
        final update = entry.value;
        final key = id.storageKey;
        final stamp = snapshot.connectionVersions[key];
        if (poll?.observes(key) != false ||
            stamp == null ||
            update.credentialVersion?.sameCache(CredentialVersion(stamp)) !=
                true) {
          retired.add(id);
          continue;
        }
        if (!snapshot.snapshotOrdering.containsKey(key)) continue;
        // The repository supplies any failure feedback that survives a checked
        // skip. A prior live success keeps its original verification proof.
        final outcome = update.outcome;
        if (!observed.containsKey(id) &&
            outcome?.category == ReportingOutcomeCategory.success &&
            outcome?.source == ReportingOutcomeSource.live &&
            outcome?.freshness == ReportingOutcomeFreshness.current &&
            await _ownsLoad(
              revision,
              () =>
                  _isSourceCurrent(operation, reportingUpdatesProof([update])),
            )) {
          continue;
        }
        retired.add(id);
      }
      if (!await _ownsLoad(
        revision,
        () => _isSourceCurrent(operation, snapshot),
      )) {
        throw const _RetiredDashboardLoad();
      }
      return await _acceptSnapshot(
        snapshot,
        revision,
        poll,
        retired,
        operation,
        publication,
      );
    } on _RetiredDashboardLoad {
      await reconcileObserved();
      rethrow;
    } finally {
      if (mounted && revision == _loadRevision) {
        setState(
          () => _reportingUpdates.removeWhere((_, update) => update.checking),
        );
      }
    }
  }

  bool _isAccepted(_SnapshotAcceptance acceptance) =>
      mounted &&
      acceptance.surfaceRevision == _surfaceRevision &&
      identical(acceptance, _acceptance);

  bool _hasCurrentRules(_SnapshotAcceptance? acceptance) =>
      acceptance != null &&
      acceptance.rules != null &&
      (acceptance.operation.mode == DataMode.demo ||
          acceptance.ruleGeneration == _ruleGeneration) &&
      _isAccepted(acceptance);

  Future<void> _syncRecoveries(_SnapshotAcceptance acceptance) async {
    final operation = acceptance.operation;
    if (operation.mode.synthetic || operation.cacheOnly) return;
    final snapshot = acceptance.snapshot;
    bool observesCurrentInput() =>
        mounted &&
        acceptance.surfaceRevision == _surfaceRevision &&
        acceptance.observationRevision == _acceptance?.observationRevision;
    Future<bool> isCurrent() async =>
        observesCurrentInput() &&
        await _isSourceCurrent(operation, snapshot) &&
        observesCurrentInput();
    // A Plan recovery choice saved after this point mutes this observation.
    final preferenceRevision = _recoveryNotificationRevision;
    try {
      var notifications = false;
      try {
        notifications = await widget.recoveryNotificationStore.read();
      } catch (_) {
        // Preference failure mutes posting, not tracking or wake scheduling.
      }
      if (!await isCurrent()) return;
      await operation.run(
        () => syncPlanRecoveries(
          snapshot,
          widget.recoveryWatchlistStore,
          widget.recoveryNotifier,
          widget.recoveryWake,
          notifications: notifications && _recoveryNotificationsEnabled,
          // Every save in this isolate bumps the revision before writing, and
          // the Mock switch is marked before it closes admission. With no await
          // after the final ownership proof, neither the choice nor ownership
          // can move before submission; a begun switch leaves it pending.
          admitDelivery:
              () async =>
                  _modeChangeInFlight
                      ? null
                      : mounted &&
                          preferenceRevision == _recoveryNotificationRevision &&
                          _recoveryNotificationsEnabled,
          readRecoveries: widget.readPlanRecoveries,
          readWindows: widget.readExhaustedWindows,
          poll: acceptance.poll,
          isCurrent: isCurrent,
        ),
      );
    } catch (_) {
      // Recovery bookkeeping cannot publish retired data or block the dashboard.
    }
  }

  Future<void> _syncAlerts(_SnapshotAcceptance acceptance) async {
    final operation = acceptance.operation;
    final snapshot = acceptance.snapshot;
    bool accepted() =>
        _hasCurrentRules(acceptance) &&
        !operation.mode.synthetic &&
        !operation.cacheOnly;
    if (!accepted()) return;
    await operation.run(
      () => AlertNotificationDelivery(
        preferences: widget.alertNotificationStore,
        conditions: widget.alertConditionStore,
        notifier: widget.alertNotifier,
      ).sync(
        snapshot,
        poll: acceptance.poll,
        isAccepted: accepted,
        alertThresholds: acceptance.rules,
        isDeliveryEnabled: () => _alertNotificationsEnabled,
        isCurrent: () async {
          if (!accepted()) return false;
          final current = await _isSourceCurrent(operation, snapshot);
          return current && accepted();
        },
      ),
    );
  }

  Future<void> _scheduleAutoSync(
    Duration interval, {
    bool registerHeadless = true,
  }) async {
    await widget.syncScheduler.schedule(interval);
    if (!registerHeadless) return;
    await widget.scheduleHeadlessSync(interval);
    _headlessRegistered = true;
  }

  void _completeDeferredRegistration() {
    if (_headlessRegistered || _headlessRegistering) return;
    _headlessRegistering = true;
    unawaited(() async {
      try {
        await widget.scheduleHeadlessSync(_refreshInterval.interval);
        _headlessRegistered = true;
      } catch (_) {
        // The next ordinary Live tick retries the registration.
      } finally {
        _headlessRegistering = false;
      }
    }());
  }

  Future<void> _onScheduledSync() async {
    if (_autoSyncInFlight ||
        !mounted ||
        !_modeReady ||
        _mode.synthetic ||
        _reportingCheckActive) {
      return;
    }
    _autoSyncInFlight = true;
    final revision = ++_loadRevision;
    // The displayed Future changes only after acceptance; Wear waits for both.
    final settled = Completer<void>();
    _trackLoad(settled.future);
    DataModeOperation? currentOperation;
    final poll = _automaticPoll();
    try {
      final operation = currentOperation = await _modeAuthority.begin();
      if (operation.mode.synthetic) return;
      // Ordinary Live polling completes registration a resend-only launch
      // deferred.
      _completeDeferredRegistration();
      if (_ringPreferences == null) await _readRingPreferences();
      if (_widgetPreferences == null) await _readWidgetPreferences();
      if (_alertThresholds == null) {
        await _serializeSnapshotSettings(() async {
          if (_alertThresholds == null) await _readAlertThresholds();
        });
      }
      // Do not invalidate: load() already refetches, and clearing caches would
      // drop stale-with-issue recovery on a failed automatic tick.
      final acceptance = await operation.run(
        () => poll.run(() => _observedLoad(revision, operation)),
      );
      if (mounted && revision == _loadRevision) {
        setState(() {
          _snapshot = Future.value(acceptance.snapshot);
        });
      }
      if (_watchPublicationPending) {
        await _syncWatch(acceptance);
      } else if (poll.whollySkipped) {
        unawaited(_seedWatchSummary(acceptance));
      }
      if (_widgetPublicationPending) {
        await _syncPhoneWidget(acceptance);
      }
      await _syncRecoveries(acceptance);
      if (!poll.whollySkipped) await _syncAlerts(acceptance);
    } on _RetiredDashboardLoad catch (retired) {
      // A rejected selection cannot replace the last accepted Dashboard. One
      // native accepted still replaces both surfaces from retained input.
      if (retired.accepted && mounted && revision == _loadRevision) {
        _replaceRetiredSurfaces(launcher: true);
      }
    } on DashboardLoadException catch (failure) {
      // Keep successful data, but an error-only dashboard must follow the most
      // recent guarded result rather than the exception from its first load.
      try {
        final operation = currentOperation;
        if (operation == null || !await operation.isCurrent()) return;
        final previous = _acceptance;
        if (previous != null &&
            await _isSourceCurrent(previous.operation, previous.snapshot)) {
          return;
        }
        if (await _source(operation).isFailureCurrent(failure) &&
            await operation.isCurrent() &&
            mounted &&
            revision == _loadRevision) {
          final failed = Future<DashboardSnapshot>.error(failure);
          // FutureBuilder attaches on the next build; observe errors meanwhile.
          failed.ignore();
          setState(() {
            _acceptance = null;
            _snapshot = failed;
          });
        }
      } catch (_) {
        // Unavailable ownership cannot replace reader-visible state.
      }
    } catch (_) {
      // Automatic sync failures keep the last successful snapshot visible.
    } finally {
      _autoSyncInFlight = false;
      settled.complete();
    }
  }

  Future<void> _updateMockDataEnabled(bool value) =>
      _updateSampleMode(DataMode.mock, value);

  Future<void> _updateDemoDataEnabled(bool value) =>
      _updateSampleMode(DataMode.demo, value);

  /// Turns synthetic [mode] on, replacing the other one in the same switch,
  /// or off, back to Live. Turning off a mode that is not active does nothing.
  Future<void> _updateSampleMode(DataMode mode, bool enabled) async {
    if (_modeChangeInFlight) return;
    _modeChangeInFlight = true;
    try {
      await _serializeSnapshotSettings(() async {
        if (!mounted || !_modeReady || enabled == (_mode == mode)) return;
        ++_loadRevision;
        ++_noticeRevision;
        setState(
          () => _reportingUpdates.removeWhere((_, update) => update.checking),
        );
        final previous = _acceptance;
        final DataModeSwitch result;
        try {
          result = await _modeAuthority.switchTo(
            enabled ? mode : DataMode.live,
          );
        } catch (error) {
          // A load denied during the drain may have advanced the load revision
          // without replacing the last acceptance. Its revision is independent.
          var owned = false;
          try {
            owned =
                previous != null &&
                _isAccepted(previous) &&
                await _isSourceCurrent(previous.operation, previous.input);
          } catch (_) {
            // A vanished credential cannot restore the old snapshot.
          }
          if (mounted) {
            ++_loadRevision;
            setState(() {
              if (error is DataModeWriteFailure &&
                  error.unresolvedStorageFailure) {
                _accountStorageUnresolved = true;
              }
              if (owned && identical(previous, _acceptance)) {
                _snapshot = Future.value(previous!.snapshot);
                unawaited(_readRejectionNotices());
              } else {
                _acceptance = null;
                _snapshot = _loadSnapshot(cacheOnly: true);
              }
            });
          }
          rethrow;
        }
        if (!mounted) return;
        _surfaceRevision++;
        _wearRefreshAnchorAt = null;
        _sampleSource(result.state.mode)?.invalidate();
        setState(() {
          _mode = result.state.mode;
          _accountStorageUnresolved =
              _accountStorageUnresolved || result.unresolvedStorageFailure;
          _acceptance = null;
          _reportingUpdates.clear();
          _rejectionNotices = const [];
          _snapshot = _loadSnapshot();
        });
        // The outgoing generation's rows leave the launcher before the load.
        unawaited(_redrawPhoneWidget());
      });
    } finally {
      _modeChangeInFlight = false;
    }
  }

  Future<void> _syncWatch(_SnapshotAcceptance acceptance) async {
    if (!_isAccepted(acceptance)) return;
    _watchPublicationPending = true;
    try {
      await _queueWatchSummary(acceptance);
    } on WatchSummarySuperseded {
      // Work in another engine accepted a newer load, or a save outran this
      // read; the current retained input answers once an active load, which
      // may be awaiting this sync, settles.
      unawaited(_resendWatchSummary());
    } catch (_) {
      // Watch availability must not block the phone dashboard.
    }
  }

  /// A cadence-skipped load still seeds Wear's first v10 summary, after an
  /// upgrade, or the replacement for the empty one a mode transition left,
  /// from its retained input. Asked after acceptance, since watch
  /// availability must not hold the phone dashboard.
  Future<void> _seedWatchSummary(_SnapshotAcceptance acceptance) async {
    if (await widget.watchSyncService.isEstablished()) return;
    await _syncWatch(acceptance);
  }

  /// A warm resume resumes native pending or owed work, and sends again a
  /// publication the accepted load still owes after a failed attempt.
  Future<void> _resumeWatchPublication() async {
    await widget.watchSyncService.resume();
    final acceptance = _acceptance;
    if (mounted && _watchPublicationPending && acceptance != null) {
      await _syncWatch(acceptance);
    }
  }

  Future<void> _publishWatchReply(_SnapshotAcceptance acceptance) async {
    try {
      // A lost acceptance hands the reply to the newest owner, even within
      // one mode generation.
      if (!await _queueWatchSummary(acceptance)) await _resendWatchSummary();
    } on DataModeRetired {
      await _resendWatchSummary();
    } on WatchSummarySuperseded {
      await _resendWatchSummary();
    } catch (_) {
      // Unavailable publication cannot authorize provider work.
    }
  }

  Future<void> _syncPhoneWidget(_SnapshotAcceptance acceptance) async {
    if (!_isAccepted(acceptance)) return;
    _widgetPublicationPending = true;
    final publicationRevision = ++_widgetPublicationRevision;
    final preferences = _widgetPreferences;
    final settingsRevision = _surfaceSettingsRevision;
    if (preferences == null) return;
    final snapshot = acceptance.snapshot;
    bool accepted() =>
        publicationRevision == _widgetPublicationRevision &&
        _hasCurrentRules(acceptance) &&
        identical(preferences, _widgetPreferences);
    Future<bool> proof() => _isSourceCurrent(acceptance.operation, snapshot);
    try {
      // Work elsewhere may have retired the source before the request.
      final published =
          accepted() && await proof() && accepted()
              ? await _dispatchPhoneWidget(
                acceptance.operation,
                snapshot,
                acceptance.publication,
                preferences,
                settingsRevision,
                accepted: accepted,
                proof: proof,
              )
              : null;
      // The saved change stays pending until a publication represents it.
      if (published != true &&
          accepted() &&
          (published == false || _widgetEditUnpublished)) {
        unawaited(_republishPhoneWidget());
      }
    } catch (_) {
      // Launcher widget updates must not block the phone dashboard.
      developer.log(
        'Dashboard refresh could not update the widget.',
        name: phoneWidgetLogName,
      );
    }
  }

  /// Publishes [snapshot] under [publication]. Completes with `true` once
  /// committed rows represent the pending request, `false` when native
  /// refused it or a newer request superseded it after the last guard and
  /// `null` when [accepted] or [proof] retired it.
  Future<bool?> _dispatchPhoneWidget(
    DataModeOperation operation,
    DashboardSnapshot snapshot,
    PhoneWidgetPublicationInput publication,
    PhoneWidgetPreferences preferences,
    int? settingsRevision, {
    required bool Function() accepted,
    required Future<bool> Function() proof,
  }) async {
    var dispatchAllowed = false;
    final published = await operation.run(
      () => publication
          .withSettingsRevision(settingsRevision)
          .run(
            () => widget.phoneWidgetSyncService.sync(
              snapshot,
              preferences,
              isCurrent:
                  () async =>
                      dispatchAllowed =
                          accepted() && await proof() && accepted(),
            ),
          ),
    );
    if (!dispatchAllowed || !accepted()) return null;
    if (!published) return false;
    _widgetPublicationPending = false;
    _widgetEditUnpublished = false;
    return true;
  }

  void _noteSurfaceSettingsRevision(int? revision) {
    if (revision != null && revision > (_surfaceSettingsRevision ?? -1)) {
      _surfaceSettingsRevision = revision;
    }
  }

  /// Cache reads a widget retry may waste while work in another engine keeps
  /// retiring its source or refusing its ticket.
  static const _widgetRepublishAttempts = 3;

  /// Publishes the pending launcher request from retained input, or from
  /// confirmed absence, without a provider poll: native refused it, its
  /// source retired or no Dashboard acceptance exists. A synthetic mode reads
  /// its captured sample source in the current generation; without one, the
  /// choice and stored rows stay as they are. Each accepted attempt also asks
  /// Wear's state, which adopts a still-valid pending watch item, and
  /// otherwise sends Wear that same acceptance; Dashboard acceptance and
  /// notification work stay as they are. An active load publishes the
  /// request itself; the retry resumes once it settles.
  Future<void> _republishPhoneWidget() async {
    if (_widgetRepublishing) return;
    _widgetRepublishing = true;
    try {
      // A superseded attempt is not a failure: the newer state retries.
      var failures = 0;
      while (failures < _widgetRepublishAttempts) {
        while (mounted && _activeLoad != null) {
          await _activeLoad;
        }
        final preferences = _widgetPreferences;
        if (!mounted ||
            !_widgetPublicationPending ||
            !_modeReady ||
            preferences == null ||
            _rulesFor(_mode) == null) {
          return;
        }
        final settingsRevision = _surfaceSettingsRevision;
        final publicationRevision = _widgetPublicationRevision;
        // A switch that refused the publication may fail and keep this mode.
        final operation = await _modeAuthority.begin(
          cacheOnly: true,
          waitForSwitch: true,
        );
        final rules = _rulesFor(operation.mode);
        if (rules == null) return;
        // A cache read through the shared repository would retire a newer
        // load, and a newer request or edit publishes itself.
        bool accepted() =>
            mounted &&
            _activeLoad == null &&
            publicationRevision == _widgetPublicationRevision &&
            identical(preferences, _widgetPreferences) &&
            identical(rules, _rulesFor(operation.mode));
        // Ordered before the cache read; a newer load's acceptance wins.
        final publication = await widget.phoneWidgetSyncService.beginLoad();
        if (!accepted()) continue;
        final retained = await _retainedWidgetInput(
          operation,
          rules,
          preferences,
        );
        if (!accepted()) continue;
        // Unreadable sample rows keep the saved choice and the stored rows.
        if (retained == null) return;
        final (snapshot, proof) = retained;
        if (await proof() &&
            accepted() &&
            await operation.run(() => publication.accept(snapshot))) {
          // Accepting retires the send authority of a still-valid watch item
          // waiting behind a put or in retry, and of a summary still in
          // flight elsewhere, such as a headless poll's. Wear's answer and
          // send stay off the launcher's path and do not depend on it.
          unawaited(
            _sendAcceptedWatchSummary(
              operation,
              publication,
              settingsRevision,
              snapshot,
              proof,
            ),
          );
          final published = await _dispatchPhoneWidget(
            operation,
            snapshot,
            publication,
            preferences,
            settingsRevision,
            accepted: accepted,
            proof: proof,
          );
          if (published == true) return;
        }
        failures++;
      }
    } catch (_) {
      // Unavailable mode or cache storage; the next load publishes.
    } finally {
      _widgetRepublishing = false;
    }
  }

  /// Asks Wear's state after a launcher retry accepted [publication], which
  /// adopts and resumes a still-valid watch item that acceptance retired.
  /// Without an established item, sends Wear [snapshot] under the same
  /// acceptance, tagged with [settingsRevision], so neither surface's send
  /// retires the other's ticket. A refused or failed send leaves the
  /// publication pending for the next load or resume.
  Future<void> _sendAcceptedWatchSummary(
    DataModeOperation operation,
    PhoneWidgetPublicationInput publication,
    int? settingsRevision,
    DashboardSnapshot snapshot,
    Future<bool> Function() proof,
  ) async {
    if (await widget.watchSyncService.isEstablished() || !mounted) return;
    _watchPublicationPending = true;
    final preferences = _ringPreferences;
    final saves = _watchSettingsSaves;
    if (preferences == null) return;
    bool current() => mounted && identical(preferences, _ringPreferences);
    bool? owned;
    try {
      await _requireWatchRingCapacity(snapshot, preferences, operation.mode);
      await operation.run(
        () => publication
            .withSettingsRevision(settingsRevision)
            .run(
              () => widget.watchSyncService.sync(
                snapshot,
                preferences,
                manualRefreshAnchorAt: _manualRefreshAnchorAt(snapshot),
                mockDataMode: operation.mode == DataMode.mock,
                isCurrent:
                    () async => owned = current() && await proof() && current(),
              ),
            ),
      );
    } catch (_) {
      return;
    }
    if (owned != false && current() && saves == _watchSettingsSaves) {
      _watchPublicationPending = false;
    }
  }

  /// Whether retained [snapshot], or confirmed absence when it is `null`,
  /// read from [operation]'s source supplies launcher rows for [preferences].
  /// The no-provider placeholder, a sample failure, which confirms no
  /// absence, and a sample without accounts or without an eligible row for a
  /// nonempty or default selection supply none.
  bool _suppliesLauncherRows(
    DataModeOperation operation,
    DashboardSnapshot? snapshot,
    PhoneWidgetPreferences preferences,
  ) =>
      !operation.mode.synthetic ||
      (_sampleSource(operation.mode) != null &&
          snapshot != null &&
          snapshot.accounts.isNotEmpty &&
          (preferences.selectedIds?.isEmpty == true ||
              buildPhoneWidgetPayload(snapshot, preferences).rows.isNotEmpty));

  /// The retained input a widget retry publishes, with its source proof, or
  /// `null` when no captured sample source has rows to read for [preferences].
  Future<(DashboardSnapshot, Future<bool> Function())?> _retainedWidgetInput(
    DataModeOperation operation,
    AlertThresholdPreferences rules,
    PhoneWidgetPreferences preferences,
  ) async {
    // The no-provider placeholder supplies no sample rows.
    if (operation.mode.synthetic && _sampleSource(operation.mode) == null) {
      return null;
    }
    try {
      final snapshot = _evaluate(
        operation.mode,
        await operation.run(_source(operation).load),
        rules,
      );
      if (!_suppliesLauncherRows(operation, snapshot, preferences)) {
        return null;
      }
      return (snapshot, () => _isSourceCurrent(operation, snapshot));
    } on DashboardLoadException catch (failure) {
      if (!_suppliesLauncherRows(operation, null, preferences)) return null;
      // Confirmed absence replaces rows the cache no longer holds.
      return (
        failure.selection,
        () async =>
            await operation.isCurrent() &&
            await _source(operation).isFailureCurrent(failure),
      );
    }
  }

  /// Redraws installed widgets from current-generation rows, or empty.
  Future<void> _redrawPhoneWidget() async {
    try {
      await widget.phoneWidgetSyncService.redraw();
    } catch (_) {
      developer.log('Could not redraw the widget.', name: phoneWidgetLogName);
    }
  }

  /// Throws [WatchSummarySuperseded] when native refuses the accepted load or
  /// the settings revision [preferences] were confirmed at.
  Future<bool> _queueWatchSummary(_SnapshotAcceptance acceptance) async {
    final preferences = _ringPreferences;
    final settingsRevision = _surfaceSettingsRevision;
    final saves = _watchSettingsSaves;
    if (preferences == null) return false;
    final snapshot = acceptance.snapshot;
    bool accepted() =>
        _hasCurrentRules(acceptance) &&
        identical(preferences, _ringPreferences);
    if (!accepted()) return false;
    final operation = acceptance.operation;
    if (!await operation.isCurrent()) throw DataModeRetired();
    if (!await _source(operation).isSnapshotCurrent(snapshot) || !accepted()) {
      return false;
    }
    await _requireWatchRingCapacity(snapshot, preferences, operation.mode);
    // The native sender holds the lease only once Google Play services is
    // ready, after this acceptance proves its ownership again.
    bool? owned;
    try {
      await operation.run(
        () => acceptance.publication
            .withSettingsRevision(settingsRevision)
            .run(
              () => widget.watchSyncService.sync(
                snapshot,
                preferences,
                manualRefreshAnchorAt: _manualRefreshAnchorAt(snapshot),
                mockDataMode: operation.mode == DataMode.mock,
                isCurrent:
                    () async =>
                        owned =
                            accepted() &&
                            await _isSourceCurrent(operation, snapshot) &&
                            accepted(),
              ),
            ),
      );
    } on WatchSummarySuperseded {
      // This acceptance lost ownership at readiness; nothing was sent.
      if (owned == false) return false;
      rethrow;
    }
    if (owned == false) return false;
    if (accepted() && saves == _watchSettingsSaves) {
      _watchPublicationPending = false;
    }
    return true;
  }

  /// Ring choices beyond capacity under [mode]'s capabilities build no
  /// replacement, so nothing is queued and a pending publication stays
  /// pending; native pending or owed work still resumes.
  Future<void> _requireWatchRingCapacity(
    DashboardSnapshot snapshot,
    WatchRingPreferences preferences,
    DataMode mode,
  ) async {
    final paused = _claudePlanPausedIn(mode);
    final reason = watchRingCapacityReason(
      watchRingSelectionIds(snapshot, preferences, claudePlanPaused: paused),
      claudePlanPaused: paused,
    );
    if (reason == null) return;
    await widget.watchSyncService.resume();
    throw StateError(reason);
  }

  Future<void> _onSettingsSyncWatch() async {
    final acceptance = _acceptance;
    var queued = false;
    try {
      queued = acceptance != null && await _queueWatchSummary(acceptance);
    } on WatchSummarySuperseded {
      // Only a retry that actually handed a current summary over is queued.
      queued = await _resendWatchSummary();
    } finally {
      // Without a replacement, explicit sync still resumes pending or owed
      // native publication.
      if (!queued) await widget.watchSyncService.resume();
    }
    if (!queued) throw StateError('Watch sync unavailable');
  }

  /// Pull-to-refresh runs the same reload the app-bar action does; the gesture
  /// only has to hold the spinner until the snapshot lands.
  Future<void> _pullToRefresh() async {
    _reload();
    try {
      await _snapshot;
    } catch (_) {
      // The failure state already tells the reader; the gesture just ends.
    }
  }

  void _reload({
    bool forCredentialChange = false,
    DataModeOperation? operation,
  }) {
    if (!forCredentialChange && _reportingCheckActive) return;
    // Samples are cached across auto-sync; refresh should draw a new seed.
    // Live repos must not clear connection recovery caches on every refresh.
    if (_mode.synthetic) _sampleSource(_mode)?.invalidate();
    setState(() {
      _snapshot = _loadSnapshot(operation: operation);
    });
  }

  /// The top mark is a way in, not a copy: it opens the Dashboard when another
  /// tab is showing and then brings the first unhealthy section into view
  /// (PHONE_DASHBOARD_DESIGN.md).
  void _revealProblem(String provider) {
    setState(() {
      _selectedIndex = _dashboardIndex;
      _reveal = (provider: provider, token: (_reveal?.token ?? 0) + 1);
    });
    // A request is answered once. Left standing, it would scroll again every
    // time the reader came back to the tab, long after they asked.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _reveal = null);
      }
    });
  }

  void _openProviders() {
    setState(() {
      _selectedIndex = _providersIndex;
    });
  }

  void _editReportingKey(ProviderConnectionId connection) {
    setState(() {
      _editReportingConnection = connection;
      _connectionReveal = null;
      _selectedIndex = _providersIndex;
    });
  }

  Future<void> _saveReportingCredential(
    ProviderConnectionId id,
    CredentialChange change,
  ) async {
    if (_reportingSaves.contains(id)) return;
    setState(() => _reportingSaves.add(id));
    try {
      try {
        if (change.updateLabelOnly) {
          await widget.credentialStore.writeLabel(id, change.label);
          return;
        }
        if (change.remove) {
          await widget.credentialStore.deleteSecret(id);
        } else {
          await widget.credentialStore.writeSecret(id, change.value!);
        }
      } catch (_) {
        if (change.remove) {
          // Retirement can succeed before label or retired-slot cleanup fails.
          // Reconcile through the normal load even if storage cannot confirm it.
          if (mounted) {
            _reportingUpdates.remove(id);
            _onCredentialsChanged();
          }
          bool? remains;
          try {
            remains = await widget.credentialStore.readSecret(id) != null;
          } catch (_) {
            // The normal reload will report an unreadable local credential.
          }
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  remains == false
                      ? 'Connection removed. Could not finish local cleanup.'
                      : 'Could not finish removing credential.',
                ),
              ),
            );
          return;
        }
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not update credential')),
          );
        return;
      }
      // App ownership survives disposal of the Providers tab and partial metadata
      // failure. Exactly this one normal reload checks the newly stored key.
      if (mounted) {
        _reportingUpdates.remove(id);
        _onCredentialsChanged();
      }
      if (!change.remove) {
        try {
          await widget.credentialStore.writeLabel(id, change.label);
        } catch (_) {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Key saved. Could not update label.'),
              ),
            );
        }
      }
    } finally {
      _reportingSaves.remove(id);
      if (mounted) setState(() {});
    }
  }

  void _onCredentialsChanged() {
    widget.repository.invalidate();
    if (_mode.synthetic) return;
    _loadRevision++;
    _surfaceRevision++;
    _acceptance = null;
    _reload(forCredentialChange: true);
  }

  /// Worst status each family is reporting, for the Providers order.
  ///
  /// Accounts only: that tab manages connections, so a plan meter crossing its
  /// own threshold is not what should pull a card to the top of it.
  Map<ProviderFamily, ProviderStatus> _providerStatuses(
    DashboardSnapshot? snapshot,
  ) {
    final byFamily = <ProviderFamily, List<ProviderStatus>>{};
    for (final account in snapshot?.accounts ?? const <ProviderSnapshot>[]) {
      if (providerFamilyOf(account.provider) case final family?) {
        byFamily.putIfAbsent(family, () => []).add(account.status);
      }
    }
    return {
      for (final entry in byFamily.entries)
        entry.key: worstProviderStatus(entry.value),
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DashboardSnapshot>(
      future: _snapshot,
      builder: (context, state) {
        // Credential changes retire visible data immediately while preserving
        // the active tab, its scroll position and any app-owned save operation.
        final acceptance = _acceptance;
        final data = acceptance?.snapshot;
        final acceptedRules = acceptance?.rules;
        final rulesCurrent = _hasCurrentRules(acceptance);
        // Samples carry no live reporting outcomes, even while loading.
        final snapshot =
            data == null || _mode.synthetic
                ? data
                : data.withReportingOutcomes(
                  {
                    for (final outcome in data.reportingOutcomes)
                      outcome.connection: outcome,
                    for (final update in _reportingUpdates.values)
                      if (update.outcome != null)
                        update.connection: update.outcome!,
                  }.values,
                );

        final reportingOutcomes = <ConnectionReportingOutcome>[
          if (!_mode.synthetic)
            for (final update in _reportingUpdates.values)
              if (update.outcome != null) update.outcome!,
        ];
        final modeLabel = switch (_mode) {
          DataMode.live => null,
          DataMode.demo => 'Demo data',
          DataMode.mock => 'Mock data',
        };
        final claudePlanPaused = _claudePlanPausedIn(_mode);
        // Providers manage live connections, so Demo readings stay off it.
        final liveSnapshot = _mode == DataMode.demo ? null : snapshot;

        return Scaffold(
          appBar: AppBar(
            leading: const Center(
              child: Image(
                image: AssetImage('assets/brand/wardpulse.png'),
                width: 32,
                height: 32,
                excludeFromSemantics: true,
              ),
            ),
            title: const Text('WardPulse'),
            actions: [
              if (modeLabel != null && _selectedIndex == _dashboardIndex)
                Center(child: Text(modeLabel)),
              if (snapshot != null)
                _AppBarProblems(
                  problems: dashboardProblems(snapshot, _dashboardOrder),
                  onReveal: _revealProblem,
                ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _reportingCheckActive ? null : _reload,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: SafeArea(
            child: switch (state.connectionState) {
              _ when _selectedIndex == _watchfaceIndex => WatchfaceScreen(
                key: const ValueKey('watchface'),
                onRefresh: _pullToRefresh,
                snapshot: snapshot,
                reportingOutcomes: reportingOutcomes,
                ringPreferences: _pendingRingPreferences ?? _ringPreferences,
                saving: _pendingRingPreferences != null,
                localCapsAvailable: rulesCurrent,
                claudePlanPaused: claudePlanPaused,
                onRingPreferencesChanged:
                    (update, {required ringId, required selected}) =>
                        _updateRingPreferences(
                          acceptance,
                          update,
                          ringId: ringId,
                          selected: selected,
                        ),
              ),
              _ when _selectedIndex == _widgetIndex => WidgetScreen(
                key: const ValueKey('widget'),
                onRefresh: _pullToRefresh,
                snapshot: snapshot,
                reportingOutcomes: reportingOutcomes,
                preferences: _pendingWidgetPreferences ?? _widgetPreferences,
                saving: _pendingWidgetPreferences != null,
                localCapsAvailable: rulesCurrent,
                onPreferencesChanged:
                    (update) => _updateWidgetPreferences(acceptance, update),
              ),
              _ when _selectedIndex == _providersIndex => ProvidersScreen(
                key: const ValueKey('providers'),
                onRefresh: _pullToRefresh,
                credentialStore: widget.credentialStore,
                codexAccountService: widget.codexAccountService,
                claudeAccountService: widget.claudeAccountService,
                claudePlanPaused: widget.claudePlanPaused,
                onCredentialsChanged: _onCredentialsChanged,
                onSaveReportingCredential: _saveReportingCredential,
                reportingUpdates: Map.unmodifiable(_reportingUpdates),
                isSnapshotCurrent: widget.repository.isSnapshotCurrent,
                savingConnections: Set.unmodifiable(_reportingSaves),
                mockDataEnabled: _mockDataEnabled,
                demoDataEnabled: _mode == DataMode.demo,
                editConnection: _editReportingConnection,
                revealConnection: _connectionReveal,
                onConnectionRevealed: (token) {
                  if (_connectionReveal?.token == token)
                    _connectionReveal = null;
                },
                onEditConnectionOpened: () => _editReportingConnection = null,
                alertThresholds: _alertThresholds,
                onAlertThresholdsChanged: _updateAlertThresholds,
                snapshot: liveSnapshot,
                alertContextRevision: _surfaceRevision,
                statuses: _providerStatuses(liveSnapshot),
              ),
              _ when _selectedIndex == _settingsIndex => SettingsScreen(
                key: const ValueKey('settings'),
                onRefresh: _pullToRefresh,
                snapshot: snapshot,
                refreshInterval: _refreshInterval,
                onRefreshIntervalChanged: _updateRefreshInterval,
                ringPreferences: rulesCurrent ? _ringPreferences : null,
                widgetPreferences: rulesCurrent ? _widgetPreferences : null,
                claudePlanPaused: claudePlanPaused,
                onSyncWatch: _onSettingsSyncWatch,
                onResumeWatch: widget.watchSyncService.resume,
                recoveryNotificationsEnabled: _recoveryNotificationsEnabled,
                onRecoveryNotificationsChanged: _updateRecoveryNotifications,
                alertNotificationsEnabled: _alertNotificationsEnabled,
                onAlertNotificationsChanged: _updateAlertNotifications,
                androidNotificationsEnabled: _androidNotificationsEnabled,
                onOpenNotificationSettings:
                    () async =>
                        await widget.notificationCoordinator
                            ?.openAndroidNotificationSettings(),
                debugDataAvailable: widget.debugDataAvailable,
                dataModeReady: _modeReady,
                demoDataEnabled: _mode == DataMode.demo,
                onDemoDataEnabledChanged: _updateDemoDataEnabled,
                mockDataEnabled: _mockDataEnabled,
                onMockDataEnabledChanged: _updateMockDataEnabled,
                accountStorageUnresolved: _accountStorageUnresolved,
              ),
              // Only the very first load has nothing to show; a reload keeps
              // the dashboard up rather than blanking it.
              ConnectionState.waiting when snapshot == null =>
                _rejectionNotices.any((notice) => !notice.dismissed)
                    ? SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          ConnectionFeedback(
                            notices: _rejectionNotices,
                            onRevealConnection: _revealConnection,
                            onDismiss: _dismissRejection,
                          ),
                          const SizedBox(height: 16),
                          const _LoadingView(),
                        ],
                      ),
                    )
                    : const _LoadingView(),
              _ when state.hasError => _ErrorView(
                failure: _dashboardFailure(state.error),
                onRetry: _reload,
                onOpenProviders: _openProviders,
                onEditReportingKey: _editReportingKey,
                rejectionNotices: _rejectionNotices,
                onRevealConnection: _revealConnection,
                onDismissRejection: _dismissRejection,
              ),
              _ when snapshot != null => DashboardScreen(
                onRefresh: _pullToRefresh,
                snapshot: snapshot,
                configuredBudgetPeriods:
                    acceptance?.operation.mode == DataMode.demo
                        ? _sampleBudgetPeriods(snapshot)
                        : acceptedRules == null
                        ? null
                        : {
                          for (final entry in acceptedRules.connections.entries)
                            entry.key: {
                              if ((entry.value.budget.today ?? 0) > 0) 'today',
                              if ((entry.value.budget.week ?? 0) > 0) 'week',
                              if ((entry.value.budget.month ?? 0) > 0) 'month',
                            },
                        },
                onOpenProviders: _openProviders,
                onEditReportingKey: _editReportingKey,
                rejectionNotices: _rejectionNotices,
                onRevealConnection: _revealConnection,
                onDismissRejection: _dismissRejection,
                reveal: _reveal,
                order: _dashboardOrder,
              ),
              _ => _ErrorView(
                failure: const DashboardLoadException(),
                onRetry: _reload,
                rejectionNotices: _rejectionNotices,
                onRevealConnection: _revealConnection,
                onDismissRejection: _dismissRejection,
              ),
            },
          ),
          bottomNavigationBar: LayoutBuilder(
            builder: (context, constraints) {
              const destinations = [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: 'Dashboard',
                ),
                NavigationDestination(
                  icon: Icon(Icons.watch_outlined),
                  selectedIcon: Icon(Icons.watch),
                  label: 'Watchface',
                ),
                NavigationDestination(
                  icon: Icon(Icons.widgets_outlined),
                  selectedIcon: Icon(Icons.widgets),
                  label: 'Widget',
                ),
                NavigationDestination(
                  icon: Icon(Icons.hub_outlined),
                  selectedIcon: Icon(Icons.hub),
                  label: 'Providers',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ];
              final theme = Theme.of(context);
              // Material uses labelMedium for both selection states, with
              // state colors supplied by NavigationBar itself.
              final labelStyle = theme.textTheme.labelMedium!;
              final measuredStyle =
                  MediaQuery.boldTextOf(context)
                      ? labelStyle.copyWith(fontWeight: FontWeight.bold)
                      : labelStyle;
              final labelWidth =
                  (constraints.maxWidth -
                      MediaQuery.paddingOf(context).horizontal) /
                  destinations.length;
              // Match NavigationDestination's existing scaling allowance.
              final textScaler = MediaQuery.textScalerOf(
                context,
              ).clamp(maxScaleFactor: 1.3);
              final painter = TextPainter(
                textDirection: Directionality.of(context),
                textScaler: textScaler,
                locale: Localizations.maybeLocaleOf(context),
              );
              bool fits(double fontSize) {
                for (final destination in destinations) {
                  painter
                    ..text = TextSpan(
                      text: destination.label,
                      style: measuredStyle.copyWith(fontSize: fontSize),
                    )
                    ..layout();
                  if (painter.width > labelWidth) return false;
                }
                return true;
              }

              var fontSize = labelStyle.fontSize!;
              if (!fits(fontSize)) {
                var lower = 0.0;
                var upper = fontSize;
                while (upper - lower > 0.01) {
                  final candidate = (lower + upper) / 2;
                  if (fits(candidate)) {
                    lower = candidate;
                  } else {
                    upper = candidate;
                  }
                }
                fontSize = lower;
              }
              painter.dispose();

              final navigationBar = NavigationBar(
                selectedIndex: _selectedIndex,
                onDestinationSelected: (index) {
                  final enteringSettings =
                      index == _settingsIndex && index != _selectedIndex;
                  setState(() {
                    _selectedIndex = index;
                    if (index != _providersIndex) _connectionReveal = null;
                  });
                  if (index == _dashboardIndex)
                    unawaited(_readRejectionNotices());
                  if (enteringSettings) {
                    unawaited(_refreshNotificationStatus());
                  }
                },
                destinations: destinations,
              );
              if (fontSize == labelStyle.fontSize) return navigationBar;
              return Theme(
                data: theme.copyWith(
                  textTheme: theme.textTheme.copyWith(
                    labelMedium: labelStyle.copyWith(
                      fontSize: fontSize,
                      // Keep the label row's height, hence the icon and
                      // indicator positions, unchanged when fitting the type.
                      height:
                          labelStyle.height! *
                          textScaler.scale(labelStyle.fontSize!) /
                          textScaler.scale(fontSize),
                    ),
                  ),
                ),
                child: navigationBar,
              );
            },
          ),
        );
      },
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.failure,
    required this.onRetry,
    this.onOpenProviders,
    this.onEditReportingKey,
    this.rejectionNotices = const [],
    this.onRevealConnection,
    this.onDismissRejection,
  });

  final DashboardLoadException failure;
  final VoidCallback onRetry;
  final VoidCallback? onOpenProviders;
  final void Function(ProviderConnectionId)? onEditReportingKey;
  final List<ConnectionRejectionNotice> rejectionNotices;
  final void Function(ProviderConnectionId)? onRevealConnection;
  final void Function(ConnectionRejectionNotice)? onDismissRejection;

  @override
  Widget build(BuildContext context) {
    if (failure.issue == DashboardSyncIssue.noProviders &&
        failure.reportingOutcomes.isEmpty &&
        rejectionNotices.every((notice) => notice.dismissed)) {
      return ConnectProviderPrompt(onOpenProviders: onOpenProviders);
    }

    final colors = Theme.of(context).colorScheme;
    final issueIcon = Icon(Icons.error_outline, color: colors.error, size: 36);
    final matchedRejection = rejectionNotices.any(
      (notice) => notice.matches(failure.syncRejection),
    );

    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!matchedRejection)
                Tooltip(message: failure.issue.message, child: issueIcon)
              else
                issueIcon,
              const SizedBox(height: 12),
              Text(
                'Dashboard unavailable',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ConnectionFeedback(
                outcomes: failure.reportingOutcomes,
                issue: failure.issue,
                details: failure.details,
                showIssueTooltip: false,
                rejection: failure.syncRejection,
                notices: rejectionNotices,
                onEditKey: onEditReportingKey,
                onRevealConnection: onRevealConnection,
                onDismiss: onDismissRejection,
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  if (failure.details != null)
                    TextButton.icon(
                      onPressed:
                          () => _showErrorDetails(context, failure.details!),
                      icon: const Icon(Icons.info_outline),
                      label: const Text('Details'),
                    ),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Demo has no live rules, so the sample's own limits set its budget periods.
Map<String, Set<String>> _sampleBudgetPeriods(DashboardSnapshot snapshot) => {
  for (final account in snapshot.accounts)
    if (account.connection case final connection?)
      connection: {
        for (final budget in [account.today, account.week, account.month])
          if (budget.limit != null) budget.period,
      },
};

DashboardLoadException _dashboardFailure(Object? error) {
  return error is DashboardLoadException
      ? error
      : const DashboardLoadException();
}

void _showErrorDetails(BuildContext context, String details) {
  showDialog<void>(
    context: context,
    builder:
        (context) => AlertDialog(
          title: const Text('Error details'),
          content: SelectableText(details),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
  );
}

/// The app bar's rollup: how many sections a tap can take the reader to, in the
/// worst of their colors. Silent when nothing below deviates.
class _AppBarProblems extends StatelessWidget {
  const _AppBarProblems({required this.problems, required this.onReveal});

  final DashboardProblems problems;
  final void Function(String provider) onReveal;

  @override
  Widget build(BuildContext context) {
    if (problems.first case final provider?) {
      final chip = providerStatusChipColors(
        Theme.of(context).colorScheme,
        problems.status,
      );
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 12),
        child: Tooltip(
          message: 'Go to ${problems.status.label.toLowerCase()}',
          child: InkResponse(
            onTap: () => onReveal(provider),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Badge(
                backgroundColor: chip.fill,
                textColor: chip.ink,
                label: Text('${problems.sections}'),
              ),
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
