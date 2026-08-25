import 'package:flutter/material.dart';

/// Edits one pasted provider secret, with an optional display label.
///
/// Pops a [CredentialChange], or null when dismissed.
class CredentialDialog extends StatefulWidget {
  const CredentialDialog({
    super.key,
    required this.hasCredential,
    required this.title,
    required this.hint,
    required this.allowLabel,
    this.initialLabel,
  });

  final bool hasCredential;
  final String title;
  final String hint;
  final bool allowLabel;
  final String? initialLabel;

  @override
  State<CredentialDialog> createState() => _CredentialDialogState();
}

class _CredentialDialogState extends State<CredentialDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  late final TextEditingController _labelController;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.initialLabel ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    _labelController.dispose();
    super.dispose();
  }

  void _save() {
    final key = _controller.text.trim();
    final label = _labelController.text.trim();
    final resolvedLabel = label.isEmpty ? null : label;
    if (key.isEmpty) {
      if (!widget.hasCredential) {
        _formKey.currentState?.validate();
        return;
      }
      if (widget.allowLabel) {
        Navigator.of(context).pop(CredentialChange.labelOnly(resolvedLabel));
      } else {
        // Leave blank to keep the stored token; dismiss without a mutation.
        Navigator.of(context).pop();
      }
      return;
    }
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(context).pop(
        CredentialChange.save(
          key,
          label: widget.allowLabel ? resolvedLabel : null,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.allowLabel
                  ? 'This key is encrypted on this phone and sent only to the provider.'
                  : 'This token is encrypted on this phone. Experimental compatibility connection.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _controller,
              autofocus: true,
              obscureText: _obscureKey,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText:
                    widget.hasCredential
                        ? 'Value (leave blank to keep)'
                        : 'Value',
                hintText: widget.hint,
                suffixIcon: IconButton(
                  tooltip: _obscureKey ? 'Show value' : 'Hide value',
                  onPressed: () {
                    setState(() {
                      _obscureKey = !_obscureKey;
                    });
                  },
                  icon: Icon(
                    _obscureKey
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              textInputAction:
                  widget.allowLabel
                      ? TextInputAction.next
                      : TextInputAction.done,
              onFieldSubmitted: widget.allowLabel ? null : (_) => _save(),
              validator: (value) {
                if (widget.hasCredential) {
                  return null;
                }
                return value == null || value.trim().isEmpty
                    ? 'Enter a value'
                    : null;
              },
            ),
            if (widget.allowLabel) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _labelController,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Label (optional)',
                  hintText: 'Work org key',
                ),
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _save(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.hasCredential)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(const CredentialChange.remove());
            },
            child: const Text('Remove'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// What [CredentialDialog] was asked to do with the secret.
final class CredentialChange {
  const CredentialChange.save(this.value, {this.label})
    : remove = false,
      updateLabelOnly = false;

  const CredentialChange.labelOnly(this.label)
    : value = null,
      remove = false,
      updateLabelOnly = true;

  const CredentialChange.remove()
    : value = null,
      label = null,
      remove = true,
      updateLabelOnly = false;

  final String? value;
  final String? label;
  final bool remove;
  final bool updateLabelOnly;
}
