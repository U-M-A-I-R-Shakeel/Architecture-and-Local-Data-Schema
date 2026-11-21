import 'package:flutter/material.dart';

import '../../domain/entities/queue_position.dart';
import 'format.dart';

/// Estimated wait for the user's place in line.
///
/// Shows how the estimate is worked out and how fresh the data is, and
/// warns when the data may be out of date, instead of pretending it's live.
class WaitTimeCard extends StatelessWidget {
  const WaitTimeCard({super.key, required this.position, required this.stale});

  final QueuePosition position;

  /// The data behind [position] is older than the app trusts.
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = position;
    final wait = p.estimatedWait;
    final expected = p.asOf.add(wait);
    final counters = p.office.countersOpen < 1 ? 1 : p.office.countersOpen;
    final error = theme.colorScheme.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.schedule, size: 20),
                const SizedBox(width: 8),
                Text('Estimated wait', style: theme.textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                QueueFormat.wait(wait),
                key: ValueKey(wait.inMinutes),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (wait.inMinutes >= 1)
              Text(
                'Expected around ${QueueFormat.hhmm(expected)}',
                style: theme.textTheme.titleMedium,
              ),
            const SizedBox(height: 8),
            Text(
              '${p.peopleAhead} ahead × ${p.office.averageServiceMinutes} min '
              '÷ $counters ${counters == 1 ? 'counter' : 'counters'}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              key: const ValueKey('freshness'),
              children: [
                Icon(
                  stale ? Icons.warning_amber_rounded : Icons.check_circle,
                  size: 16,
                  color: stale ? error : Colors.green,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    stale
                        ? 'As of ${QueueFormat.hhmm(p.asOf)} · may be out of date'
                        : 'As of ${QueueFormat.hhmm(p.asOf)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: stale ? error : null,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
