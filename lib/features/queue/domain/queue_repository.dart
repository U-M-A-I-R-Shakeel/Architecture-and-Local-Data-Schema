import 'entities/enums.dart';
import 'entities/office_status.dart';
import 'entities/queue_position.dart';
import 'entities/ticket.dart';

/// Thrown when a change would break a queue rule. [message] is safe to show.
class QueueException implements Exception {
  const QueueException(this.message);
  final String message;

  @override
  String toString() => 'QueueException: $message';
}

/// All access to locally stored queue data goes through this interface. The
/// app and the sync code never touch the database directly, so the storage
/// library can change without touching them.
abstract interface class QueueRepository {
  // Offices ----------------------------------------------------------------

  /// Every office, by name.
  Future<List<OfficeStatus>> getOffices();

  Future<OfficeStatus?> getOfficeStatus(String officeId);

  /// Inserts or replaces office statuses (e.g. after a sync).
  Future<void> saveOfficeStatuses(List<OfficeStatus> statuses);

  // Tickets ----------------------------------------------------------------

  /// Inserts or replaces tickets (e.g. a queue snapshot from the server).
  /// Throws [QueueException] if the user would own two active tickets at the
  /// same office.
  Future<void> saveTickets(List<Ticket> tickets);

  Future<Ticket?> getTicket(String id);

  /// One office's tickets for a day, in line order (service, then number).
  Future<List<Ticket>> getQueue(
    String officeId,
    String serviceDate, {
    Set<TicketStatus>? statuses,
  });

  /// The user's tickets, newest first.
  Future<List<Ticket>> getMyTickets({bool activeOnly = false});

  /// The user's place in line for [ticketId], or `null` if the ticket isn't
  /// waiting.
  Future<QueuePosition?> getMyPosition(String ticketId);

  /// Recalculates `position` for every waiting ticket at an office on a day,
  /// from the tickets stored locally. Call after saving new ticket data.
  Future<void> recomputePositions(
    String officeId,
    String serviceDate, {
    required DateTime now,
  });

  // Offline actions --------------------------------------------------------

  /// Takes a ticket while offline. It is saved as `pendingCreate` with no
  /// number and an estimated position until the server confirms it.
  Future<Ticket> requestTicketOffline({
    required String officeId,
    required String serviceCode,
    required DateTime now,
  });

  /// Cancels one of the user's tickets. Synced tickets become
  /// `pendingCancel`; tickets the server never saw are deleted.
  Future<void> cancelMyTicket(String ticketId, {required DateTime now});

  /// Local changes the server hasn't received yet, oldest first.
  Future<List<Ticket>> getPendingChanges();

  /// Records that the server accepted a pending change. [assignedNumber] is
  /// the number the server gave a ticket created offline.
  Future<void> markSynced(String ticketId, {int? assignedNumber});

  Future<int> countTickets();
}
