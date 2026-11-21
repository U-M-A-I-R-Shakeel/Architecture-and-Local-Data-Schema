import 'dart:async';
import 'dart:math';

import 'package:sqflite_common/sqlite_api.dart';

import '../domain/entities/enums.dart';
import '../domain/entities/office_status.dart';
import '../domain/entities/queue_position.dart';
import '../domain/entities/ticket.dart';
import '../domain/queue_repository.dart';
import 'row_mappers.dart';

/// [QueueRepository] backed by SQLite.
///
/// SQLite (sqflite) has no built-in way to watch data, so this class
/// announces its own writes on [changes]. Every public write runs in one
/// transaction and emits once, after it commits, so listeners never see a
/// half-finished change (e.g. a new ticket before its position is set).
class SqliteQueueRepository implements QueueRepository {
  SqliteQueueRepository(this._db, {Random? random})
    : _random = random ?? Random.secure();

  final Database _db;
  final Random _random;
  final _changes = StreamController<void>.broadcast();

  static const _active = "('waiting', 'called', 'serving')";

  @override
  Stream<void> get changes => _changes.stream;

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  /// Runs [action] in a transaction, turns rule breaks into
  /// [QueueException], and announces the change once it is committed.
  Future<T> _write<T>(Future<T> Function(Transaction txn) action) async {
    final T result;
    try {
      result = await _db.transaction(action);
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw const QueueException(
          'You already have an active ticket at this office, '
          'or a ticket number is used twice.',
        );
      }
      rethrow;
    }
    _notify();
    return result;
  }

  @override
  Future<void> dispose() => _changes.close();

  // Offices ----------------------------------------------------------------

  @override
  Future<List<OfficeStatus>> getOffices() async => [
    for (final r in await _db.query('office_status', orderBy: 'name'))
      RowMappers.officeFromRow(r),
  ];

  @override
  Future<OfficeStatus?> getOfficeStatus(String officeId) =>
      _officeStatus(_db, officeId);

  static Future<OfficeStatus?> _officeStatus(
    DatabaseExecutor db,
    String officeId,
  ) async {
    final rows = await db.query(
      'office_status',
      where: 'office_id = ?',
      whereArgs: [officeId],
    );
    return rows.isEmpty ? null : RowMappers.officeFromRow(rows.single);
  }

  @override
  Future<void> saveOfficeStatuses(List<OfficeStatus> statuses) => _write(
    (txn) => _upsertAll(txn, 'office_status', 'office_id', [
      for (final s in statuses) RowMappers.officeToRow(s),
    ]),
  );

  /// Updates each row that has this key, then inserts the ones that had
  /// none. Two batches, so saving 1000 rows is two trips to the database
  /// instead of 2000, which keeps the app responsive on first launch.
  ///
  /// Not `INSERT OR REPLACE`: on a clash with any *other* unique index,
  /// REPLACE silently deletes the other row (e.g. the user's existing
  /// ticket). Not `ON CONFLICT ... DO UPDATE` either: that needs SQLite 3.24,
  /// newer than Android 7–10 ship. Here every other rule break is an error.
  static Future<void> _upsertAll(
    Transaction txn,
    String table,
    String keyColumn,
    List<Map<String, Object?>> rows,
  ) async {
    // The last copy of a row wins, as if they were saved one by one.
    final byKey = {for (final r in rows) r[keyColumn]: r};
    if (byKey.isEmpty) return;
    final updates = txn.batch();
    for (final MapEntry(:key, :value) in byKey.entries) {
      updates.update(table, value, where: '$keyColumn = ?', whereArgs: [key]);
    }
    final counts = await updates.commit();
    final inserts = txn.batch();
    var any = false;
    for (final (i, row) in byKey.values.indexed) {
      if (counts[i] == 0) {
        inserts.insert(table, row);
        any = true;
      }
    }
    if (any) await inserts.commit(noResult: true);
  }

  // Tickets ----------------------------------------------------------------

  @override
  Future<void> saveTickets(List<Ticket> tickets) =>
      _write((txn) => _saveTickets(txn, tickets));

  static Future<void> _saveTickets(Transaction txn, List<Ticket> tickets) =>
      _upsertAll(txn, 'tickets', 'id', [
        for (final t in tickets) RowMappers.ticketToRow(t),
      ]);

  @override
  Future<Ticket?> getTicket(String id) => _ticket(_db, id);

  static Future<Ticket?> _ticket(DatabaseExecutor db, String id) async {
    final rows = await db.query('tickets', where: 'id = ?', whereArgs: [id]);
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
  }) => _write((txn) => _recompute(txn, officeId, serviceDate, now));

  static Future<void> _recompute(
    Transaction txn,
    String officeId,
    String serviceDate,
    DateTime now,
  ) async {
    final ts = now.toIso8601String();
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
  }

  @override
  Future<void> saveQueueUpdate({
    required List<Ticket> tickets,
    List<OfficeStatus> offices = const [],
    required DateTime now,
  }) => _write((txn) async {
    await _upsertAll(txn, 'office_status', 'office_id', [
      for (final s in offices) RowMappers.officeToRow(s),
    ]);
    await _saveTickets(txn, tickets);
    final lines = {for (final t in tickets) (t.officeId, t.serviceDate)};
    for (final (officeId, serviceDate) in lines) {
      await _recompute(txn, officeId, serviceDate, now);
    }
  });

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
    return _write((txn) async {
      await _saveTickets(txn, [ticket]);
      await _recompute(txn, officeId, ticket.serviceDate, now);
      return (await _ticket(txn, ticket.id))!;
    });
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
    await _write((txn) async {
      if (t.syncState == SyncState.pendingCreate) {
        // The server never saw it: just forget it.
        await txn.delete('tickets', where: 'id = ?', whereArgs: [ticketId]);
      } else {
        await _saveTickets(txn, [
          t.copyWith(
            status: TicketStatus.cancelled,
            position: () => null,
            syncState: SyncState.pendingCancel,
            updatedAt: now,
          ),
        ]);
      }
      await _recompute(txn, t.officeId, t.serviceDate, now);
    });
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
      count = await _write(
        (txn) => txn.update(
          'tickets',
          {'sync_state': SyncState.synced.dbValue, 'number': ?assignedNumber},
          where: 'id = ?',
          whereArgs: [ticketId],
        ),
      );
    } on QueueException {
      throw QueueException(
        'Ticket number $assignedNumber is already used in this line.',
      );
    }
    if (count == 0) throw QueueException('No ticket "$ticketId".');
  }

  @override
  Future<int> countTickets() async =>
      (await _db.rawQuery('SELECT COUNT(*) AS n FROM tickets')).single['n']!
          as int;
}
