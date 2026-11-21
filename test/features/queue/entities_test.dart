import 'package:flutter_test/flutter_test.dart';
import 'package:queue_system/features/queue/domain/entities/enums.dart';
import 'package:queue_system/features/queue/domain/entities/queue_position.dart';

import '../../helpers.dart';

void main() {
  test('ticket code is service + 3-digit number, or … before a number', () {
    expect(ticket(7).code, 'A-007');
    expect(ticket(147, service: 'B').code, 'B-147');
    expect(
      ticket(7).copyWith(number: null).code,
      'A-007',
      reason: 'copyWith keeps the number when not given',
    );
  });

  test('active statuses', () {
    expect(TicketStatus.values.where((s) => s.isActive), [
      TicketStatus.waiting,
      TicketStatus.called,
      TicketStatus.serving,
    ]);
    expect(TicketStatus.fromDb('no_show'), TicketStatus.noShow);
    expect(SyncState.fromDb('pending_cancel'), SyncState.pendingCancel);
  });

  test('estimated wait = people ahead × average ÷ counters, rounded up', () {
    QueuePosition pos(int position, {int counters = 2, int avg = 6}) =>
        QueuePosition(
          ticket: ticket(1),
          office: office('main', counters: counters, avg: avg),
          position: position,
          asOf: now,
        );
    expect(pos(1).peopleAhead, 0);
    expect(pos(1).estimatedWait, Duration.zero);
    expect(pos(21, counters: 4).estimatedWait, const Duration(minutes: 30));
    expect(
      pos(4, counters: 2, avg: 5).estimatedWait,
      const Duration(minutes: 8),
    );
    expect(
      pos(3, counters: 0, avg: 5).estimatedWait,
      const Duration(minutes: 10),
      reason: 'no counters open counts as one',
    );
  });

  test('a position older than 5 minutes is stale', () {
    final p = QueuePosition(
      ticket: ticket(1),
      office: office('main'),
      position: 3,
      asOf: now,
    );
    expect(p.isStale(now.add(const Duration(minutes: 5))), isFalse);
    expect(p.isStale(now.add(const Duration(minutes: 6))), isTrue);
  });
}
