import 'package:flutter/material.dart';

import 'bookplate_dialog.dart';
import 'bookplate_plate.dart';

/// Pull down on a tab to fetch its data again, as on a web page. Flutter's
/// refresh gesture without its Material spinner: the shell's turning brass
/// arc shows at the top instead while the fetch runs.
///
/// Any vertical scroll view inside counts (the app's scroll behavior makes
/// even a short page pullable — see main.dart's _AppScrollBehavior).
class PullToRefresh extends StatefulWidget {
  const PullToRefresh({super.key, required this.onRefresh, required this.child});

  /// Throws if the fetch failed; the page keeps what it had and says so.
  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  State<PullToRefresh> createState() => _PullToRefreshState();
}

class _PullToRefreshState extends State<PullToRefresh> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } catch (error) {
      debugPrint('Pull to refresh failed: ${error.runtimeType}');
      if (mounted) showBookplateNotice(context, "Couldn't refresh. Check your connection.");
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator.noSpinner(
          onRefresh: _refresh,
          // Whichever vertical list the tab is built from, however deep.
          notificationPredicate: (notification) => notification.metrics.axis == Axis.vertical,
          child: widget.child,
        ),
        if (_refreshing)
          const Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(child: BookplateSpinner(size: 24, semanticLabel: 'Refreshing')),
            ),
          ),
      ],
    );
  }
}
