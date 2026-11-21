import 'package:flutter/material.dart';

import '../../domain/entities/office_status.dart';

/// One office's latest known status.
class OfficeStatusTile extends StatelessWidget {
  const OfficeStatusTile({super.key, required this.office});

  final OfficeStatus office;

  @override
  Widget build(BuildContext context) {
    final o = office;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        title: Text(o.name),
        subtitle: Text(
          o.isOpen
              ? 'Now serving ${o.nowServing ?? '—'} · ${o.waitingCount} waiting · '
                    '${o.countersOpen} counters'
              : 'Closed · open ${o.opensAt}–${o.closesAt}',
        ),
        trailing: Chip(
          label: Text(o.isOpen ? 'Open' : 'Closed'),
          backgroundColor: o.isOpen
              ? scheme.tertiaryContainer
              : scheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}
