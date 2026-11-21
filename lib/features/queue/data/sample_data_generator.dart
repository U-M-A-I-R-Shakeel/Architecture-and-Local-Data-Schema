import 'dart:math';

import '../domain/entities/enums.dart';
import '../domain/entities/office_status.dart';
import '../domain/entities/ticket.dart';
import '../domain/queue_repository.dart';
import 'row_mappers.dart';

/// Generated queue data for one day: offices plus [count] tickets.
class SampleQueueData {
  const SampleQueueData({
    required this.offices,
    required this.tickets,
    required this.now,
    required this.seed,
  });
  final List<OfficeStatus> offices;
  final List<Ticket> tickets;
  final DateTime now;
  final int seed;
}

/// Builds a realistic, self-consistent day of queue data:
///
/// * 4 offices (3 open, 1 closed), services A/B/C, tickets issued from 09:00.
/// * In each line, earlier tickets are finished (mostly completed, some
///   cancelled or no-show), one is being served, one may be called, and the
///   latest ones are waiting.
/// * Exactly one waiting ticket belongs to the user (`isMine`).
/// * Office status (now serving, waiting count) matches the tickets.
///
/// The same [seed] always gives the same data.
SampleQueueData generateSampleQueueData({
  int count = 1000,
  int seed = 42,
  required DateTime now,
}) {
  final rnd = Random(seed);
  final day = RowMappers.date(now);
  final opening = DateTime(now.year, now.month, now.day, 9);
  if (!now.isAfter(opening)) {
    throw ArgumentError.value(
      now,
      'now',
      'must be after 09:00, when the offices open and start issuing tickets',
    );
  }
  DateTime at(DateTime from, int minutes) =>
      from.add(Duration(minutes: minutes));

  const officeDefs = [
    // id, name, open, counters, avg minutes, share of tickets
    ('main', 'Main Branch', true, 4, 6, 0.35),
    ('north', 'North Branch', true, 2, 8, 0.20),
    ('city', 'City Centre', true, 3, 5, 0.30),
    ('airport', 'Airport Office', false, 0, 7, 0.15),
  ];
  const services = [('A', 0.5), ('B', 0.3), ('C', 0.2)];

  T pick<T>(List<(T, double)> weighted) {
    var r = rnd.nextDouble();
    for (final (v, w) in weighted) {
      if ((r -= w) <= 0) return v;
    }
    return weighted.last.$1;
  }

  // Spread the tickets over (office, service) lines.
  final lineSizes = <(String, String), int>{};
  for (var i = 0; i < count; i++) {
    final office = pick([for (final o in officeDefs) (o.$1, o.$6)]);
    final service = pick(services);
    lineSizes.update((office, service), (n) => n + 1, ifAbsent: () => 1);
  }

  final tickets = <Ticket>[];
  Ticket? mine;
  for (final o in officeDefs) {
    final (officeId, _, isOpen, counters, avg, _) = o;
    // A closed office stopped issuing at 11:30 (or now, if earlier) and has
    // served everyone. No ticket is ever issued after [now].
    final closedAt = DateTime(now.year, now.month, now.day, 11, 30);
    final lastIssue = isOpen || now.isBefore(closedAt) ? now : closedAt;
    final span = lastIssue.difference(opening).inMinutes;

    for (final (service, _) in services) {
      final n = lineSizes[(officeId, service)] ?? 0;
      if (n == 0) continue;
      final issued = [
        for (var i = 0; i < n; i++) at(opening, rnd.nextInt(span)),
      ]..sort();
      // Open lines: about a quarter still waiting, one serving, one called.
      final waiting = isOpen
          ? max(1, (n * (0.2 + rnd.nextDouble() * 0.1)).round())
          : 0;
      final serving = isOpen && n - waiting >= 1 ? 1 : 0;
      final called = isOpen && n - waiting - serving >= 1 && rnd.nextBool()
          ? 1
          : 0;
      final finished = n - waiting - serving - called;

      for (var i = 0; i < n; i++) {
        final number = i + 1;
        final issuedAt = issued[i];
        TicketStatus status;
        DateTime? calledAt, completedAt;
        int? counter;
        if (i < finished) {
          final roll = rnd.nextDouble();
          status = roll < 0.90
              ? TicketStatus.completed
              : roll < 0.95
              ? TicketStatus.noShow
              : TicketStatus.cancelled;
          if (status != TicketStatus.cancelled) {
            calledAt = at(issuedAt, 3 + rnd.nextInt(30));
            if (calledAt.isAfter(now)) calledAt = now;
            counter = 1 + rnd.nextInt(max(counters, 1));
          }
          if (status == TicketStatus.completed) {
            completedAt = at(calledAt!, max(1, avg - 2 + rnd.nextInt(5)));
            if (completedAt.isAfter(now)) completedAt = now;
          }
        } else if (i < finished + serving) {
          status = TicketStatus.serving;
          calledAt = at(now, -(1 + rnd.nextInt(avg)));
          counter = 1 + rnd.nextInt(counters);
        } else if (i < finished + serving + called) {
          status = TicketStatus.called;
          calledAt = at(now, -1);
          counter = 1 + rnd.nextInt(counters);
        } else {
          status = TicketStatus.waiting;
        }
        final updatedAt = completedAt ?? calledAt ?? issuedAt;
        tickets.add(
          Ticket(
            id: 'srv-$officeId-$day-$service-$number',
            officeId: officeId,
            serviceCode: service,
            number: number,
            serviceDate: day,
            status: status,
            issuedAt: issuedAt,
            calledAt: calledAt,
            completedAt: completedAt,
            counter: counter,
            updatedAt: updatedAt.isAfter(now) ? now : updatedAt,
          ),
        );
      }
    }
  }

  // The user's ticket: a waiting ticket in the middle of Main Branch line A.
  final mainA = [
    for (final (i, t) in tickets.indexed)
      if (t.officeId == 'main' &&
          t.serviceCode == 'A' &&
          t.status == TicketStatus.waiting)
        i,
  ];
  if (mainA.isNotEmpty) {
    final i = mainA[mainA.length ~/ 2];
    final t = tickets[i];
    mine = Ticket(
      id: t.id,
      officeId: t.officeId,
      serviceCode: t.serviceCode,
      number: t.number,
      serviceDate: t.serviceDate,
      status: t.status,
      issuedAt: t.issuedAt,
      updatedAt: t.updatedAt,
      isMine: true,
    );
    tickets[i] = mine;
  }

  final offices = [
    for (final (officeId, name, isOpen, counters, avg, _) in officeDefs)
      () {
        final here = tickets.where((t) => t.officeId == officeId);
        final latestCalled =
            here
                .where(
                  (t) =>
                      t.status == TicketStatus.serving ||
                      t.status == TicketStatus.called,
                )
                .toList()
              ..sort((a, b) => b.calledAt!.compareTo(a.calledAt!));
        return OfficeStatus(
          officeId: officeId,
          name: name,
          isOpen: isOpen,
          opensAt: '09:00',
          closesAt: isOpen ? '17:00' : '12:00',
          nowServing: latestCalled.isEmpty ? null : latestCalled.first.code,
          waitingCount: here
              .where((t) => t.status == TicketStatus.waiting)
              .length,
          countersOpen: counters,
          averageServiceMinutes: avg,
          updatedAt: now,
          syncedAt: now,
        );
      }(),
  ];

  return SampleQueueData(
    offices: offices,
    tickets: tickets,
    now: now,
    seed: seed,
  );
}

/// Saves [data] through the repository and works out every queue position.
Future<void> loadSampleData(QueueRepository repo, SampleQueueData data) async {
  await repo.saveOfficeStatuses(data.offices);
  await repo.saveTickets(data.tickets);
  for (final o in data.offices) {
    await repo.recomputePositions(
      o.officeId,
      RowMappers.date(data.now),
      now: data.now,
    );
  }
}
