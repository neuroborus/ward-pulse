import 'dart:async';

import 'package:flutter/material.dart';

import 'alert_threshold_preferences.dart';

/// Compact editor for an opt-in threshold in **remaining %** language.
///
/// Persists used% via [AlertPercentThreshold] for Rust evaluation.
class AlertPercentThresholdEditor extends StatefulWidget {
  const AlertPercentThresholdEditor({
    super.key,
    this.title,
    required this.value,
    required this.onChanged,
    this.disabledReason,
    this.usePlanDefault = false,
    this.onUsePlanDefault,
  });

  /// Heading above the control; omit when the caller already labels the group.
  final String? title;
  final AlertPercentThreshold value;
  final ValueChanged<AlertPercentThreshold> onChanged;

  /// Non-null greys out the control and says why the rule cannot fire.
  final String? disabledReason;
  final bool usePlanDefault;
  final VoidCallback? onUsePlanDefault;

  @override
  State<AlertPercentThresholdEditor> createState() =>
      AlertPercentThresholdEditorState();
}

class AlertPercentThresholdEditorState
    extends State<AlertPercentThresholdEditor> {
  static const _custom = -1;
  static const _planDefault = -2;
  final _fieldKey = GlobalKey<FormFieldState<String>>();
  final _focusNode = FocusNode();
  var _errorRevealScheduled = false;
  late final _controller = TextEditingController(
    text: alertUsedToRemaining(widget.value.at)?.toString() ?? '',
  );
  late bool _isCustom =
      !widget.usePlanDefault &&
      !alertRemainingStops.contains(alertUsedToRemaining(widget.value.at));

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Called after the owning form validates all fields, including offscreen ones.
  /// With [requestFocus] false, only an already-focused error is revealed.
  bool revealError({bool requestFocus = true}) {
    if (_fieldKey.currentState?.hasError != true ||
        (!requestFocus && !_focusNode.hasFocus)) {
      return false;
    }
    if (requestFocus) _focusNode.requestFocus();
    unawaited(_revealErrorAfterFrame());
    return true;
  }

  Future<void> _revealErrorAfterFrame() async {
    if (_errorRevealScheduled) return;
    _errorRevealScheduled = true;
    // Focus queues a caret-only scroll in a post-frame callback. Reveal the
    // complete field after those callbacks so the error stays visible too.
    await WidgetsBinding.instance.endOfFrame;
    _errorRevealScheduled = false;
    if (!mounted ||
        !_focusNode.hasFocus ||
        _fieldKey.currentState?.hasError != true) {
      return;
    }
    await Scrollable.ensureVisible(
      _fieldKey.currentContext!,
      alignment: 0.5,
      duration: const Duration(milliseconds: 150),
    );
  }

  int? _parse(String text) {
    if (!RegExp(r'^[0-9]+$').hasMatch(text)) return null;
    final value = int.tryParse(text);
    return value != null && value <= 100 ? value : null;
  }

  @override
  Widget build(BuildContext context) {
    final remaining = alertUsedToRemaining(widget.value.at);
    final enabled = widget.disabledReason == null;
    final selection =
        widget.usePlanDefault
            ? _planDefault
            : (_isCustom ? _custom : remaining);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.title != null) ...[
          Text(widget.title!, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
        ],
        Semantics(
          label: '${widget.title ?? 'Alert'} threshold',
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Alert when',
              border: const OutlineInputBorder(),
              isDense: true,
              enabled: enabled,
              helperText: widget.disabledReason,
              helperMaxLines: 8,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                isExpanded: true,
                value: selection,
                itemHeight: null,
                items: [
                  if (widget.onUsePlanDefault != null)
                    const DropdownMenuItem<int?>(
                      value: _planDefault,
                      child: Text('Use Plan default'),
                    ),
                  for (final stop in alertRemainingStops)
                    DropdownMenuItem<int?>(
                      value: stop,
                      child: Text(stop == null ? 'Off' : '$stop% left'),
                    ),
                  const DropdownMenuItem<int?>(
                    value: _custom,
                    child: Text('Custom % left'),
                  ),
                ],
                onChanged:
                    enabled
                        ? (next) {
                          _focusNode.unfocus();
                          setState(() => _isCustom = next == _custom);
                          if (next == _planDefault) {
                            widget.onUsePlanDefault!();
                          } else if (next == _custom) {
                            // Entering custom mode is explicit enabled intent.
                            // Invalid text stays in the draft and blocks Save.
                            final parsed = _parse(_controller.text);
                            widget.onChanged(
                              AlertPercentThreshold(
                                at: alertRemainingToUsed(parsed ?? 0),
                              ),
                            );
                          } else {
                            _controller.text = next?.toString() ?? '';
                            widget.onChanged(
                              AlertPercentThreshold(
                                at: alertRemainingToUsed(next),
                              ),
                            );
                          }
                        }
                        : null,
              ),
            ),
          ),
        ),
        if (_isCustom && !widget.usePlanDefault) ...[
          const SizedBox(height: 12),
          Semantics(
            label: '${widget.title ?? 'Alert'} remaining percentage',
            child: TextFormField(
              key: _fieldKey,
              controller: _controller,
              focusNode: _focusNode,
              enabled: enabled,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: '% left',
                border: const OutlineInputBorder(),
                helperText: 'Whole number from 0 to 100',
                helperMaxLines: 4,
                errorMaxLines: 4,
              ),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator:
                  (text) =>
                      !enabled || _parse(text ?? '') != null
                          ? null
                          : 'Enter a whole number from 0 to 100',
              onChanged: (text) {
                final parsed = _parse(text);
                if (parsed != null) {
                  widget.onChanged(
                    AlertPercentThreshold(at: alertRemainingToUsed(parsed)),
                  );
                }
              },
            ),
          ),
        ],
      ],
    );
  }
}
