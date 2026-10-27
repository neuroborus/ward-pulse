import 'package:flutter/material.dart';

import '../dashboard/dashboard_models.dart';
import '../settings/alert_percent_threshold_editor.dart';
import '../settings/alert_threshold_preferences.dart';
import 'provider_connection.dart';

/// Edits the alert rules of one connection.
///
/// Which rules apply depends on what the connection reports: a subscription
/// plan exposes usage windows, an organization key exposes spend. Pops the
/// edited thresholds, or null when dismissed.
class ConnectionAlertsDialog extends StatefulWidget {
  const ConnectionAlertsDialog({
    super.key,
    required this.connectionTitle,
    required this.connection,
    required this.thresholds,
    this.planWindows = const [],
  });

  final String connectionTitle;
  final ProviderConnectionId connection;
  final ConnectionAlertThresholds thresholds;
  final List<AllowanceState> planWindows;

  @override
  State<ConnectionAlertsDialog> createState() => _ConnectionAlertsDialogState();
}

class _ConnectionAlertsDialogState extends State<ConnectionAlertsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _editorKeys = <String, GlobalKey<AlertPercentThresholdEditorState>>{};
  final _knownWindows = <String, AllowanceState>{};
  double? _viewportExtent;
  late var _draft = widget.thresholds;

  @override
  void initState() {
    super.initState();
    _rememberWindows();
  }

  @override
  void didUpdateWidget(ConnectionAlertsDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rememberWindows();
  }

  void _rememberWindows() {
    for (final window in widget.planWindows) {
      if (window.source == AllowanceSource.plan) {
        _knownWindows[window.id] = window;
      }
    }
  }

  GlobalKey<AlertPercentThresholdEditorState> _key(String id) =>
      _editorKeys.putIfAbsent(
        '${widget.connection.storageKey}/$id',
        () => GlobalKey<AlertPercentThresholdEditorState>(),
      );

  bool _handleScrollMetrics(ScrollMetricsNotification notification) {
    if (notification.depth == 0 &&
        notification.metrics.axis == Axis.vertical &&
        notification.metrics.viewportDimension != _viewportExtent) {
      _viewportExtent = notification.metrics.viewportDimension;
      // Keyboard insets animate the dialog viewport after focus is requested.
      // Keep its focused error visible without taking focus from another control.
      for (final key in _editorKeys.values) {
        if (key.currentState?.revealError(requestFocus: false) == true) break;
      }
    }
    return false;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      for (final key in _editorKeys.values) {
        if (key.currentState?.revealError() == true) break;
      }
      return;
    }
    Navigator.of(context).pop(_draft);
  }

  @override
  Widget build(BuildContext context) {
    final isPlan = widget.connection.kind == ConnectionKind.plan;
    return Form(
      key: _formKey,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: _handleScrollMetrics,
        child: _ConnectionDialog(
          title: 'Alerts · ${widget.connectionTitle}',
          intro:
              isPlan
                  ? 'Opt-in · alert at the chosen % left. Windows without an '
                      'override use Plan. Changing Plan keeps window overrides.'
                  : 'Opt-in · fire when this connection’s remaining budget reaches '
                      'the chosen % left. Other providers do not count.',
          onSave: _save,
          editors: isPlan ? _planEditors() : _budgetEditors(),
        ),
      ),
    );
  }

  List<Widget> _planEditors() {
    return [
      AlertPercentThresholdEditor(
        key: _key('plan'),
        title: 'Plan',
        value: _draft.plan,
        onChanged:
            (plan) => setState(() => _draft = _draft.copyWith(plan: plan)),
      ),
      for (final id in {..._knownWindows.keys, ..._draft.planWindows.keys})
        _windowEditor(id),
      AlertPercentThresholdEditor(
        key: _key('purchased'),
        title: 'Purchased',
        value: _draft.purchased,
        onChanged:
            (purchased) =>
                setState(() => _draft = _draft.copyWith(purchased: purchased)),
      ),
    ];
  }

  Widget _windowEditor(String id) {
    final window = _knownWindows[id];
    final available = widget.planWindows.any(
      (value) => value.source == AllowanceSource.plan && value.id == id,
    );
    final label = window?.label ?? 'Plan window';
    final duplicate =
        _knownWindows.values.where((value) => value.label == label).length > 1;
    // Normalized IDs are identity, never labels, durations or reset times.
    final safeId = id.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ');
    final title = window == null || duplicate ? '$label · $safeId' : label;
    return Column(
      key: ValueKey((widget.connection.storageKey, id, AllowanceSource.plan)),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          available
              ? 'Plan window'
              : 'Unavailable window · not reported in the current snapshot.',
        ),
        const SizedBox(height: 8),
        AlertPercentThresholdEditor(
          key: _key('plan/$id'),
          title: title,
          value: _draft.planWindows[id] ?? _draft.plan,
          usePlanDefault: !_draft.planWindows.containsKey(id),
          onUsePlanDefault: () {
            final windows = {..._draft.planWindows}..remove(id);
            setState(() => _draft = _draft.copyWith(planWindows: windows));
          },
          onChanged: (value) {
            final windows = {..._draft.planWindows, id: value};
            setState(() => _draft = _draft.copyWith(planWindows: windows));
          },
        ),
      ],
    );
  }

  List<Widget> _budgetEditors() {
    return [
      for (final period in _BudgetPeriod.values)
        AlertPercentThresholdEditor(
          key: _key(period.name),
          title: period.label,
          value: period.thresholdOf(_draft),
          // The limit comes first: without it there is no percentage to alert on.
          disabledReason:
              period.limitOf(_draft.budget) == null
                  ? 'Set this period’s limit under Budget limits'
                  : null,
          onChanged:
              (value) =>
                  setState(() => _draft = period.withThreshold(_draft, value)),
        ),
    ];
  }
}

