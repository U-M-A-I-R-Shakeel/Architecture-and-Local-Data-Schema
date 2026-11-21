import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:queue_system/features/queue/domain/entities/enums.dart';
import 'package:queue_system/features/queue/domain/entities/office_status.dart';
import 'package:queue_system/features/queue/domain/entities/queue_position.dart';
import 'package:queue_system/features/queue/domain/entities/ticket.dart';
import 'package:queue_system/features/queue/domain/queue_repository.dart';
import 'package:queue_system/features/queue/presentation/dashboard_controller.dart';
import 'package:queue_system/features/queue/presentation/queue_dashboard_screen.dart';

import '../../helpers.dart';

/// In-memory storage. Like the real repository, every write emits on
/// [changes]; the screen depends only on [QueueRepository].
class _FakeRepository implements QueueRepository {
  _FakeRepository({this.mine, List<OfficeStatus>? offices})
    : offices = offices ?? _offices;

  Ticket? mine;
  List<OfficeStatus> offices;
  final _changes = StreamController<void>.broadcast();

  /// Simulates a write by someone else (e.g. a sync).
  void write({Ticket? mine, bool clearMine = false}) {
    if (clearMine) this.mine = null;
    if (mine != null) this.mine = mine;
    _changes.add(null);
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<List<OfficeStatus>> getOffices() async => offices;

  @override
  Future<List<Ticket>> getMyTickets({bool activeOnly = false}) async => [
    if (mine case final t? when !activeOnly || t.status.isActive) t,
  ];

  @override
  Future<QueuePosition?> getMyPosition(String ticketId) async {
    final t = mine;
    if (t == null || t.status != TicketStatus.waiting || t.position == null) {
      return null;
    }
    return QueuePosition(
      ticket: t,
      office: offices.firstWhere((o) => o.officeId == t.officeId),
      position: t.position!,
      asOf: t.positionUpdatedAt ?? now,
    );
  }

  @override
  Future<Ticket> requestTicketOffline({
    required String officeId,
    required String serviceCode,
    required DateTime now,
  }) async {
    if (officeId == 'full') {
      throw const QueueException('That office is not taking tickets.');
    }
    final t = Ticket(
      id: 'local-1',
      officeId: officeId,
      serviceCode: serviceCode,
      number: null,
      serviceDate: day,
      status: TicketStatus.waiting,
      issuedAt: now,
      updatedAt: now,
      position: 85,
      positionUpdatedAt: now,
      isMine: true,
      syncState: SyncState.pendingCreate,
    );
    write(mine: t);
    return t;
  }

  @override
  Future<void> cancelMyTicket(String ticketId, {required DateTime now}) async =>
      write(clearMine: true);

  @override
  Future<void> dispose() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final _offices = [
  office(
    'main',
    counters: 4,
  ).copyWith(nowServing: () => 'A-126', waitingCount: 84),
  office('airport', open: false),
];

Ticket _mine({
  int position = 21,
  TicketStatus status = TicketStatus.waiting,
  int? counter,
}) => Ticket(
  id: 'm',
  officeId: 'main',
  serviceCode: 'A',
  number: 147,
  serviceDate: day,
  status: status,
  issuedAt: now,
  updatedAt: now,
  counter: counter,
  position: status == TicketStatus.waiting ? position : null,
  positionUpdatedAt: now,
  isMine: true,
);

void main() {
  /// Shows the dashboard. Returns a function that ends the test cleanly.
  Future<Future<void> Function()> show(
    WidgetTester tester,
    QueueRepository repo, {
    DateTime? at,
    Future<void>? ready,
  }) async {
    final controller = DashboardController(
      repository: repo,
      ready: ready,
      clock: () => at ?? now,
    );
    unawaited(controller.start());
    await tester.pumpWidget(
      MaterialApp(home: QueueDashboardScreen(controller: controller)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // cross-fade
    return () async {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    };
  }

  testWidgets('shows a loading skeleton until offline data is ready', (
    tester,
  ) async {
    final ready = Completer<void>();
    final done = await show(
      tester,
      _FakeRepository(mine: _mine()),
      ready: ready.future,
    );
    expect(find.text('Preparing your offline queue…'), findsOneWidget);
    expect(find.byKey(const ValueKey('my-ticket-code')), findsNothing);

    ready.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Preparing your offline queue…'), findsNothing);
    expect(find.text('A-147'), findsOneWidget);
    await done();
  });

  testWidgets('position and wait time widgets', (tester) async {
    final done = await show(tester, _FakeRepository(mine: _mine()));
    expect(find.text('A-147'), findsOneWidget);
    expect(find.text('Main Branch · General'), findsNothing); // fake name
    expect(find.text('Office main · General'), findsOneWidget);
    expect(find.text('21'), findsOneWidget);
    expect(find.text('20 people ahead'), findsOneWidget);
    expect(find.text('Now serving A-126'), findsOneWidget);
    expect(find.text('~30 min'), findsOneWidget); // 20 × 6 ÷ 4
    expect(find.text('Expected around 13:00'), findsOneWidget);
    expect(find.text('20 ahead × 6 min ÷ 4 counters'), findsOneWidget);
    expect(find.text('As of 12:30'), findsOneWidget);
    expect(
      find.text('Now serving A-126 · 84 waiting · 4 counters'),
      findsOneWidget,
    );
    expect(find.text('Closed · open 09:00–17:00'), findsOneWidget);
    await done();
  });

  testWidgets('updates as soon as storage changes, with no refresh', (
    tester,
  ) async {
    final repo = _FakeRepository(mine: _mine());
    final done = await show(tester, repo);
    expect(find.text('20 people ahead'), findsOneWidget);

    repo.write(mine: _mine(position: 2));
    await tester.pump(); // read
    await tester.pump(const Duration(milliseconds: 300)); // number animation
    expect(find.text('1 person ahead'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('~2 min'), findsOneWidget);

    repo.write(mine: _mine(position: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("You're next"), findsOneWidget);
    expect(find.text('Under 1 min'), findsOneWidget);

    repo.write(mine: _mine(status: TicketStatus.called, counter: 3));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("It's your turn"), findsOneWidget);
    expect(find.text('Please go to counter 3'), findsOneWidget);
    expect(find.text('Estimated wait'), findsNothing);
    await done();
  });

  testWidgets('warns when the data is old', (tester) async {
    final done = await show(
      tester,
      _FakeRepository(mine: _mine()),
      at: now.add(const Duration(minutes: 20)),
    );
    expect(find.text('As of 12:30 · may be out of date'), findsOneWidget);
    await done();
  });

  testWidgets('empty state: take a ticket, then cancel it', (tester) async {
    final repo = _FakeRepository();
    final done = await show(tester, repo);
    expect(find.text("You're not in a queue"), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('take-ticket')));
    await tester.pumpAndSettle();
    // Only open offices are offered.
    expect(find.byKey(const ValueKey('service-airport-A')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('service-main-B')));
    await tester.pumpAndSettle();
    expect(find.text('B-…'), findsOneWidget);
    expect(find.text('Waiting to sync'), findsOneWidget);
    expect(find.text('85'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cancel-ticket')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-cancel')));
    await tester.pumpAndSettle();
    expect(find.text("You're not in a queue"), findsOneWidget);
    await done();
  });

  testWidgets('a failed action shows its message', (tester) async {
    final repo = _FakeRepository(offices: [office('full')]);
    final done = await show(tester, repo);
    await tester.tap(find.byKey(const ValueKey('take-ticket')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('service-full-A')));
    await tester.pumpAndSettle();
    expect(find.text('That office is not taking tickets.'), findsOneWidget);
    await done();
  });

  testWidgets('empty state with no office data at all', (tester) async {
    final done = await show(tester, _FakeRepository(offices: []));
    expect(find.text('No office data yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('take-ticket')), findsNothing);
    await done();
  });

  testWidgets('wide screens put position and wait side by side', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final done = await show(tester, _FakeRepository(mine: _mine()));
    final position = tester.getTopLeft(find.text('Your ticket'));
    final wait = tester.getTopLeft(find.text('Estimated wait'));
    expect(wait.dy, closeTo(position.dy, 8));
    expect(wait.dx, greaterThan(position.dx));
    await done();
  });
}
