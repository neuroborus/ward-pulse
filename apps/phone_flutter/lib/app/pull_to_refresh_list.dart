import 'package:flutter/material.dart';

/// A tab list whose pull opens room at the top and spins in it.
///
/// Material's `RefreshIndicator` floats its spinner over the first rows, which
/// reads as an overlay landing on the content. Here the list is pushed down by
/// exactly the height the spinner needs while the reload runs, so the spinner
/// turns in a gap of its own and no row is covered.
///
/// The gesture keeps Android's own physics on purpose: a sliver refresh control
/// opens its gap out of overscroll, which needs bouncing physics, and then a
/// hard flick back to the top arms a reload nobody asked for.
class PullToRefreshList extends StatefulWidget {
  const PullToRefreshList({
    super.key,
    required this.onRefresh,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
  });

  /// Runs the reload; the gap stays open until this completes.
  final Future<void> Function() onRefresh;

  final List<Widget> children;
  final EdgeInsets padding;

  @override
  State<PullToRefreshList> createState() => _PullToRefreshListState();
}

class _PullToRefreshListState extends State<PullToRefreshList> {
  /// Tall enough for the spinner and its shadow, short enough that the first
  /// row stays in sight while it turns.
  static const _gap = 64.0;

  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      // Turns in the middle of the gap the list opens under it.
      displacement: _gap / 2,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(top: _refreshing ? _gap : 0),
        child: ListView(
          // A tab that fits its viewport still has to answer the gesture.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: widget.padding,
          children: widget.children,
        ),
      ),
    );
  }
}
