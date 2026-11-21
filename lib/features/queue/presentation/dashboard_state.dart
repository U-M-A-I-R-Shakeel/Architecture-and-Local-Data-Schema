import 'package:flutter/foundation.dart';

import '../domain/entities/office_status.dart';
import '../domain/entities/queue_position.dart';
import '../domain/entities/ticket.dart';

/// What the dashboard shows. One of four states, so the screen can't end up
/// half loading and half showing data.
sealed class DashboardState {
  const DashboardState();
}

/// Nothing read yet (first launch may still be preparing offline data).
final class DashboardLoading extends DashboardState {
  const DashboardLoading();

  @override
  bool operator ==(Object other) => other is DashboardLoading;

  @override
  int get hashCode => 0;
}

/// The user has no active ticket. [offices] may also be empty if nothing has
/// ever been downloaded.
final class DashboardEmpty extends DashboardState {
  const DashboardEmpty({required this.offices, required this.now});

  final List<OfficeStatus> offices;
  final DateTime now;

  @override
  bool operator ==(Object other) =>
      other is DashboardEmpty && listEquals(other.offices, offices);

  @override
  int get hashCode => Object.hashAll(offices);
}

/// The user's active ticket.
final class DashboardReady extends DashboardState {
  const DashboardReady({
    required this.ticket,
    required this.office,
    required this.position,
    required this.offices,
    required this.now,
  });

  final Ticket ticket;

  /// The ticket's office, if its status is stored.
  final OfficeStatus? office;

  /// Place in line. `null` once the ticket is called or being served.
  final QueuePosition? position;
  final List<OfficeStatus> offices;

  /// When this state was read, for "may be out of date" checks.
  final DateTime now;

  bool get isStale => position?.isStale(now) ?? false;

  @override
  bool operator ==(Object other) =>
      other is DashboardReady &&
      other.ticket == ticket &&
      other.office == office &&
      other.position?.position == position?.position &&
      other.position?.asOf == position?.asOf &&
      listEquals(other.offices, offices) &&
      other.isStale == isStale;

  // [now] itself is left out: a re-read that finds the same data and the
  // same freshness is equal, so it causes no rebuild.
  @override
  int get hashCode => Object.hash(
    ticket,
    office,
    position?.position,
    position?.asOf,
    Object.hashAll(offices),
    isStale,
  );
}

/// Local storage could not be read.
final class DashboardError extends DashboardState {
  const DashboardError(this.message);
  final String message;

  @override
  bool operator ==(Object other) =>
      other is DashboardError && other.message == message;

  @override
  int get hashCode => message.hashCode;
}
