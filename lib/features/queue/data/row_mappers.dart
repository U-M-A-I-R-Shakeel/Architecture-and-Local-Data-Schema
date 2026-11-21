import '../domain/entities/enums.dart';
import '../domain/entities/office_status.dart';
import '../domain/entities/ticket.dart';

/// Converts entities to and from database rows. Times are stored as ISO 8601
/// text in local time; `yyyy-MM-dd` and `HH:mm` sort correctly as text.
abstract final class RowMappers {
  static String _ts(DateTime d) => d.toIso8601String();
  static DateTime? _parse(Object? v) =>
      v == null ? null : DateTime.parse(v as String);

  static Map<String, Object?> officeToRow(OfficeStatus o) => {
    'office_id': o.officeId,
    'name': o.name,
    'is_open': o.isOpen ? 1 : 0,
    'opens_at': o.opensAt,
    'closes_at': o.closesAt,
    'now_serving': o.nowServing,
    'waiting_count': o.waitingCount,
    'counters_open': o.countersOpen,
    'average_service_minutes': o.averageServiceMinutes,
    'updated_at': _ts(o.updatedAt),
    'synced_at': _ts(o.syncedAt),
  };

  static OfficeStatus officeFromRow(Map<String, Object?> r) => OfficeStatus(
    officeId: r['office_id']! as String,
    name: r['name']! as String,
    isOpen: r['is_open'] == 1,
    opensAt: r['opens_at']! as String,
    closesAt: r['closes_at']! as String,
    nowServing: r['now_serving'] as String?,
    waitingCount: r['waiting_count']! as int,
    countersOpen: r['counters_open']! as int,
    averageServiceMinutes: r['average_service_minutes']! as int,
    updatedAt: _parse(r['updated_at'])!,
    syncedAt: _parse(r['synced_at'])!,
  );

  static Map<String, Object?> ticketToRow(Ticket t) => {
    'id': t.id,
    'office_id': t.officeId,
    'service_code': t.serviceCode,
    'number': t.number,
    'service_date': t.serviceDate,
    'status': t.status.dbValue,
    'issued_at': _ts(t.issuedAt),
    'called_at': t.calledAt == null ? null : _ts(t.calledAt!),
    'completed_at': t.completedAt == null ? null : _ts(t.completedAt!),
    'counter': t.counter,
    'position': t.position,
    'position_updated_at': t.positionUpdatedAt == null
        ? null
        : _ts(t.positionUpdatedAt!),
    'is_mine': t.isMine ? 1 : 0,
    'sync_state': t.syncState.dbValue,
    'updated_at': _ts(t.updatedAt),
  };

  static Ticket ticketFromRow(Map<String, Object?> r) => Ticket(
    id: r['id']! as String,
    officeId: r['office_id']! as String,
    serviceCode: r['service_code']! as String,
    number: r['number'] as int?,
    serviceDate: r['service_date']! as String,
    status: TicketStatus.fromDb(r['status']! as String),
    issuedAt: _parse(r['issued_at'])!,
    calledAt: _parse(r['called_at']),
    completedAt: _parse(r['completed_at']),
    counter: r['counter'] as int?,
    position: r['position'] as int?,
    positionUpdatedAt: _parse(r['position_updated_at']),
    isMine: r['is_mine'] == 1,
    syncState: SyncState.fromDb(r['sync_state']! as String),
    updatedAt: _parse(r['updated_at'])!,
  );

  /// `yyyy-MM-dd` for a local date.
  static String date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
