import 'package:flutter/material.dart';

import '../data/queue_simulator.dart';
import '../domain/entities/office_status.dart';
import '../domain/queue_repository.dart';
import 'dashboard_controller.dart';
import 'dashboard_state.dart';
import 'widgets/dashboard_skeleton.dart';
import 'widgets/empty_queue_view.dart';
import 'widgets/office_status_tile.dart';
import 'widgets/queue_position_card.dart';
import 'widgets/wait_time_card.dart';

/// The main dashboard: the user's ticket, place in line, estimated wait and
/// every office's status, all from local storage.
///
/// It rebuilds whenever [controller] reports a new state, which happens the
/// moment local data changes. It has no data of its own and never reloads
/// itself after an action.
class QueueDashboardScreen extends StatelessWidget {
  const QueueDashboardScreen({
    super.key,
    required this.controller,
    this.simulator,
  });

  final DashboardController controller;

  /// Demo only: buttons that make the queue move, to show live updates.
  final QueueSimulator? simulator;

  @override
  Widget build(BuildContext context) {
    final sim = simulator;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Queue'),
        actions: [
          if (sim != null) ...[
            ValueListenableBuilder(
              valueListenable: sim.running,
              builder: (context, running, _) => IconButton(
                key: const ValueKey('live-demo'),
                tooltip: running ? 'Stop live demo' : 'Start live demo',
                icon: Icon(running ? Icons.pause_circle : Icons.play_circle),
                onPressed: running ? sim.stop : sim.start,
              ),
            ),
            IconButton(
              key: const ValueKey('next-customer'),
              tooltip: 'Next customer (demo)',
              icon: const Icon(Icons.skip_next),
              onPressed: sim.advance,
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final state = controller.state;
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              // Keyed by kind of state, so it cross-fades between loading,
              // empty and ready, but updates within a state in place.
              child: KeyedSubtree(
                key: ValueKey(state.runtimeType),
                child: switch (state) {
                  DashboardLoading() => const DashboardSkeleton(
                    message: 'Preparing your offline queue…',
                  ),
                  DashboardError(:final message) => _ErrorView(
                    message: message,
                    onRetry: controller.refresh,
                  ),
                  DashboardEmpty(:final offices) => _Body(
                    onRefresh: controller.refresh,
                    children: [
                      EmptyQueueView(
                        offices: offices,
                        onTakeTicket: (office, service) => _run(
                          context,
                          () => controller.takeTicket(office, service),
                        ),
                      ),
                      ..._offices(context, offices),
                    ],
                  ),
                  DashboardReady() => _Body(
                    onRefresh: controller.refresh,
                    children: [
                      _TicketSection(state: state),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          key: const ValueKey('cancel-ticket'),
                          onPressed: () => _confirmCancel(context),
                          icon: const Icon(Icons.close),
                          label: const Text('Cancel ticket'),
                        ),
                      ),
                      ..._offices(context, state.offices),
                    ],
                  ),
                },
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _offices(BuildContext context, List<OfficeStatus> offices) => [
    if (offices.isNotEmpty) ...[
      const SizedBox(height: 16),
      Text('Offices', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      for (final o in offices) OfficeStatusTile(office: o),
    ],
  ];

  Future<void> _confirmCancel(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Cancel your ticket?'),
        content: const Text('You will lose your place in line.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            key: const ValueKey('confirm-cancel'),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Cancel ticket'),
          ),
        ],
      ),
    );
    if (yes == true && context.mounted) {
      await _run(context, controller.cancelTicket);
    }
  }

  /// Runs an action. The screen updates through the change stream; only a
  /// failure needs handling here.
  static Future<void> _run(
    BuildContext context,
    Future<Object?> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on QueueException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// Scrollable, pull-to-refresh column, centred and width-limited on tablets.
class _Body extends StatelessWidget {
  const _Body({required this.onRefresh, required this.children});

  final Future<void> Function() onRefresh;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [const _OfflineBanner(), ...children],
            ),
          ),
        ),
      ],
    ),
  );
}

/// The two custom widgets, side by side when there is room.
class _TicketSection extends StatelessWidget {
  const _TicketSection({required this.state});
  final DashboardReady state;

  @override
  Widget build(BuildContext context) {
    final positionCard = QueuePositionCard(
      ticket: state.ticket,
      office: state.office,
      position: state.position,
    );
    final p = state.position;
    if (p == null) return positionCard;
    final waitCard = WaitTimeCard(position: p, stale: state.isStale);
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= 600
          ? IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 3, child: positionCard),
                  Expanded(flex: 2, child: waitCard),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [positionCard, waitCard],
            ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
              'Works offline: everything here is read from this phone\'s '
              'storage and updates as soon as it changes.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}
