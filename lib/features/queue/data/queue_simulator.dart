import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../domain/entities/enums.dart';
import '../domain/entities/ticket.dart';
import '../domain/queue_repository.dart';
import 'row_mappers.dart';

/// Stands in for the server in the demo: it writes queue updates into local
/// storage, exactly as a real sync would. The dashboard never hears from the
/// simulator directly. It only sees the database change, which is how the
/// UI's reactivity is shown working.
class QueueSimulator {
  QueueSimulator(this._repo, {DateTime Function()? clock, Random? random})
    : _clock = clock ?? DateTime.now,
      _random = random ?? Random();

  final QueueRepository _repo;
  final DateTime Function() _clock;
  final Random _random;
  Timer? _timer;

  /// Whether [start] is advancing the queue on a timer.
  final running = ValueNotifier(false);

  void start({Duration every = const Duration(seconds: 3)}) {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => advance());
    running.value = true;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    running.value = false;
  }

  void dispose() {
    stop();
    running.dispose();
  }

  /// One step of the queue, as the server would report it:
  ///
  /// 1. The server accepts the user's pending changes (an offline ticket gets
  ///    the next number in its line; a cancellation is confirmed).
  /// 2. In the user's line (or Main Branch line A if they have no ticket),
  ///    the customer being served finishes, the called customer reaches the
  ///    counter, and the next waiting customer is called.
  Future<void> advance() async {
    final now = _clock();
    await _syncPending();

    final mine = await _repo.getMyTickets(activeOnly: true);
    final officeId = mine.isEmpty ? 'main' : mine.first.officeId;
    final service = mine.isEmpty ? 'A' : mine.first.serviceCode;
    final office = await _repo.getOfficeStatus(officeId);
    if (office == null || !office.isOpen) return;
    final day = RowMappers.date(now);

    final line = (await _repo.getQueue(
      officeId,
      day,
    )).where((t) => t.serviceCode == service).toList();
    final changed = <Ticket>[];
    for (final t in line.where((t) => t.status == TicketStatus.serving)) {
      changed.add(
        t.copyWith(
          status: TicketStatus.completed,
          completedAt: now,
          updatedAt: now,
        ),
      );
    }
    for (final t in line.where((t) => t.status == TicketStatus.called)) {
      changed.add(t.copyWith(status: TicketStatus.serving, updatedAt: now));
    }
    final next = line
        .where((t) => t.status == TicketStatus.waiting && t.number != null)
        .firstOrNull;
    if (next != null) {
      changed.add(
        next.copyWith(
          status: TicketStatus.called,
          calledAt: now,
          counter: 1 + _random.nextInt(max(1, office.countersOpen)),
          position: () => null,
          updatedAt: now,
        ),
      );
    }
    if (changed.isEmpty) return;

    final waitingAfter =
        (await _repo.getQueue(
          officeId,
          day,
          statuses: {TicketStatus.waiting},
        )).length -
        (next == null ? 0 : 1);
    await _repo.saveQueueUpdate(
      tickets: changed,
      offices: [
        office.copyWith(
          nowServing: next == null ? null : () => next.code,
          waitingCount: waitingAfter,
          updatedAt: now,
          syncedAt: now,
        ),
      ],
      now: now,
    );
  }

  Future<void> _syncPending() async {
    for (final t in await _repo.getPendingChanges()) {
      if (t.syncState == SyncState.pendingCreate) {
        final line = (await _repo.getQueue(
          t.officeId,
          t.serviceDate,
        )).where((x) => x.serviceCode == t.serviceCode);
        final last = line.map((x) => x.number ?? 0).fold(0, max);
        await _repo.markSynced(t.id, assignedNumber: last + 1);
      } else {
        await _repo.markSynced(t.id);
      }
    }
  }
}
