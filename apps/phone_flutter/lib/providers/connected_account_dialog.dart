import 'package:flutter/material.dart';

/// Confirms what to do with an already connected provider account.
class ConnectedAccountDialog extends StatelessWidget {
  const ConnectedAccountDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Reconnect',
  });

  final String title;
  final String message;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(AccountAction.disconnect),
          child: const Text('Disconnect'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(AccountAction.reconnect),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

enum AccountAction { reconnect, disconnect }
