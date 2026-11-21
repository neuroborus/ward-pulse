import 'package:ward_pulse_phone/dashboard/dashboard_models.dart';

final freshnessSuccessAt = DateTime.utc(2026, 11, 8, 9);

DashboardSnapshot freshnessSnapshot(
  List<ProviderSnapshot> accounts, {
  ProviderStatus overall = ProviderStatus.warning,
  DateTime? at,
}) => DashboardSnapshot.fromJson({
  ...DashboardSnapshot.empty().toJson(),
  'generatedAt': (at ?? freshnessSuccessAt).toIso8601String(),
  'overallStatus': overall.name,
  'accounts': [for (final account in accounts) account.toJson()],
});

ProviderSnapshot freshnessAccount(
  String provider,
  String connection, {
  ProviderStatus status = ProviderStatus.ok,
  List<AllowanceState> allowances = const [],
  DateTime? at,
}) => ProviderSnapshot.fromJson({
  'accountId': '$connection-account',
  'provider': provider,
  'connection': connection,
  'status': status.name,
  'lastSuccessfulSyncAt': (at ?? freshnessSuccessAt).toIso8601String(),
  'allowances': [for (final allowance in allowances) allowance.toJson()],
  'credits': <Object>[],
  'buckets': <Object>[],
  'modelBreakdown': <Object>[],
  for (final period in ['today', 'week', 'month'])
    period: {
      ...BudgetState.unknownPeriod(period).toJson(),
      'spent': {'minorUnits': 2500, 'currency': 'USD'},
      'limit': {'minorUnits': 10000, 'currency': 'USD'},
      'usedPercent': 25,
      'status': 'ok',
    },
});

AllowanceState freshnessAllowance(
  String id, {
  double? usedPercent = 40,
  String? remaining,
  String unit = 'credits',
  bool purchased = false,
  bool unlimited = false,
  ProviderStatus status = ProviderStatus.ok,
}) => AllowanceState.fromJson({
  'id': id,
  'label': id,
  'source': purchased ? 'purchased' : 'plan',
  'usedPercent': usedPercent,
  'remaining': remaining == null ? null : {'value': remaining, 'unit': unit},
  'unlimited': unlimited,
  'status': status.name,
});
