import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:queue_system/features/queue/data/queue_simulator.dart';
import 'package:queue_system/features/queue/data/sample_data_generator.dart';
import 'package:queue_system/features/queue/data/sqlite_queue_repository.dart';
import 'package:queue_system/features/queue/domain/entities/enums.dart';
import 'package:queue_system/features/queue/domain/queue_repository.dart';
import 'package:queue_system/features/queue/presentation/dashboard_controller.dart';
import 'package:queue_system/features/queue/presentation/dashboard_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers.dart';

/// The controller against a real SQLite database: proves the state follows
/// storage, with no refresh calls from the test.
void main() {
  late Database db;
  late SqliteQueueRepository repo;
  late DateTime clock;

  setUp(() async {
    (db, repo) = await openRepo();
    clock = now;
    addTearDown(() async {
      await repo.dispose();
      await db.close();
    });
    await repo.saveOfficeStatuses([office('main'), office('north')]);
  });

  DashboardController controller({Future<void>? ready}) {
    final c = DashboardController(
      repository: repo,
      ready: ready,
      clock: () => clock,
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Waits until the controller has caught up with storage.
  Future<void> settle() => pumpEventQueue(times: 50);

  test('loading until ready, then empty when the user has no ticket', () async {
    final ready = Completer<void>();
    final c = controller(ready: ready.future);
    unawaited(c.start());
    await settle();
    expect(c.state, isA<DashboardLoading>());

    ready.complete();
    await settle();
    final s = c.state as DashboardEmpty;
    expect(s.offices.map((o) => o.officeId), ['main', 'north']);
  });

  test('an error while preparing data is shown, not swallowed', () async {
    final c = controller(ready: Future.error('disk full'));
    await c.start();
    expect(c.state, isA<DashboardError>());
    expect((c.state as DashboardError).message, contains('disk full'));
  });

  test('state follows storage: take, sync, move up, cancel', () async {
    await repo.saveQueueUpdate(
      tickets: [ticket(1), ticket(2), ticket(3)],
      now: now,
    );
    final c = controller();
    await c.start();
    expect(c.state, isA<DashboardEmpty>());

    // Taking a ticket only writes; the state arrives via the change stream.
    await c.takeTicket('main', 'A');
    await settle();
    var s = c.state as DashboardReady;
    expect(s.ticket.code, 'A-…');
    expect(s.ticket.syncState, SyncState.pendingCreate);
    expect(s.position!.position, 4);

    // Someone else's write (a sync) updates the screen too.
    await repo.markSynced(s.ticket.id, assignedNumber: 4);
    await repo.saveQueueUpdate(
      tickets: [ticket(1, status: TicketStatus.serving)],
      now: now,
    );
    await settle();
    s = c.state as DashboardReady;
    expect(s.ticket.code, 'A-004');
    expect(s.ticket.syncState, SyncState.synced);
    expect(s.position!.position, 3);

    await c.cancelTicket();
    await settle();
    expect(c.state, isA<DashboardEmpty>());
  });

  test('a burst of writes causes a few reads, not one per write', () async {
    final c = controller();
    await c.start();
    final before = c.reads;
    await Future.wait([
      for (var i = 1; i <= 30; i++) repo.saveTickets([ticket(i)]),
    ]);
    await settle();
    expect(c.reads - before, lessThan(10));
    expect(c.state, isA<DashboardEmpty>());
  });

  test('no rebuild when a re-read finds nothing new', () async {
    final c = controller();
    await c.start();
    var notified = 0;
    c.addListener(() => notified++);
    await c.refresh();
    await c.refresh();
    expect(notified, 0);
  });

  test('the warning appears once the data gets old, with no writes', () async {
    await repo.saveQueueUpdate(
      tickets: [ticket(1), ticket(2, mine: true)],
      now: now,
    );
    final c = controller();
    await c.start();
    expect((c.state as DashboardReady).isStale, isFalse);

    clock = now.add(const Duration(minutes: 6));
    await c.refresh(); // what the 30-second ticker does
    expect((c.state as DashboardReady).isStale, isTrue);
  });

  test('the simulator moves the user up until called, then done', () async {
    await loadSampleData(repo, generateSampleQueueData(count: 200, now: now));
    final c = controller();
    await c.start();
    final sim = QueueSimulator(repo, clock: () => clock);
    addTearDown(sim.dispose);

    var s = c.state as DashboardReady;
    final start = s.position!.position;
    await sim.advance();
    await settle();
    s = c.state as DashboardReady;
    expect(s.position!.position, start - 1);
    expect(s.office!.syncedAt, clock);

    for (var i = 0; i < start - 1; i++) {
      await sim.advance();
    }
    await settle();
    s = c.state as DashboardReady;
    expect(s.ticket.status, TicketStatus.called);
    expect(s.position, isNull);
    expect(s.ticket.counter, isNotNull);

    await sim.advance(); // at the counter
    await sim.advance(); // finished
    await settle();
    expect(c.state, isA<DashboardEmpty>());
  });

  test('take ticket errors are QueueExceptions with a message', () async {
    await repo.saveOfficeStatuses([office('shut', open: false)]);
    final c = controller();
    await c.start();
    await expectLater(
      c.takeTicket('shut', 'A'),
      throwsA(
        isA<QueueException>().having(
          (e) => e.message,
          'message',
          contains('closed'),
        ),
      ),
    );
  });
}
