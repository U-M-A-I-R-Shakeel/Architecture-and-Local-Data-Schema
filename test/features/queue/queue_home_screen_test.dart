import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:queue_system/features/queue/domain/entities/enums.dart';
import 'package:queue_system/features/queue/domain/entities/office_status.dart';
import 'package:queue_system/features/queue/domain/entities/queue_position.dart';
import 'package:queue_system/features/queue/domain/entities/ticket.dart';
import 'package:queue_system/features/queue/domain/queue_repository.dart';
import 'package:queue_system/features/queue/presentation/queue_home_screen.dart';

import '../../helpers.dart';

/// The screen only depends on [QueueRepository], so a tiny fake replaces
/// the database here.
class _FakeRepository implements QueueRepository {
  _FakeRepository(this.mine, this.offices);
  final Ticket? mine;
  final List<OfficeStatus> offices;

  @override
  Future<List<Ticket>> getMyTickets({bool activeOnly = false}) async => [?mine];

  @override
  Future<QueuePosition?> getMyPosition(String ticketId) async => mine == null
      ? null
      : QueuePosition(
          ticket: mine!,
          office: offices.first,
          position: mine!.position!,
          asOf: now,
        );

  @override
  Future<List<OfficeStatus>> getOffices() async => offices;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  Future<void> pump(
    WidgetTester tester,
    QueueRepository repo,
    DateTime at,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QueueHomeScreen(repository: repo, clock: () => at),
      ),
    );
    await tester.pumpAndSettle();
  }

  final offices = [
    office(
      'main',
      counters: 4,
    ).copyWith(nowServing: () => 'A-126', waitingCount: 84),
    office('airport', open: false),
  ];

  testWidgets('shows my ticket, position, wait and offices', (tester) async {
    final mine = Ticket(
      id: 'm',
      officeId: 'main',
      serviceCode: 'A',
      number: 147,
      serviceDate: day,
      status: TicketStatus.waiting,
      issuedAt: now,
      updatedAt: now,
      position: 21,
      positionUpdatedAt: now,
      isMine: true,
    );
    await pump(tester, _FakeRepository(mine, offices), now);

    expect(find.text('A-147'), findsOneWidget);
    expect(find.text('Position 21 · 20 ahead · ~30 min'), findsOneWidget);
    expect(find.text('As of 12:30'), findsOneWidget);
    expect(
      find.text('Now serving A-126 · 84 waiting · 4 counters'),
      findsOneWidget,
    );
    expect(find.text('Closed · open 09:00–17:00'), findsOneWidget);
  });

  testWidgets('warns when the position is out of date', (tester) async {
    final mine = ticket(5, mine: true).copyWith(position: () => 3);
    await pump(
      tester,
      _FakeRepository(mine, offices),
      now.add(const Duration(minutes: 20)),
    );
    expect(find.text('As of 12:30 · may be out of date'), findsOneWidget);
  });

  testWidgets('no ticket', (tester) async {
    await pump(tester, _FakeRepository(null, offices), now);
    expect(find.text('You have no ticket.'), findsOneWidget);
  });
}
