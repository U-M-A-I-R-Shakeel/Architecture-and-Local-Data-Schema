import 'package:flutter/material.dart';

import '../domain/entities/office_status.dart';
import '../domain/entities/queue_position.dart';
import '../domain/entities/ticket.dart';
import '../domain/queue_repository.dart';

/// Shows the user's ticket, place in line and every office's status, all
/// read from local storage through [repository]. Works with no internet.
class QueueHomeScreen extends StatefulWidget {
  const QueueHomeScreen({
    super.key,
    required this.repository,
    this.clock = DateTime.now,
  });

  final QueueRepository repository;
  final DateTime Function() clock;

  @override
  State<QueueHomeScreen> createState() => _QueueHomeScreenState();
}

typedef _Data = ({
  Ticket? ticket,
  QueuePosition? position,
  List<OfficeStatus> offices,
});

class _QueueHomeScreenState extends State<QueueHomeScreen> {
  late Future<_Data> _data = _load();

  Future<_Data> _load() async {
    final mine = await widget.repository.getMyTickets(activeOnly: true);
    final ticket = mine.isEmpty ? null : mine.first;
    return (
      ticket: ticket,
      position: ticket == null
          ? null
          : await widget.repository.getMyPosition(ticket.id),
      offices: await widget.repository.getOffices(),
    );
  }

  Future<void> _refresh() async {
    setState(() => _data = _load());
    await _data;
  }

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('My Queue')),
      body: FutureBuilder<_Data>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text('Could not read local data.\n${snap.error}'),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snap.data!;
          final officeName = {for (final o in d.offices) o.officeId: o.name};
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off_outlined),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Works offline: everything here is read from '
                          'this phone\'s storage.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (d.ticket == null)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('You have no ticket.'),
                    ),
                  )
                else
                  _TicketCard(
                    ticket: d.ticket!,
                    officeName:
                        officeName[d.ticket!.officeId] ?? d.ticket!.officeId,
                    position: d.position,
                    stale: d.position?.isStale(widget.clock()) ?? false,
                    hhmm: _hhmm,
                  ),
                const SizedBox(height: 24),
                Text('Offices', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final o in d.offices) _OfficeTile(office: o, hhmm: _hhmm),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({
    required this.ticket,
    required this.officeName,
    required this.position,
    required this.stale,
    required this.hhmm,
  });

  final Ticket ticket;
  final String officeName;
  final QueuePosition? position;
  final bool stale;
  final String Function(DateTime) hhmm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = position;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your ticket', style: theme.textTheme.labelLarge),
            Text(
              ticket.code,
              key: const ValueKey('my-ticket-code'),
              style: theme.textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            Text(officeName, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (p != null) ...[
              Text(
                'Position ${p.position} · ${p.peopleAhead} ahead · '
                '~${p.estimatedWait.inMinutes} min',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                stale
                    ? 'As of ${hhmm(p.asOf)} · may be out of date'
                    : 'As of ${hhmm(p.asOf)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: stale ? theme.colorScheme.error : null,
                ),
              ),
            ] else
              Text('Status: ${ticket.status.name}'),
          ],
        ),
      ),
    );
  }
}

class _OfficeTile extends StatelessWidget {
  const _OfficeTile({required this.office, required this.hhmm});

  final OfficeStatus office;
  final String Function(DateTime) hhmm;

  @override
  Widget build(BuildContext context) {
    final o = office;
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
              ? Colors.green.shade50
              : Colors.grey.shade200,
        ),
      ),
    );
  }
}
