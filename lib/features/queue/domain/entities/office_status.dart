/// The latest known state of an office, as last received from the server.
class OfficeStatus {
  const OfficeStatus({
    required this.officeId,
    required this.name,
    required this.isOpen,
    required this.opensAt,
    required this.closesAt,
    required this.waitingCount,
    required this.countersOpen,
    required this.averageServiceMinutes,
    required this.updatedAt,
    required this.syncedAt,
    this.nowServing,
  });

  final String officeId;
  final String name;

  /// Accepting and serving customers right now.
  final bool isOpen;

  /// Opening hours, `HH:mm` local time.
  final String opensAt;
  final String closesAt;

  /// Code of the ticket being served most recently, e.g. "A-031".
  final String? nowServing;

  /// Tickets waiting across all services.
  final int waitingCount;

  /// Counters currently serving customers.
  final int countersOpen;

  /// Average time per customer, used to estimate waits.
  final int averageServiceMinutes;

  /// When the office produced this status (server time).
  final DateTime updatedAt;

  /// When this device saved it. The gap to "now" shows how old it is.
  final DateTime syncedAt;

  OfficeStatus copyWith({
    bool? isOpen,
    String? Function()? nowServing,
    int? waitingCount,
    int? countersOpen,
    int? averageServiceMinutes,
    DateTime? updatedAt,
    DateTime? syncedAt,
  }) => OfficeStatus(
    officeId: officeId,
    name: name,
    isOpen: isOpen ?? this.isOpen,
    opensAt: opensAt,
    closesAt: closesAt,
    nowServing: nowServing == null ? this.nowServing : nowServing(),
    waitingCount: waitingCount ?? this.waitingCount,
    countersOpen: countersOpen ?? this.countersOpen,
    averageServiceMinutes: averageServiceMinutes ?? this.averageServiceMinutes,
    updatedAt: updatedAt ?? this.updatedAt,
    syncedAt: syncedAt ?? this.syncedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is OfficeStatus &&
      other.officeId == officeId &&
      other.name == name &&
      other.isOpen == isOpen &&
      other.opensAt == opensAt &&
      other.closesAt == closesAt &&
      other.nowServing == nowServing &&
      other.waitingCount == waitingCount &&
      other.countersOpen == countersOpen &&
      other.averageServiceMinutes == averageServiceMinutes &&
      other.updatedAt == updatedAt &&
      other.syncedAt == syncedAt;

  @override
  int get hashCode => Object.hash(
    officeId,
    name,
    isOpen,
    opensAt,
    closesAt,
    nowServing,
    waitingCount,
    countersOpen,
    averageServiceMinutes,
    updatedAt,
    syncedAt,
  );

  @override
  String toString() =>
      'OfficeStatus($officeId, open: $isOpen, serving: $nowServing, '
      'waiting: $waitingCount)';
}
