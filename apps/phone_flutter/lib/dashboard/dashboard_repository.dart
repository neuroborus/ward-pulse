import 'package:flutter/services.dart';

import 'dashboard_models.dart';

abstract class DashboardRepository {
  const DashboardRepository();

  Future<DashboardSnapshot> load();
}

class AssetDashboardRepository extends DashboardRepository {
  const AssetDashboardRepository({
    this.assetPath = 'assets/mock/dashboard_today.json',
  });

  final String assetPath;

  @override
  Future<DashboardSnapshot> load() async {
    final source = await rootBundle.loadString(assetPath);
    return DashboardSnapshot.fromJsonString(source);
  }
}

class ValueDashboardRepository extends DashboardRepository {
  const ValueDashboardRepository(this.snapshot);

  final DashboardSnapshot snapshot;

  @override
  Future<DashboardSnapshot> load() async => snapshot;
}