/// Edits the [ConnectionBudget] of one connection.
///
/// Pops the edited budget, or null when dismissed.
class ConnectionBudgetDialog extends StatefulWidget {
  const ConnectionBudgetDialog({
    super.key,
    required this.connectionTitle,
    required this.budget,
  });

  final String connectionTitle;
  final ConnectionBudget budget;

  @override
  State<ConnectionBudgetDialog> createState() => _ConnectionBudgetDialogState();
}

class _ConnectionBudgetDialogState extends State<ConnectionBudgetDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _limits = {
    for (final period in _BudgetPeriod.values)
      period: TextEditingController(
        text: _amountText(period.limitOf(widget.budget)),
      ),
  };

  @override
  void dispose() {
    for (final controller in _limits.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: _ConnectionDialog(
        title: 'Budget · ${widget.connectionTitle}',
        intro:
            'Your own ceiling on this connection’s spend — providers report the '
            'spend, never the limit. Empty means no limit.',
        onSave: _save,
        editors: [
          for (final period in _BudgetPeriod.values)
            TextFormField(
              controller: _limits[period],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: period.label,
                border: const OutlineInputBorder(),
                isDense: true,
                errorMaxLines: 2,
              ),
              validator: (text) => _parseBudgetAmount(text ?? '').error,
            ),
        ],
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    var budget = widget.budget;
    for (final period in _BudgetPeriod.values) {
      budget = period.withLimit(
        budget,
        _parseBudgetAmount(_limits[period]!.text).minorUnits,
      );
    }
    Navigator.of(context).pop(budget);
  }
}

/// Budget periods in the order the dialog shows them.
enum _BudgetPeriod {
  today('Today'),
  week('Week'),
  month('Month');

  const _BudgetPeriod(this.label);

  final String label;

  AlertPercentThreshold thresholdOf(ConnectionAlertThresholds rules) =>
      switch (this) {
        _BudgetPeriod.today => rules.today,
        _BudgetPeriod.week => rules.week,
        _BudgetPeriod.month => rules.month,
      };

  int? limitOf(ConnectionBudget budget) => switch (this) {
    _BudgetPeriod.today => budget.today,
    _BudgetPeriod.week => budget.week,
    _BudgetPeriod.month => budget.month,
  };

  ConnectionAlertThresholds withThreshold(
    ConnectionAlertThresholds rules,
    AlertPercentThreshold value,
  ) => switch (this) {
    _BudgetPeriod.today => rules.copyWith(today: value),
    _BudgetPeriod.week => rules.copyWith(week: value),
    _BudgetPeriod.month => rules.copyWith(month: value),
  };

  ConnectionBudget withLimit(ConnectionBudget budget, int? minorUnits) =>
      switch (this) {
        _BudgetPeriod.today => ConnectionBudget(
          today: minorUnits,
          week: budget.week,
          month: budget.month,
        ),
        _BudgetPeriod.week => ConnectionBudget(
          today: budget.today,
          week: minorUnits,
          month: budget.month,
        ),
        _BudgetPeriod.month => ConnectionBudget(
          today: budget.today,
          week: budget.week,
          month: minorUnits,
        ),
      };
}

/// Minor units are the storage unit; the field takes major units.
String _amountText(int? minorUnits) =>
    minorUnits == null
        ? ''
        : '${minorUnits ~/ 100}.${(minorUnits % 100).toString().padLeft(2, '0')}';

final _decimalAmount = RegExp(r'^(?:[0-9]+(?:\.[0-9]{0,2})?|\.[0-9]{1,2})$');
// Money crosses the Rust boundary as signed 64-bit minor units.
final _maximumBudgetMinorUnits = BigInt.parse('9223372036854775807');

({int? minorUnits, String? error}) _parseBudgetAmount(String text) {
  final amount = text.trim().replaceAll(',', '.');
  if (amount.isEmpty) {
    return (minorUnits: null, error: null);
  }
  if (!_decimalAmount.hasMatch(amount)) {
    return (
      minorUnits: null,
      error: 'Enter a positive amount with up to 2 decimal places',
    );
  }
  final parts = amount.split('.');
  final whole = BigInt.parse(parts.first.isEmpty ? '0' : parts.first);
  final fraction = parts.length == 1 ? '00' : parts.last.padRight(2, '0');
  final minorUnits = whole * BigInt.from(100) + BigInt.parse(fraction);
  if (minorUnits < BigInt.one) {
    return (minorUnits: null, error: 'Enter at least 0.01');
  }
  if (minorUnits > _maximumBudgetMinorUnits) {
    return (minorUnits: null, error: 'Amount is too large');
  }
  return (minorUnits: minorUnits.toInt(), error: null);
}

/// Shell both dialogs use: intro copy, spaced editors, Cancel/Save.
class _ConnectionDialog extends StatelessWidget {
  const _ConnectionDialog({
    required this.title,
    required this.intro,
    required this.editors,
    required this.onSave,
  });

  final String title;
  final String intro;
  final List<Widget> editors;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            intro,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          for (final editor in editors) ...[const SizedBox(height: 16), editor],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: onSave, child: const Text('Save')),
      ],
    );
  }
}
