import 'package:flutter/material.dart';

import '../../domain/entities/office_status.dart';
import 'format.dart';

/// Shown when the user has no active ticket: says so plainly and offers the
/// next step. If no office data has ever been saved, it says that instead.
class EmptyQueueView extends StatelessWidget {
  const EmptyQueueView({
    super.key,
    required this.offices,
    required this.onTakeTicket,
  });

  final List<OfficeStatus> offices;

  /// Called with the chosen office and service code.
  final Future<void> Function(String officeId, String serviceCode) onTakeTicket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noData = offices.isEmpty;
    final anyOpen = offices.any((o) => o.isOpen);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            Icon(
              noData
                  ? Icons.cloud_download_outlined
                  : Icons.confirmation_number,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              noData ? 'No office data yet' : "You're not in a queue",
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              noData
                  ? 'Connect to the internet once to download offices. '
                        'After that, the app works offline.'
                  : anyOpen
                  ? 'Take a ticket and your place in line will show here, '
                        'even without internet.'
                  : 'All offices are closed right now.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (anyOpen) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const ValueKey('take-ticket'),
                onPressed: () => _chooseService(context),
                icon: const Icon(Icons.add),
                label: const Text('Take a ticket'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _chooseService(BuildContext context) => showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(
            'Choose an office and service',
            style: Theme.of(sheet).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final o in offices.where((o) => o.isOpen))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(o.name),
              subtitle: Wrap(
                spacing: 8,
                children: [
                  for (final MapEntry(key: code, value: name)
                      in QueueFormat.serviceNames.entries)
                    ActionChip(
                      key: ValueKey('service-${o.officeId}-$code'),
                      label: Text('$code · $name'),
                      onPressed: () {
                        Navigator.pop(sheet);
                        onTakeTicket(o.officeId, code);
                      },
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
