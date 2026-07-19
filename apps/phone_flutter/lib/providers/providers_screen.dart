import 'package:flutter/material.dart';

import '../dashboard/dashboard_models.dart';
import '../dashboard/dashboard_screen.dart';
import 'provider_detail_screen.dart';

class ProvidersScreen extends StatelessWidget {
  const ProvidersScreen({super.key, required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    if (snapshot.accounts.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No providers'),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: snapshot.accounts.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final account = snapshot.accounts[index];

        return Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            leading: const Icon(Icons.hub),
            title: Text(account.providerLabel),
            subtitle: Text(account.accountId),
            trailing: StatusPill(
              status: account.status,
              tooltip: snapshot.syncIssue?.message,
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder:
                      (context) => ProviderDetailScreen(
                        account: account,
                        syncIssue: snapshot.syncIssue,
                      ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
