import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/entities/ticket.dart';
import '../domain/queue_repository.dart';
import 'dashboard_state.dart';

/// Keeps [state] in step with local storage.
///
/// It listens to [QueueRepository.changes] and re-reads after every write,
/// so the screen updates the moment the database changes, whether the user,
/// a sync or the demo simulator made the change. Actions such as
/// [takeTicket] only write; the new state arrives through the same path.
///
/// Built on Flutter's own [ChangeNotifier], so there is no state-management
/// package to learn or keep up to date.
class DashboardController extends ChangeNotifier {
  DashboardController({
    required QueueRepository repository,
    Future<void>? ready,
    DateTime Function()? clock,
    this.tickEvery = const Duration(seconds: 30),
  }) : _repo = repository,
       _ready = ready ?? Future.value(),
       _clock = clock ?? DateTime.now;

  final QueueRepository _repo;
  final Future<void> _ready;
  final DateTime Function() _clock;

  /// How often to re-read with no change, so "may be out of date" appears
  /// on time even when nothing is written.
  final Duration tickEvery;

  StreamSubscription<void>? _changes;
  Timer? _ticker;
  bool _started = false;
  bool _disposed = false;

  // Coalescing: a burst of writes causes at most one read in progress plus
  // one more after it, never a read per write.
  bool _reading = false;
  bool _readAgain = false;

  DashboardState _state = const DashboardLoading();
  DashboardState get state => _state;

  /// How many times storage was read. For tests and diagnostics.
  int get reads => _reads;
  int _reads = 0;

  /// Waits for [ready] (e.g. first-launch sample data), then reads and starts
  /// listening. Safe to call more than once.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      await _ready;
    } catch (e) {
      _set(DashboardError('Could not prepare offline data: $e'));
      return;
    }
    if (_disposed) return;
    _changes = _repo.changes.listen((_) => refresh());
    _ticker = Timer.periodic(tickEvery, (_) => refresh());
    await refresh();
  }

  /// Re-reads local storage. Called on every change; also on pull-to-refresh.
  Future<void> refresh() async {
    if (_reading) {
      _readAgain = true;
      return;
    }
    _reading = true;
    try {
      do {
        _readAgain = false;
        final next = await _read();
        if (_disposed) return;
        _set(next);
      } while (_readAgain);
    } finally {
      _reading = false;
    }
  }

  Future<DashboardState> _read() async {
    _reads++;
    try {
      final now = _clock();
      final mine = await _repo.getMyTickets(activeOnly: true);
      final offices = await _repo.getOffices();
      if (mine.isEmpty) return DashboardEmpty(offices: offices, now: now);
      final ticket = mine.first;
      return DashboardReady(
        ticket: ticket,
        office: offices.where((o) => o.officeId == ticket.officeId).firstOrNull,
        position: await _repo.getMyPosition(ticket.id),
        offices: offices,
        now: now,
      );
    } catch (e) {
      return DashboardError('Could not read local data: $e');
    }
  }

  void _set(DashboardState next) {
    if (next == _state) return; // nothing new: no rebuild
    _state = next;
    notifyListeners();
  }

  // Actions: they only write. The change stream brings the new state.

  /// Takes a ticket offline. Throws [QueueException] with a message to show.
  Future<Ticket> takeTicket(String officeId, String serviceCode) =>
      _repo.requestTicketOffline(
        officeId: officeId,
        serviceCode: serviceCode,
        now: _clock(),
      );

  /// Cancels the user's current ticket. Throws [QueueException].
  Future<void> cancelTicket() async {
    final s = _state;
    if (s is! DashboardReady) return;
    await _repo.cancelMyTicket(s.ticket.id, now: _clock());
  }

  @override
  void dispose() {
    _disposed = true;
    _changes?.cancel();
    _ticker?.cancel();
    super.dispose();
  }
}
