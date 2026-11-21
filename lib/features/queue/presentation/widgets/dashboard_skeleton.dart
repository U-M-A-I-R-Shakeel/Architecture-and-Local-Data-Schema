import 'package:flutter/material.dart';

/// Placeholder shaped like the dashboard, gently pulsing, shown while local
/// data is read or prepared. The layout doesn't jump when data arrives.
class DashboardSkeleton extends StatefulWidget {
  const DashboardSkeleton({super.key, this.message});

  /// Optional line under the placeholders, e.g. "Preparing offline data…".
  final String? message;

  @override
  State<DashboardSkeleton> createState() => _DashboardSkeletonState();
}

class _DashboardSkeletonState extends State<DashboardSkeleton>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget box(double height, {double? width}) => Container(
      height: height,
      width: width,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
    );
    return Semantics(
      label: 'Loading your queue',
      liveRegion: true,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // First, so it is visible on the smallest screens.
          if (widget.message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.message!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          FadeTransition(
            opacity: Tween(begin: 0.45, end: 1.0).animate(_pulse),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                box(48),
                box(220),
                box(150),
                box(20, width: 120),
                box(64),
                box(64),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
