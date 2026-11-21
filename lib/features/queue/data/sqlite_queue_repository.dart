import 'dart:math';

import 'package:sqflite_common/sqlite_api.dart';

import '../domain/entities/enums.dart';
import '../domain/entities/office_status.dart';
import '../domain/entities/queue_position.dart';
import '../domain/entities/ticket.dart';
import '../domain/queue_repository.dart';
import 'row_mappers.dart';

/// [QueueRepository] backed by SQLite.
class SqliteQueueRepository implements QueueRepository {
  SqliteQueueRepository(this._db, {Random? random})
    : _random = random ?? Random.secure();

  final Database _db;
  final Random _random;

  static const _active = "('waiting', 'called', 'serving')";

  // Offices ----------------------------------------------------------------

  @override
  Future<List<OfficeStatus>> getOffices() async => [
    for (final r in await _db.query('office_status', orderBy: 'name'))
      RowMappers.officeFromRow(r),
  ];

  @override
  Future<OfficeStatus?> getOfficeStatus(String officeId) async {
    final rows = await _db.query(
      'office_status',
      where: 'office_id = ?',
      whereArgs: [officeId],
    );
    return rows.isEmpty ? null : RowMappers.officeFromRow(rows.single);
  }

  @override
  Future<void> saveOfficeStatuses(List<OfficeStatus> statuses) =>
      _db.transaction((txn) async {
        for (final s in statuses) {
          await _upsert(
            txn,
            'office_status',
            'office_id',
            s.officeId,
            RowMappers.officeToRow(s),
          );
        }
      });

  /// Updates the row with this key, or inserts it if there is none.
  ///
  /// Not `INSERT OR REPLACE`: on a clash with any *other* unique index,
  /// REPLACE silently deletes the other row (e.g. the user's existing
  /// ticket). Not `ON CONFLICT ... DO UPDATE` either: that needs SQLite 3.24,
  /// newer than Android 7–10 ship. Here every other rule break is an error.
  static Future<void> _upsert(
    DatabaseExecutor txn,
    String table,
    String keyColumn,
    Object key,
    Map<String, Object?> row,
  ) async {
    final updated = await txn.update(
      table,
      row,
      where: '$keyColumn = ?',
      whereArgs: [key],
    );
    if (updated == 0) await txn.insert(table, row);
  }

  // Tickets ----------------------------------------------------------------

