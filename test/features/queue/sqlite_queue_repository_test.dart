import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:queue_system/features/queue/data/sqlite_queue_repository.dart';
import 'package:queue_system/features/queue/domain/entities/enums.dart';
import 'package:queue_system/features/queue/domain/entities/ticket.dart';
import 'package:queue_system/features/queue/domain/queue_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers.dart';

void main() {
  late Database db;
  late SqliteQueueRepository repo;

  setUp(() async {
    (db, repo) = await openRepo();
    addTearDown(db.close);
    await repo.saveOfficeStatuses([office('main'), office('north')]);
  });

  Future<Map<String, int?>> positions() async => {
    for (final t in await repo.getQueue('main', day)) t.code: t.position,
  };

  test('office status is saved, updated and read back', () async {
    expect((await repo.getOffices()).map((o) => o.officeId), ['main', 'north']);
    await repo.saveTickets([ticket(1)]);
    await repo.saveOfficeStatuses([
      office('main').copyWith(isOpen: false, nowServing: () => 'A-001'),
    ]);
    final main = (await repo.getOfficeStatus('main'))!;
    expect(main.isOpen, isFalse);
    expect(main.nowServing, 'A-001');
    expect(
      await repo.countTickets(),
      1,
      reason: 'updating an office keeps its tickets',
    );
    expect(await repo.getOfficeStatus('nope'), isNull);
  });

  test('queue comes back in line order and can be filtered', () async {
    await repo.saveTickets([
      ticket(3),
      ticket(1, status: TicketStatus.completed),
      ticket(2),
      ticket(1, service: 'B'),
      ticket(1, officeId: 'north'),
    ]);
    expect((await repo.getQueue('main', day)).map((t) => t.code), [
      'A-001',
      'A-002',
      'A-003',
      'B-001',
    ]);
    expect(
      (await repo.getQueue(
        'main',
        day,
        statuses: {TicketStatus.waiting},
      )).map((t) => t.code),
      ['A-002', 'A-003', 'B-001'],
    );
  });

  test('positions count only waiting tickets ahead in the same line', () async {
    await repo.saveTickets([
      ticket(1, status: TicketStatus.completed),
      ticket(2, status: TicketStatus.serving),
      ticket(3),
      ticket(4, status: TicketStatus.cancelled),
      ticket(5),
      ticket(6),
      ticket(1, service: 'B'),
    ]);
    await repo.recomputePositions('main', day, now: now);
    expect(await positions(), {
      'A-001': null,
      'A-002': null,
      'A-003': 1,
      'A-004': null,
      'A-005': 2,
      'A-006': 3,
      'B-001': 1,
    });
  });

  test('my position, people ahead and estimated wait', () async {
    await repo.saveTickets([
      for (var i = 1; i <= 4; i++) ticket(i),
      ticket(5, mine: true),
    ]);
    await repo.recomputePositions('main', day, now: now);
    final pos = (await repo.getMyPosition('main-A-5'))!;
    expect(pos.position, 5);
    expect(pos.peopleAhead, 4);
    expect(pos.estimatedWait, const Duration(minutes: 12)); // 4 × 6 ÷ 2
    expect(pos.asOf, now);
    expect(pos.office.officeId, 'main');

    await repo.saveTickets([ticket(1, status: TicketStatus.serving)]);
    await repo.recomputePositions(
      'main',
      day,
      now: now.add(const Duration(minutes: 3)),
    );
    expect((await repo.getMyPosition('main-A-5'))!.position, 4);
  });

  test(
    'a position counted on the device is as old as the synced data',
    () async {
      // Last server data at 10:00; the user takes a ticket offline at 15:00.
      final syncedAt = DateTime(2026, 11, 21, 10);
      final later = DateTime(2026, 11, 21, 15);
      await repo.saveOfficeStatuses([
        office('main').copyWith(syncedAt: syncedAt, updatedAt: syncedAt),
      ]);
      await repo.saveTickets([ticket(1), ticket(2)]);
      final t = await repo.requestTicketOffline(
        officeId: 'main',
        serviceCode: 'A',
        now: later,
      );
      final pos = (await repo.getMyPosition(t.id))!;
      expect(pos.position, 3);
      expect(pos.asOf, syncedAt);
      expect(pos.isStale(later), isTrue);

      // After a fresh sync the position is current again.
      await repo.saveOfficeStatuses([
        office('main').copyWith(syncedAt: later, updatedAt: later),
      ]);
      expect((await repo.getMyPosition(t.id))!.isStale(later), isFalse);
    },
  );

  test('no position for a ticket that is not waiting', () async {
    await repo.saveTickets([
      ticket(1, status: TicketStatus.called, mine: true),
    ]);
    await repo.recomputePositions('main', day, now: now);
    expect(await repo.getMyPosition('main-A-1'), isNull);
    expect(await repo.getMyPosition('missing'), isNull);
  });

  test('only one active ticket of mine per office', () async {
    await repo.saveTickets([ticket(1, mine: true)]);
    await expectLater(
      repo.saveTickets([ticket(2, mine: true)]),
      throwsA(isA<QueueException>()),
    );
    // Fine at another office, or once the first is finished.
    await repo.saveTickets([ticket(1, officeId: 'north', mine: true)]);
    await repo.saveTickets([
      ticket(1, mine: true, status: TicketStatus.completed),
      ticket(2, mine: true),
    ]);
    expect(
      (await repo.getMyTickets(activeOnly: true)).map((t) => t.id),
      unorderedEquals(['north-A-1', 'main-A-2']),
    );
  });

  test('a ticket number can only be used once per line and day', () async {
    await repo.saveTickets([ticket(1)]);
    final t = ticket(1);
    final sameNumber = Ticket(
      id: 'another-id',
      officeId: t.officeId,
      serviceCode: t.serviceCode,
      number: t.number,
      serviceDate: t.serviceDate,
      status: t.status,
      issuedAt: t.issuedAt,
      updatedAt: t.updatedAt,
    );
    await expectLater(
      repo.saveTickets([sameNumber]),
      throwsA(isA<QueueException>()),
    );
    expect(await repo.countTickets(), 1);
  });

  test('taking a ticket offline: pending, no number, end of line', () async {
    await repo.saveTickets([
      ticket(1),
      ticket(2),
      ticket(3, status: TicketStatus.serving),
    ]);
    final t = await repo.requestTicketOffline(
      officeId: 'main',
      serviceCode: 'A',
      now: now,
    );
    expect(t.isMine, isTrue);
    expect(t.number, isNull);
    expect(t.code, 'A-…');
    expect(t.syncState, SyncState.pendingCreate);
    expect(t.position, 3);
    expect((await repo.getPendingChanges()).map((p) => p.id), [t.id]);

    await repo.markSynced(t.id, assignedNumber: 4);
    final synced = (await repo.getTicket(t.id))!;
    expect(synced.code, 'A-004');
    expect(synced.syncState, SyncState.synced);
    expect(await repo.getPendingChanges(), isEmpty);
  });

  test(
    'syncing with a number already in the line is a QueueException',
    () async {
      await repo.saveTickets([ticket(1), ticket(2)]);
      final t = await repo.requestTicketOffline(
        officeId: 'main',
        serviceCode: 'A',
        now: now,
      );
      await expectLater(
        repo.markSynced(t.id, assignedNumber: 2),
        throwsA(isA<QueueException>()),
      );
      final unchanged = (await repo.getTicket(t.id))!;
      expect(unchanged.number, isNull);
      expect(unchanged.syncState, SyncState.pendingCreate);
      await expectLater(
        repo.markSynced('missing'),
        throwsA(isA<QueueException>()),
      );
    },
  );

  test('cannot take a ticket at a closed or unknown office', () async {
    await repo.saveOfficeStatuses([office('closed', open: false)]);
    await expectLater(
      repo.requestTicketOffline(officeId: 'closed', serviceCode: 'A', now: now),
      throwsA(isA<QueueException>()),
    );
    await expectLater(
      repo.requestTicketOffline(officeId: 'x', serviceCode: 'A', now: now),
      throwsA(isA<QueueException>()),
    );
  });

  test('cancelling a synced ticket waits for sync; others move up', () async {
    await repo.saveTickets([ticket(1, mine: true), ticket(2), ticket(3)]);
    await repo.recomputePositions('main', day, now: now);
    await repo.cancelMyTicket('main-A-1', now: now);

    final cancelled = (await repo.getTicket('main-A-1'))!;
    expect(cancelled.status, TicketStatus.cancelled);
    expect(cancelled.position, isNull);
    expect(cancelled.syncState, SyncState.pendingCancel);
    expect(await positions(), {'A-001': null, 'A-002': 1, 'A-003': 2});
    expect((await repo.getPendingChanges()).single.id, 'main-A-1');

    await expectLater(
      repo.cancelMyTicket('main-A-1', now: now),
      throwsA(isA<QueueException>()),
    );
    await expectLater(
      repo.cancelMyTicket('main-A-2', now: now),
      throwsA(isA<QueueException>()),
    );
  });

  test('cancelling a ticket the server never saw deletes it', () async {
    final t = await repo.requestTicketOffline(
      officeId: 'main',
      serviceCode: 'A',
      now: now,
    );
    await repo.cancelMyTicket(t.id, now: now);
    expect(await repo.getTicket(t.id), isNull);
    expect(await repo.getPendingChanges(), isEmpty);
  });

  test('everything survives closing and reopening the database', () async {
    final dir = Directory.systemTemp.createTempSync('queue_db');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/queue.db';

    var (fileDb, fileRepo) = await openRepo(path);
    await fileRepo.saveOfficeStatuses([office('main')]);
    await fileRepo.saveTickets([ticket(1), ticket(2, mine: true)]);
    await fileRepo.recomputePositions('main', day, now: now);
    await fileDb.close();

    (fileDb, fileRepo) = await openRepo(path);
    final pos = (await fileRepo.getMyPosition('main-A-2'))!;
    expect(pos.position, 2);
    expect(pos.office.name, 'Office main');
    await fileDb.close();
  });
}
