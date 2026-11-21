import 'package:flutter/material.dart';

import '../../domain/entities/enums.dart';
import '../../domain/entities/office_status.dart';
import '../../domain/entities/queue_position.dart';
import '../../domain/entities/ticket.dart';
import 'format.dart';

/// The user's ticket and place in line.
///
/// Shows what matters for each stage: the position while waiting (animating
/// when it changes), "go to counter N" once called, and "being served" at
/// the counter. A ticket taken offline is marked as waiting to sync.
class QueuePositionCard extends StatelessWidget {
  const QueuePositionCard({
    super.key,
    required this.ticket,
    required this.office,
    required this.position,
  });

  final Ticket ticket;
  final OfficeStatus? office;
  final QueuePosition? position;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final called = ticket.status == TicketStatus.called;
    return Card(
      color: called ? scheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Your ticket', style: theme.textTheme.labelLarge),
                ),
                if (ticket.syncState != SyncState.synced)
                  _SyncChip(ticket.syncState),
              ],
            ),
            Text(
              ticket.code,
              key: const ValueKey('my-ticket-code'),
              style: theme.textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: scheme.primary,
              ),
            ),
            Text(
              '${office?.name ?? ticket.officeId} · '
              '${QueueFormat.service(ticket.serviceCode)}',
              style: theme.textTheme.titleMedium,
            ),
            const Divider(height: 32),
            switch (ticket.status) {
              TicketStatus.waiting when position != null => _Waiting(
                position: position!,
              ),
              TicketStatus.waiting => const _Message(
                icon: Icons.hourglass_top,
                title: 'Working out your place in line…',
              ),
              TicketStatus.called => _Message(
                icon: Icons.campaign_outlined,
                title: "It's your turn",
                subtitle: ticket.counter == null
                    ? 'Please go to the counter'
                    : 'Please go to counter ${ticket.counter}',
                emphasis: true,
              ),
              TicketStatus.serving => _Message(
                icon: Icons.support_agent,
                title: 'Being served',
                subtitle: ticket.counter == null
                    ? null
                    : 'At counter ${ticket.counter}',
              ),
              _ => _Message(
                icon: Icons.info_outline,
                title: 'Status: ${ticket.status.name}',
              ),
            },
          ],
        ),
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.position});
  final QueuePosition position;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nowServing = position.office.nowServing;
    return Semantics(
      label:
          'Position ${position.position} in line, '
          '${QueueFormat.ahead(position.peopleAhead)}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _AnimatedNumber(
                key: const ValueKey('queue-position'),
                value: position.position,
                style: theme.textTheme.displayLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('in line', style: theme.textTheme.labelLarge),
                    Text(
                      QueueFormat.ahead(position.peopleAhead),
                      key: const ValueKey('people-ahead'),
                      style: theme.textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (nowServing != null) ...[
            const SizedBox(height: 12),
            Text('Now serving $nowServing', style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// A number that slides and fades to its new value when it changes.
class _AnimatedNumber extends StatelessWidget {
  const _AnimatedNumber({super.key, required this.value, this.style});
  final int value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 300),
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.4),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    ),
    child: Text('$value', key: ValueKey(value), style: style),
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.subtitle,
    this.emphasis = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: emphasis ? 40 : 28),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: emphasis
                    ? theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      )
                    : theme.textTheme.titleMedium,
              ),
              if (subtitle != null)
                Text(subtitle!, style: theme.textTheme.titleMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _SyncChip extends StatelessWidget {
  const _SyncChip(this.state);
  final SyncState state;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: const Icon(Icons.cloud_upload_outlined, size: 18),
    label: Text(
      state == SyncState.pendingCreate ? 'Waiting to sync' : 'Cancel pending',
    ),
    visualDensity: VisualDensity.compact,
  );
}
