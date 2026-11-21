import 'package:queue_system/core/database/queue_database.dart';
import 'package:queue_system/features/queue/data/sqlite_queue_repository.dart';
import 'package:queue_system/features/queue/domain/entities/enums.dart';
import 'package:queue_system/features/queue/domain/entities/office_status.dart';
import 'package:queue_system/features/queue/domain/entities/ticket.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final now = DateTime(2026, 11, 21, 12, 30);
const day = '2026-11-21';

Future<(Database, SqliteQueueRepository)> openRepo([String? path]) async {
  sqfliteFfiInit();
  final db = await QueueDatabase.open(
    databaseFactoryFfi,
    path ?? inMemoryDatabasePath,
  );
  return (db, SqliteQueueRepository(db));
}

OfficeStatus office(
  String id, {
  bool open = true,
  int counters = 2,
  int avg = 6,
}) => OfficeStatus(
  officeId: id,
  name: 'Office $id',
  isOpen: open,
  opensAt: '09:00',
  closesAt: '17:00',
  waitingCount: 0,
  countersOpen: counters,
  averageServiceMinutes: avg,
  updatedAt: now,
  syncedAt: now,
);

Ticket ticket(
  int number, {
  String officeId = 'main',
  String service = 'A',
  TicketStatus status = TicketStatus.waiting,
  bool mine = false,
}) => Ticket(
  id: '$officeId-$service-$number',
  officeId: officeId,
  serviceCode: service,
  number: number,
  serviceDate: day,
  status: status,
  issuedAt: DateTime(2026, 11, 21, 9).add(Duration(minutes: number)),
  updatedAt: DateTime(2026, 11, 21, 9).add(Duration(minutes: number)),
  isMine: mine,
);
