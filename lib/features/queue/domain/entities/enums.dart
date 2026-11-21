/// Where a ticket is in its life cycle.
enum TicketStatus {
  /// In the line, not called yet. Only waiting tickets have a position.
  waiting('waiting'),

  /// Called to a counter; the customer is on the way.
  called('called'),

  /// Being served at a counter now.
  serving('serving'),

  /// Service finished.
  completed('completed'),

  /// Cancelled by the customer.
  cancelled('cancelled'),

  /// Called but the customer didn't come.
  noShow('no_show');

  const TicketStatus(this.dbValue);

  /// Text stored in the database.
  final String dbValue;

  /// Still in the office's queue (waiting, called or being served).
  bool get isActive => this == waiting || this == called || this == serving;

  static TicketStatus fromDb(String value) =>
      values.firstWhere((s) => s.dbValue == value);
}

/// Whether a local change has reached the server yet.
enum SyncState {
  /// Same as the server.
  synced('synced'),

  /// Created on this device while offline; the server hasn't seen it.
  pendingCreate('pending_create'),

  /// Cancelled on this device while offline; the server hasn't seen it.
  pendingCancel('pending_cancel');

  const SyncState(this.dbValue);

  final String dbValue;

  static SyncState fromDb(String value) =>
      values.firstWhere((s) => s.dbValue == value);
}
