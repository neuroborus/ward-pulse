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
import '../settings/debug_data_preferences.dart';
import '../settings/recovery_notification_preferences.dart';
import '../settings/refresh_interval_preferences.dart';
import '../settings/watch_ring_preferences.dart';
import '../sync/alert_notifications.dart';
import '../sync/automatic_poll.dart';
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
    this.refreshIntervalStore = const DefaultRefreshIntervalPreferenceStore(),
    this.watchRingPreferenceStore = const DefaultWatchRingPreferenceStore(),
    this.phoneWidgetPreferenceStore = const DefaultPhoneWidgetPreferenceStore(),
    this.alertThresholdStore = const DefaultAlertThresholdPreferenceStore(),
    this.applyAlertSettings = applyUserAlertSettings,
    this.syncScheduler = const DisabledProviderSyncScheduler(),
    this.scheduleHeadlessSync = HeadlessProviderSync.schedule,
    this.debugDataAvailable = false,
    this.debugDataPreferenceStore = const DisabledDebugDataPreferenceStore(),
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
  final RefreshIntervalPreferenceStore refreshIntervalStore;
  final WatchRingPreferenceStore watchRingPreferenceStore;
  final PhoneWidgetPreferenceStore phoneWidgetPreferenceStore;
  final AlertThresholdPreferenceStore alertThresholdStore;
  final ApplyAlertSettings applyAlertSettings;
  final ProviderSyncScheduler syncScheduler;
  final Future<void> Function(Duration) scheduleHeadlessSync;
  final bool debugDataAvailable;
  final DebugDataPreferenceStore debugDataPreferenceStore;
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
        refreshIntervalStore: refreshIntervalStore,
        watchRingPreferenceStore: watchRingPreferenceStore,
        phoneWidgetPreferenceStore: phoneWidgetPreferenceStore,
        alertThresholdStore: alertThresholdStore,
        applyAlertSettings: applyAlertSettings,
        syncScheduler: syncScheduler,
        scheduleHeadlessSync: scheduleHeadlessSync,
        debugDataAvailable: debugDataAvailable,
        debugDataPreferenceStore: debugDataPreferenceStore,
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
    required this.refreshIntervalStore,
    required this.watchRingPreferenceStore,
    required this.phoneWidgetPreferenceStore,
    required this.alertThresholdStore,
    required this.applyAlertSettings,
    required this.syncScheduler,
    required this.scheduleHeadlessSync,
    required this.debugDataAvailable,
    required this.debugDataPreferenceStore,
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
  final RefreshIntervalPreferenceStore refreshIntervalStore;
  final WatchRingPreferenceStore watchRingPreferenceStore;
  final PhoneWidgetPreferenceStore phoneWidgetPreferenceStore;
  final AlertThresholdPreferenceStore alertThresholdStore;
  final ApplyAlertSettings applyAlertSettings;
  final ProviderSyncScheduler syncScheduler;
  final Future<void> Function(Duration) scheduleHeadlessSync;
  final bool debugDataAvailable;
  final DebugDataPreferenceStore debugDataPreferenceStore;
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
    required this.observationRevision,
    required this.input,
    required this.snapshot,
    required this.rules,
    required this.ruleGeneration,
    required this.surfaceRevision,
    required this.poll,
  });

  // Rule edits replace the acceptance while retaining the provider observation.
  final int observationRevision;
  final DashboardSnapshot input;
  final DashboardSnapshot snapshot;
  final AlertThresholdPreferences? rules;
  final int ruleGeneration;
  final int surfaceRevision;
  final AutomaticPollContext? poll;
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
  late Future<DashboardSnapshot> _snapshot = _loadSnapshot(automatic: true);
  _SnapshotAcceptance? _acceptance;
  final _reportingUpdates = <ProviderConnectionId, ConnectionReportingUpdate>{};
  ProviderConnectionId? _editReportingConnection;
  ({ProviderConnectionId connection, int token})? _connectionReveal;
  var _connectionRevealToken = 0;
  var _noticeRevision = 0;
  List<ConnectionRejectionNotice> _rejectionNotices = const [];

  Future<void> _readRejectionNotices() async {
    final revision = ++_noticeRevision;
    try {
      final notices = await widget.rejectionNotices.read();
      if (mounted && revision == _noticeRevision)
        setState(() => _rejectionNotices = notices);
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
  var _widgetPublicationRevision = 0;
  WatchRingPreferences? _pendingRingPreferences;
  PhoneWidgetPreferences? _pendingWidgetPreferences;
  Future<void> _ringPreferenceWork = Future<void>.value();
  Future<void> _widgetPreferenceWork = Future<void>.value();
  var _ringPreferenceRevision = 0;
  var _widgetPreferenceRevision = 0;
  AlertThresholdPreferences? _alertThresholds;
  var _ruleGeneration = 0;
  Future<void> _snapshotSettingsWork = Future<void>.value();
  bool _mockDataEnabled = false;
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_readRejectionNotices());
    _initializeNotifications();
    _queueNotificationFrame();
    _syncTicks = widget.syncScheduler.ticks.listen((_) {
      unawaited(_onScheduledSync());
    });
    widget.watchSyncService.bindWatchRefreshListener(_onWatchRefreshRequested);
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
    if (state == AppLifecycleState.resumed) unawaited(_readRejectionNotices());
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

  /// Later of snapshot time and the last accepted Wear refresh tap.
  DateTime _manualRefreshAnchorAt(DashboardSnapshot snapshot) {
    final wearAnchor = _wearRefreshAnchorAt;
    if (wearAnchor == null || !wearAnchor.isAfter(snapshot.generatedAt)) {
      return snapshot.generatedAt;
    }
    return wearAnchor;
  }

  void _onWatchRefreshRequested() {
    if (!mounted) {
      return;
    }
    final acceptance = _acceptance;
    if (acceptance == null) {
      // Load in flight / failed — reload; a later empty snapshot clears Wear.
      _reload();
      return;
    }
    final window = ManualRefreshWindow.fromLastSync(
      lastSyncAt: _manualRefreshAnchorAt(acceptance.snapshot),
    );
    if (!window.allowed) {
      // Re-push flags so Wear chrome matches the phone floor without a wasted sync.
      unawaited(_syncWatch(acceptance));
      return;
    }
    _wearRefreshAnchorAt = DateTime.now().toUtc();
    // Push disabled chrome immediately; the reload will push again with fresh data.
    unawaited(_syncWatch(acceptance));
    _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  Future<void> _readDebugDataPreference(int revision) async {
    var enabled = false;
    if (widget.debugDataAvailable) {
      try {
        enabled = await widget.debugDataPreferenceStore.readMockDataEnabled();
      } catch (_) {
        // Unavailable debug preferences leave live data enabled.
      }
    }
    if (mounted && revision == _loadRevision) {
      _mockDataEnabled = enabled;
    }
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
      try {
        await store.write(value);
      } catch (_) {
        if (mounted && revision == _ringPreferenceRevision) {
          setState(() => _pendingRingPreferences = null);
        }
        rethrow;
      }
      if (!mounted) return;
      setState(() {
        _ringPreferences = value;
        _watchPublicationPending = true;
        if (revision == _ringPreferenceRevision) _pendingRingPreferences = null;
      });
      final acceptance = _acceptance;
      if (acceptance != null) unawaited(_syncWatch(acceptance));
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
      try {
        await store.write(value);
      } catch (_) {
        if (mounted && revision == _widgetPreferenceRevision) {
          setState(() => _pendingWidgetPreferences = null);
        }
        rethrow;
      }
      if (!mounted) return;
      setState(() {
        _widgetPreferences = value;
        _widgetPublicationPending = true;
        if (revision == _widgetPreferenceRevision)
          _pendingWidgetPreferences = null;
      });
      final acceptance = _acceptance;
      if (acceptance != null) unawaited(_syncPhoneWidget(acceptance));
    });
    _widgetPreferenceWork = work.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return work;
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
    // store ahead of in-memory prefs / dashboard alerts.
    final withAlerts =
        previous == null
            ? null
            : widget.applyAlertSettings(previous.input, value);
    await widget.alertThresholdStore.write(value);
    if (!mounted) return;
    _confirmAlertThresholds(value);
    if (previous == null || withAlerts == null) return;
    try {
      if (!await widget.repository.isSnapshotCurrent(withAlerts)) return;
    } catch (_) {
      // The write is saved even if ownership cannot be confirmed.
      return;
    }
    // A new load request may retain this accepted input as its owned fallback.
    if (!mounted ||
        surfaceRevision != _surfaceRevision ||
        !identical(previous, _acceptance)) {
      return;
    }
    final acceptance = _SnapshotAcceptance(
      observationRevision: previous.observationRevision,
      input: previous.input,
      snapshot: withAlerts,
      rules: _alertThresholds,
      ruleGeneration: _ruleGeneration,
      surfaceRevision: surfaceRevision,
      poll: previous.poll,
    );
    setState(() => _acceptance = acceptance);
    unawaited(_syncWatch(acceptance));
    unawaited(_syncPhoneWidget(acceptance));
    unawaited(_syncAlerts(acceptance));
  });

  Future<_SnapshotAcceptance> _acceptSnapshot(
    DashboardSnapshot repositorySnapshot,
    int revision,
    AutomaticPollContext? poll,
  ) => _serializeSnapshotSettings(() async {
    if (!mounted || revision != _loadRevision) {
      throw const DashboardLoadException(details: 'Refresh superseded.');
    }
    final rules = _alertThresholds;
    final snapshot =
        rules == null
            ? repositorySnapshot
            : widget.applyAlertSettings(repositorySnapshot, rules);
    final current = await widget.repository.isSnapshotCurrent(snapshot);
    if (!mounted || revision != _loadRevision || !current) {
      throw const DashboardLoadException(
        details: 'Connection changed during refresh.',
      );
    }
    final acceptance = _SnapshotAcceptance(
      observationRevision: revision,
      input: repositorySnapshot,
      snapshot: snapshot,
      rules: rules,
      ruleGeneration: _ruleGeneration,
      surfaceRevision: _surfaceRevision,
      poll: poll,
    );
    setState(() {
      _acceptance = acceptance;
      // Either surface may have to wait while a newer load takes over.
      if (poll?.whollySkipped != true) {
        _watchPublicationPending = true;
        _widgetPublicationPending = true;
      }
    });
    return acceptance;
  });

  Future<DashboardSnapshot> _loadSnapshot({bool automatic = false}) {
    final load = _loadForegroundSnapshot(automatic: automatic);
    // FutureBuilder subscribes on the next build. Observe classified failures
    // immediately while preserving the original future for its error UI.
    unawaited(
      load.then<void>((_) {}).onError<DashboardLoadException>((_, _) {}),
    );
    return load;
  }

  AutomaticPollContext _automaticPoll() => AutomaticPollContext(
    readInterval:
        () async => (await widget.refreshIntervalStore.read()).interval,
  );

  Future<DashboardSnapshot> _loadForegroundSnapshot({
    bool automatic = false,
  }) async {
    final revision = ++_loadRevision;
    final poll = automatic ? _automaticPoll() : null;
    _invalidateNotificationEligibility();
    try {
      await _readRefreshInterval();
      await _readRingPreferences();
      await _readWidgetPreferences();
      await _serializeSnapshotSettings(_readAlertThresholds);
      await _readDebugDataPreference(revision);
      await _readNotificationPreferences(revision);
      // Keep both schedulers registered; native admission enforces spacing
      // across their starts. Headless WorkManager uses ≥15 minutes.
      unawaited(_scheduleAutoSync(_refreshInterval.interval));
      final repositorySnapshot =
          await (poll == null
              ? _observedLoad(revision)
              : poll.run(() => _observedLoad(revision)));
      final acceptance = await _acceptSnapshot(
        repositorySnapshot,
        revision,
        poll,
      );
      unawaited(_syncRecoveries(acceptance));
      if (_watchPublicationPending) {
        unawaited(_syncWatch(acceptance));
      }
      if (_widgetPublicationPending) {
        unawaited(_syncPhoneWidget(acceptance));
      }
      if (poll?.whollySkipped != true) unawaited(_syncAlerts(acceptance));
      return acceptance.snapshot;
    } catch (_) {
      // A failed foreground load leaves an error-only Dashboard. Successful
      // fallback loads return normally and retain their usable data.
      if (mounted && revision == _loadRevision) {
        _acceptance = null;
      }
      rethrow;
    } finally {
      await _readRejectionNotices();
    }
  }

  Future<DashboardSnapshot> _observedLoad(int revision) async {
    final poll = AutomaticPollContext.current;
    if (!mounted || revision != _loadRevision) {
      throw const DashboardLoadException(details: 'Refresh superseded.');
    }
    // A superseded request cannot leave a row spinning without active work.
    _reportingUpdates.removeWhere((_, update) => update.checking);
    final observed = <ProviderConnectionId>{};
    void forgetObserved() {
      if (mounted && revision == _loadRevision) {
        setState(() {
          for (final id in observed) {
            _reportingUpdates.remove(id);
          }
        });
      }
    }

    try {
      final snapshot = await widget.repository.loadObserved((update) {
        if (!mounted || revision != _loadRevision) return;
        observed.add(update.connection);
        setState(() => _reportingUpdates[update.connection] = update);
      });
      if (!await widget.repository.isSnapshotCurrent(snapshot) ||
          !mounted ||
          revision != _loadRevision) {
        forgetObserved();
        throw const DashboardLoadException(
          details: 'Connection changed during refresh.',
        );
      }
      setState(() {
        // A completed, current load is authoritative, including omissions for
        // removed connections. Its outcomes retain the current sibling facts.
        _reportingUpdates.removeWhere((id, update) {
          final stamp = snapshot.connectionVersions[id.storageKey];
          return poll?.observes(id.storageKey) != false ||
              stamp == null ||
              update.credentialVersion?.sameCache(CredentialVersion(stamp)) !=
                  true;
        });
        for (final outcome in snapshot.reportingOutcomes) {
          _reportingUpdates[outcome.connection] = ConnectionReportingUpdate(
            connection: outcome.connection,
            credentialVersion: outcome.credentialVersion,
            outcome: outcome,
          );
        }
      });
      return snapshot;
    } on DashboardLoadException catch (failure) {
      if (!await widget.repository.isFailureCurrent(failure) ||
          !mounted ||
          revision != _loadRevision) {
        forgetObserved();
        throw const DashboardLoadException(
          details: 'Connection changed during refresh.',
        );
      }
      setState(() {
        _reportingUpdates.clear();
        for (final outcome in failure.reportingOutcomes) {
          _reportingUpdates[outcome.connection] = ConnectionReportingUpdate(
            connection: outcome.connection,
            credentialVersion: outcome.credentialVersion,
            outcome: outcome,
          );
        }
      });
      rethrow;
    } catch (_) {
      forgetObserved();
      throw const DashboardLoadException();
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
      acceptance.ruleGeneration == _ruleGeneration &&
      _isAccepted(acceptance);

  Future<void> _syncRecoveries(_SnapshotAcceptance acceptance) async {
    final snapshot = acceptance.snapshot;
    bool observesCurrentInput() =>
        mounted &&
        acceptance.surfaceRevision == _surfaceRevision &&
        acceptance.observationRevision == _acceptance?.observationRevision;
    Future<bool> isCurrent() async =>
        observesCurrentInput() &&
        await widget.repository.isSnapshotCurrent(snapshot) &&
        observesCurrentInput();
    try {
      var notifications = false;
      try {
        notifications = await widget.recoveryNotificationStore.read();
      } catch (_) {
        // Preference failure mutes posting, not tracking or wake scheduling.
      }
      if (!await isCurrent()) return;
      await syncPlanRecoveries(
        snapshot,
        widget.recoveryWatchlistStore,
        widget.recoveryNotifier,
        widget.recoveryWake,
        mockData: _mockDataEnabled,
        notifications: notifications && _recoveryNotificationsEnabled,
        readRecoveries: widget.readPlanRecoveries,
        readWindows: widget.readExhaustedWindows,
        poll: acceptance.poll,
        isCurrent: isCurrent,
      );
    } catch (_) {
      // Recovery bookkeeping cannot publish retired data or block the dashboard.
    }
  }

  Future<void> _syncAlerts(_SnapshotAcceptance acceptance) async {
    final snapshot = acceptance.snapshot;
    bool accepted() => _hasCurrentRules(acceptance) && !_mockDataEnabled;
    if (!accepted()) return;
    await AlertNotificationDelivery(
      preferences: widget.alertNotificationStore,
      conditions: widget.alertConditionStore,
      notifier: widget.alertNotifier,
    ).sync(
      snapshot,
      poll: acceptance.poll,
      mockData: _mockDataEnabled,
      isAccepted: accepted,
      alertThresholds: acceptance.rules,
      isDeliveryEnabled: () => _alertNotificationsEnabled,
      isCurrent: () async {
        if (!accepted()) return false;
        final current = await widget.repository.isSnapshotCurrent(snapshot);
        return current && accepted();
      },
    );
  }

  Future<void> _scheduleAutoSync(Duration interval) async {
    await widget.syncScheduler.schedule(interval);
    await widget.scheduleHeadlessSync(interval);
  }

  Future<void> _onScheduledSync() async {
    if (_autoSyncInFlight || !mounted || _reportingCheckActive) {
      return;
    }
    _autoSyncInFlight = true;
    final revision = ++_loadRevision;
    final poll = _automaticPoll();
    try {
      if (_ringPreferences == null) await _readRingPreferences();
      if (_widgetPreferences == null) await _readWidgetPreferences();
      if (_alertThresholds == null) {
        await _serializeSnapshotSettings(() async {
          if (_alertThresholds == null) await _readAlertThresholds();
        });
      }
      // Do not invalidate: load() already refetches, and clearing caches would
      // drop stale-with-issue recovery on a failed automatic tick.
      final repositorySnapshot = await poll.run(() => _observedLoad(revision));
      final acceptance = await _acceptSnapshot(
        repositorySnapshot,
        revision,
        poll,
      );
      if (mounted && revision == _loadRevision) {
        setState(() {
          _snapshot = Future.value(acceptance.snapshot);
        });
      }
      if (_watchPublicationPending) {
        await _syncWatch(acceptance);
      }
      if (_widgetPublicationPending) {
        await _syncPhoneWidget(acceptance);
      }
      await _syncRecoveries(acceptance);
      if (!poll.whollySkipped) await _syncAlerts(acceptance);
    } on DashboardLoadException catch (failure) {
      // Keep successful data, but an error-only dashboard must follow the most
      // recent guarded result rather than the exception from its first load.
      try {
        final previous = _acceptance?.snapshot;
        if (previous != null &&
            await widget.repository.isSnapshotCurrent(previous))
          return;
        if (await widget.repository.isFailureCurrent(failure) &&
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
    }
  }

  Future<void> _updateMockDataEnabled(
    bool value,
  ) => _serializeSnapshotSettings(() async {
    final revision = ++_loadRevision;
    final surfaceRevision = ++_surfaceRevision;
    try {
      await widget.repository.clearPersistentSnapshots();
      await widget.debugDataPreferenceStore.writeMockDataEnabled(value);
    } catch (_) {
      final previous = _acceptance;
      var owned = false;
      try {
        owned =
            previous != null &&
            await widget.repository.isSnapshotCurrent(previous.input);
      } catch (_) {
        // Unavailable ownership cannot restore reader-visible data.
      }
      if (mounted &&
          revision == _loadRevision &&
          surfaceRevision == _surfaceRevision) {
        setState(() {
          if (owned && previous != null) {
            _acceptance = _SnapshotAcceptance(
              observationRevision: previous.observationRevision,
              input: previous.input,
              snapshot: previous.snapshot,
              rules: previous.rules,
              ruleGeneration: previous.ruleGeneration,
              surfaceRevision: surfaceRevision,
              poll: previous.poll,
            );
            _snapshot = Future.value(previous.snapshot);
          } else {
            _acceptance = null;
            final failed = Future<DashboardSnapshot>.error(
              const DashboardLoadException(),
            );
            failed.ignore();
            _snapshot = failed;
          }
        });
      }
      rethrow;
    }
    if (!mounted) {
      return;
    }
    // A completed mode write is authoritative even if a refresh started during
    // it. Retire that refresh and reload with current credentials and mode.
    _surfaceRevision++;
    widget.repository.invalidate();
    setState(() {
      _acceptance = null;
      _mockDataEnabled = value;
      _snapshot = _loadSnapshot();
    });
  });

  Future<void> _syncWatch(_SnapshotAcceptance acceptance) async {
    if (!_isAccepted(acceptance)) return;
    _watchPublicationPending = true;
    try {
      await _queueWatchSummary(acceptance);
    } catch (_) {
      // Watch availability must not block the phone dashboard.
    }
  }

  Future<void> _syncPhoneWidget(_SnapshotAcceptance acceptance) async {
    if (!_isAccepted(acceptance)) return;
    _widgetPublicationPending = true;
    final publicationRevision = ++_widgetPublicationRevision;
    final preferences = _widgetPreferences;
    if (preferences == null) return;
    final snapshot = acceptance.snapshot;
    bool accepted() =>
        publicationRevision == _widgetPublicationRevision &&
        _hasCurrentRules(acceptance) &&
        identical(preferences, _widgetPreferences);
    Future<bool> isCurrent() async =>
        accepted() &&
        await widget.repository.isSnapshotCurrent(snapshot) &&
        accepted();
    try {
      if (!await isCurrent() || !accepted()) return;
      var dispatchAllowed = false;
      await widget.phoneWidgetSyncService.sync(
        snapshot,
        preferences,
        isCurrent: () async => dispatchAllowed = await isCurrent(),
      );
      if (dispatchAllowed && accepted()) _widgetPublicationPending = false;
    } catch (_) {
      // Launcher widget updates must not block the phone dashboard.
      developer.log(
        'Dashboard refresh could not update the widget.',
        name: phoneWidgetLogName,
      );
    }
  }

  Future<bool> _queueWatchSummary(_SnapshotAcceptance acceptance) async {
    final preferences = _ringPreferences;
    if (preferences == null) return false;
    final snapshot = acceptance.snapshot;
    bool accepted() =>
        _hasCurrentRules(acceptance) &&
        identical(preferences, _ringPreferences);
    if (!accepted() ||
        !await widget.repository.isSnapshotCurrent(snapshot) ||
        !accepted()) {
      return false;
    }
    await widget.watchSyncService.sync(
      snapshot,
      preferences,
      manualRefreshAnchorAt: _manualRefreshAnchorAt(snapshot),
      mockDataMode: _mockDataEnabled,
    );
    if (accepted()) _watchPublicationPending = false;
    return true;
  }

  Future<void> _onSettingsSyncWatch() async {
    final acceptance = _acceptance;
    if (acceptance == null || !await _queueWatchSummary(acceptance)) {
      throw StateError('Watch sync unavailable');
    }
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

  void _reload({bool forCredentialChange = false}) {
    if (!forCredentialChange && _reportingCheckActive) return;
    // Mock demo is cached across auto-sync; refresh should draw a new seed.
    // Live repos must not clear connection recovery caches on every refresh.
    if (_mockDataEnabled) {
      widget.repository.invalidate();
    }
    setState(() {
      _snapshot = _loadSnapshot();
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
    _loadRevision++;
    _surfaceRevision++;
    _acceptance = null;
    widget.repository.invalidate();
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
        final snapshot =
            data == null || _mockDataEnabled
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
          if (!_mockDataEnabled)
            for (final update in _reportingUpdates.values)
              if (update.outcome != null) update.outcome!,
        ];

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
                onCredentialsChanged: _onCredentialsChanged,
                onSaveReportingCredential: _saveReportingCredential,
                reportingUpdates: Map.unmodifiable(_reportingUpdates),
                isSnapshotCurrent: widget.repository.isSnapshotCurrent,
                savingConnections: Set.unmodifiable(_reportingSaves),
                mockDataEnabled: _mockDataEnabled,
                editConnection: _editReportingConnection,
                revealConnection: _connectionReveal,
                onConnectionRevealed: (token) {
                  if (_connectionReveal?.token == token)
                    _connectionReveal = null;
                },
                onEditConnectionOpened: () => _editReportingConnection = null,
                alertThresholds: _alertThresholds,
                onAlertThresholdsChanged: _updateAlertThresholds,
                snapshot: snapshot,
                alertContextRevision: _surfaceRevision,
                statuses: _providerStatuses(snapshot),
              ),
              _ when _selectedIndex == _settingsIndex => SettingsScreen(
                key: const ValueKey('settings'),
                onRefresh: _pullToRefresh,
                snapshot: snapshot,
                refreshInterval: _refreshInterval,
                onRefreshIntervalChanged: _updateRefreshInterval,
                ringPreferences: rulesCurrent ? _ringPreferences : null,
                widgetPreferences: rulesCurrent ? _widgetPreferences : null,
                onSyncWatch: _onSettingsSyncWatch,
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
                mockDataEnabled: _mockDataEnabled,
                onMockDataEnabledChanged: _updateMockDataEnabled,
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
                    acceptedRules == null
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
