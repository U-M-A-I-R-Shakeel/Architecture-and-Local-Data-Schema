import 'enums.dart';

/// A queue ticket: the user's own ticket, or another customer's ticket in a
/// queue snapshot received from the server.
///
/// Numbers restart every day, per office and service, so a ticket is
/// identified for people by [code] (e.g. "A-042") plus [serviceDate].
class Ticket {
  const Ticket({
    required this.id,
    required this.officeId,
    required this.serviceCode,
    required this.number,
    required this.serviceDate,
    required this.status,
    required this.issuedAt,
    required this.updatedAt,
    this.calledAt,
    this.completedAt,
    this.counter,
    this.position,
    this.positionUpdatedAt,
    this.isMine = false,
    this.syncState = SyncState.synced,
  });

  /// Unique id. Created on the device for offline tickets, so it never
  /// clashes with server ids.
  final String id;
  final String officeId;

  /// Service line within the office, e.g. "A" (general), "B" (payments).
  final String serviceCode;

  /// Number in the day's line for this service. `null` while a ticket made
  /// offline is waiting for the server to assign one.
  final int? number;

  /// The day the ticket belongs to, `yyyy-MM-dd` (local time).
  final String serviceDate;

  final TicketStatus status;
  final DateTime issuedAt;
  final DateTime? calledAt;
  final DateTime? completedAt;

  /// Counter the ticket was called to.
  final int? counter;

  /// Place in line: 1 means next. Only set while [status] is waiting.
  final int? position;

  /// When [position] was last worked out (by the server or on the device).
  final DateTime? positionUpdatedAt;

  /// This device's user owns the ticket.
  final bool isMine;

  final SyncState syncState;

  /// Last change to this row.
  final DateTime updatedAt;

  /// Human-readable ticket code, e.g. "A-042", or "A-…" before the server
  /// has assigned a number.
  String get code => number == null
      ? '$serviceCode-…'
      : '$serviceCode-${number.toString().padLeft(3, '0')}';

  Ticket copyWith({
    int? number,
    TicketStatus? status,
    DateTime? calledAt,
    DateTime? completedAt,
    int? counter,
    int? Function()? position,
    DateTime? Function()? positionUpdatedAt,
    SyncState? syncState,
    DateTime? updatedAt,
  }) => Ticket(
    id: id,
    officeId: officeId,
    serviceCode: serviceCode,
    number: number ?? this.number,
    serviceDate: serviceDate,
    status: status ?? this.status,
    issuedAt: issuedAt,
    calledAt: calledAt ?? this.calledAt,
    completedAt: completedAt ?? this.completedAt,
    counter: counter ?? this.counter,
    position: position == null ? this.position : position(),
    positionUpdatedAt: positionUpdatedAt == null
        ? this.positionUpdatedAt
        : positionUpdatedAt(),
    isMine: isMine,
    syncState: syncState ?? this.syncState,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is Ticket &&
      other.id == id &&
      other.officeId == officeId &&
      other.serviceCode == serviceCode &&
      other.number == number &&
      other.serviceDate == serviceDate &&
      other.status == status &&
      other.issuedAt == issuedAt &&
      other.calledAt == calledAt &&
      other.completedAt == completedAt &&
      other.counter == counter &&
      other.position == position &&
      other.positionUpdatedAt == positionUpdatedAt &&
      other.isMine == isMine &&
      other.syncState == syncState &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    officeId,
    serviceCode,
    number,
    serviceDate,
    status,
    issuedAt,
    calledAt,
    completedAt,
    counter,
    position,
    positionUpdatedAt,
    isMine,
    syncState,
    updatedAt,
  );

  @override
  String toString() =>
      'Ticket($code, $officeId, ${status.name}, position: $position, '
      'mine: $isMine, ${syncState.name})';
}
