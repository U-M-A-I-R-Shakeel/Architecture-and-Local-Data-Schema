import 'office_status.dart';
import 'ticket.dart';

/// The user's place in line, worked out from locally stored data, so it can
/// be shown without an internet connection.
class QueuePosition {
  const QueuePosition({
    required this.ticket,
    required this.office,
    required this.position,
    required this.asOf,
  });

  final Ticket ticket;
  final OfficeStatus office;

  /// 1 means next.
  final int position;

  /// When the position was last worked out. Shown as "as of 10:42".
  final DateTime asOf;

  int get peopleAhead => position - 1;

  /// People ahead × average service time ÷ open counters, rounded up.
  Duration get estimatedWait {
    final counters = office.countersOpen < 1 ? 1 : office.countersOpen;
    final minutes = (peopleAhead * office.averageServiceMinutes / counters)
        .ceil();
    return Duration(minutes: minutes);
  }

  /// Older than [maxAge]: the app should say the data may be out of date.
  bool isStale(DateTime now, {Duration maxAge = const Duration(minutes: 5)}) =>
      now.difference(asOf) > maxAge;
}