  @override
  Future<void> saveTickets(List<Ticket> tickets) async {
    try {
      await _db.transaction((txn) async {
        for (final t in tickets) {
          await _upsert(txn, 'tickets', 'id', t.id, RowMappers.ticketToRow(t));
        }
      });
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw const QueueException(
          'You already have an active ticket at this office, '
          'or a ticket number is used twice.',
        );
      }
      rethrow;
    }
  }

  @override
  Future<Ticket?> getTicket(String id) async {
    final rows = await _db.query('tickets', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : RowMappers.ticketFromRow(rows.single);
  }

  @override
  Future<List<Ticket>> getQueue(
    String officeId,
    String serviceDate, {
    Set<TicketStatus>? statuses,
  }) async {
    final statusFilter = statuses == null || statuses.isEmpty
        ? ''
        : ' AND status IN (${List.filled(statuses.length, '?').join(', ')})';
    final rows = await _db.query(
      'tickets',
      where: 'office_id = ? AND service_date = ?$statusFilter',
      whereArgs: [
        officeId,
        serviceDate,
        if (statuses != null) ...statuses.map((s) => s.dbValue),
      ],
      // Unnumbered (offline) tickets go to the end of their line.
      orderBy: 'service_code, number IS NULL, number, issued_at',
    );
    return rows.map(RowMappers.ticketFromRow).toList();
  }

  @override
  Future<List<Ticket>> getMyTickets({bool activeOnly = false}) async {
    final rows = await _db.query(
      'tickets',
      where: 'is_mine = 1${activeOnly ? ' AND status IN $_active' : ''}',
      orderBy: 'issued_at DESC',
    );
    return rows.map(RowMappers.ticketFromRow).toList();
  }

  @override
  Future<QueuePosition?> getMyPosition(String ticketId) async {
    final ticket = await getTicket(ticketId);
    if (ticket == null ||
        ticket.status != TicketStatus.waiting ||
        ticket.position == null) {
      return null;
    }
    final office = await getOfficeStatus(ticket.officeId);
    if (office == null) return null;
    // A position recalculated on the device is only as fresh as the queue
    // data it was counted from, so use whichever is older.
    final computedAt = ticket.positionUpdatedAt ?? ticket.updatedAt;
    return QueuePosition(
      ticket: ticket,
      office: office,
      position: ticket.position!,
      asOf: office.syncedAt.isBefore(computedAt) ? office.syncedAt : computedAt,
    );
  }

  @override
  Future<void> recomputePositions(
    String officeId,
    String serviceDate, {
    required DateTime now,
  }) async {
    final ts = now.toIso8601String();
    await _db.transaction((txn) async {
      // Position = 1 + numbered waiting tickets ahead in the same line. A
      // correlated subquery, not a window function, so it also works with
      // the older SQLite versions on Android 7.
      await txn.rawUpdate(
        '''UPDATE tickets SET
             position = 1 + (
               SELECT COUNT(*) FROM tickets ahead
               WHERE ahead.office_id = tickets.office_id
                 AND ahead.service_date = tickets.service_date
                 AND ahead.service_code = tickets.service_code
                 AND ahead.status = 'waiting'
                 AND ahead.number IS NOT NULL
                 AND ahead.number < tickets.number),
             position_updated_at = ?
           WHERE office_id = ? AND service_date = ?
             AND status = 'waiting' AND number IS NOT NULL''',
        [ts, officeId, serviceDate],
      );
      // Offline tickets without a number go after everyone numbered.
      await txn.rawUpdate(
        '''UPDATE tickets SET
             position = 1 + (
               SELECT COUNT(*) FROM tickets ahead
               WHERE ahead.office_id = tickets.office_id
                 AND ahead.service_date = tickets.service_date
                 AND ahead.service_code = tickets.service_code
                 AND ahead.status = 'waiting'
                 AND (ahead.number IS NOT NULL
                      OR ahead.issued_at < tickets.issued_at)),
             position_updated_at = ?
           WHERE office_id = ? AND service_date = ?
             AND status = 'waiting' AND number IS NULL''',
        [ts, officeId, serviceDate],
      );
      // Only waiting tickets have a place in line.
      await txn.rawUpdate(
        '''UPDATE tickets SET position = NULL
           WHERE office_id = ? AND service_date = ?
             AND status != 'waiting' AND position IS NOT NULL''',
        [officeId, serviceDate],
      );
    });
  }

  // Offline actions --------------------------------------------------------

  @override
  Future<Ticket> requestTicketOffline({
    required String officeId,
    required String serviceCode,
    required DateTime now,
  }) async {
    final office = await getOfficeStatus(officeId);
    if (office == null) {
      throw QueueException('Unknown office "$officeId".');
    }
    if (!office.isOpen) {
      throw QueueException('${office.name} is closed.');
    }
    final ticket = Ticket(
      id: 'local-${now.microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}',
      officeId: officeId,
      serviceCode: serviceCode,
      number: null,
      serviceDate: RowMappers.date(now),
      status: TicketStatus.waiting,
      issuedAt: now,
      updatedAt: now,
      isMine: true,
      syncState: SyncState.pendingCreate,
    );
    await saveTickets([ticket]);
    await recomputePositions(officeId, ticket.serviceDate, now: now);
    return (await getTicket(ticket.id))!;
  }

  @override
  Future<void> cancelMyTicket(String ticketId, {required DateTime now}) async {
    final t = await getTicket(ticketId);
    if (t == null || !t.isMine) {
      throw const QueueException('That ticket isn\'t yours.');
    }
    if (!t.status.isActive) {
      throw const QueueException('That ticket is no longer in the queue.');
    }
    if (t.syncState == SyncState.pendingCreate) {
      // The server never saw it: just forget it.
      await _db.delete('tickets', where: 'id = ?', whereArgs: [ticketId]);
    } else {
      await saveTickets([
        t.copyWith(
          status: TicketStatus.cancelled,
          position: () => null,
          syncState: SyncState.pendingCancel,
          updatedAt: now,
        ),
      ]);
    }
    await recomputePositions(t.officeId, t.serviceDate, now: now);
  }

  @override
  Future<List<Ticket>> getPendingChanges() async {
    final rows = await _db.query(
      'tickets',
      where: "sync_state != 'synced'",
      orderBy: 'updated_at',
    );
    return rows.map(RowMappers.ticketFromRow).toList();
  }

  @override
  Future<void> markSynced(String ticketId, {int? assignedNumber}) async {
    final int count;
    try {
      count = await _db.update(
        'tickets',
        {'sync_state': SyncState.synced.dbValue, 'number': ?assignedNumber},
        where: 'id = ?',
        whereArgs: [ticketId],
      );
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw QueueException(
          'Ticket number $assignedNumber is already used in this line.',
        );
      }
      rethrow;
    }
    if (count == 0) throw QueueException('No ticket "$ticketId".');
  }

  @override
  Future<int> countTickets() async =>
      (await _db.rawQuery('SELECT COUNT(*) AS n FROM tickets')).single['n']!
          as int;
}
