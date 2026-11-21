import 'package:flutter_test/flutter_test.dart';
import 'package:queue_system/features/queue/data/sample_data_generator.dart';
import 'package:queue_system/features/queue/domain/entities/enums.dart';

import '../../helpers.dart';

void main() {
  test('generates exactly 1000 tickets, the same for the same seed', () {
    final a = generateSampleQueueData(count: 1000, seed: 7, now: now);
    final b = generateSampleQueueData(count: 1000, seed: 7, now: now);
    final c = generateSampleQueueData(count: 1000, seed: 8, now: now);
    expect(a.tickets, hasLength(1000));
    expect(a.tickets, b.tickets);
    expect(a.offices, b.offices);
    expect(a.tickets, isNot(c.tickets));
    expect(generateSampleQueueData(count: 50, now: now).tickets, hasLength(50));
  });

  test('works for any time after opening, never issues in the future', () {
    for (final (h, m) in [(9, 1), (10, 0), (11, 45), (16, 59)]) {
      final at = DateTime(2026, 11, 21, h, m);
      final data = generateSampleQueueData(now: at);
      expect(data.tickets, hasLength(1000), reason: '$h:$m');
      expect(
        data.tickets.every((t) => !t.issuedAt.isAfter(at)),
        isTrue,
        reason: '$h:$m',
      );
    }
    for (final (h, m) in [(9, 0), (8, 0)]) {
      expect(
        () => generateSampleQueueData(now: DateTime(2026, 11, 21, h, m)),
        throwsArgumentError,
      );
    }
  });

  test('loaded through the repository, the data is consistent', () async {
    final (db, repo) = await openRepo();
    addTearDown(db.close);
    final data = generateSampleQueueData(now: now);
    await loadSampleData(repo, data);

    expect(await repo.countTickets(), 1000);
    final offices = await repo.getOffices();
    expect(offices, hasLength(4));
    expect(offices.where((o) => !o.isOpen), hasLength(1));

    for (final o in offices) {
      final queue = await repo.getQueue(o.officeId, day);
      final waiting = queue.where((t) => t.status == TicketStatus.waiting);
      expect(o.waitingCount, waiting.length, reason: o.officeId);
      if (!o.isOpen) expect(waiting, isEmpty);

      // Positions run 1, 2, 3 ... in each service line, in number order.
      for (final service in ['A', 'B', 'C']) {
        final line = waiting.where((t) => t.serviceCode == service).toList();
        expect(
          [for (final t in line) t.position],
          [for (var i = 1; i <= line.length; i++) i],
          reason: '${o.officeId} $service',
        );
      }
      expect(
        queue
            .where((t) => t.status != TicketStatus.waiting)
            .every((t) => t.position == null),
        isTrue,
      );
    }

    final mine = await repo.getMyTickets(activeOnly: true);
    expect(mine, hasLength(1));
    final pos = (await repo.getMyPosition(mine.single.id))!;
    expect(pos.position, greaterThan(1));
    expect(pos.office.isOpen, isTrue);
  });
}
