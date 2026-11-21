// Generates sample queue data and writes it as a ready SQLite database and
// as JSON.
//
//   dart run tool/generate_sample_data.dart [--count 1000] [--seed 42]
//       [--date yyyy-MM-dd] [--out sample_data]
//
// The data is for one day, as seen at 12:30 that day. Same seed, same data.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:queue_system/core/database/queue_database.dart';
import 'package:queue_system/features/queue/data/row_mappers.dart';
import 'package:queue_system/features/queue/data/sample_data_generator.dart';
import 'package:queue_system/features/queue/data/sqlite_queue_repository.dart';
import 'package:queue_system/features/queue/domain/entities/enums.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  String? arg(String name) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final count = int.parse(arg('count') ?? '1000');
  final seed = int.parse(arg('seed') ?? '42');
  final outDir = arg('out') ?? 'sample_data';
  final date = arg('date') == null
      ? DateTime.now()
      : DateTime.parse(arg('date')!);
  final now = DateTime(date.year, date.month, date.day, 12, 30);

  final watch = Stopwatch()..start();
  final data = generateSampleQueueData(count: count, seed: seed, now: now);

  Directory(outDir).createSync(recursive: true);
  final dbPath = p.absolute(p.join(outDir, 'queue_sample.db'));
  final file = File(dbPath);
  if (file.existsSync()) file.deleteSync();

  sqfliteFfiInit();
  final db = await QueueDatabase.open(databaseFactoryFfi, dbPath);
  final repo = SqliteQueueRepository(db);
  await loadSampleData(repo, data);

  // Read back through the repository, so the JSON shows what the app sees.
  final offices = await repo.getOffices();
  final tickets = [
    for (final o in offices)
      ...await repo.getQueue(o.officeId, RowMappers.date(now)),
  ];
  final jsonPath = p.join(outDir, 'queue_sample.json');
  File(jsonPath).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'description': 'Sample queue data for one day, as seen at 12:30.',
      'seed': seed,
      'generatedFor': now.toIso8601String(),
      'officeCount': offices.length,
      'ticketCount': tickets.length,
      'offices': offices.map(RowMappers.officeToRow).toList(),
      'tickets': tickets.map(RowMappers.ticketToRow).toList(),
    }),
  );

  // How quickly the user's position is read from 1000 rows.
  final mine = (await repo.getMyTickets(activeOnly: true)).single;
  final lookup = Stopwatch()..start();
  final position = await repo.getMyPosition(mine.id);
  lookup.stop();
  final recompute = Stopwatch()..start();
  await repo.recomputePositions(mine.officeId, mine.serviceDate, now: now);
  recompute.stop();
  await db.close();

  final byStatus = <String, int>{};
  for (final t in tickets) {
    byStatus.update(t.status.dbValue, (n) => n + 1, ifAbsent: () => 1);
  }
  stdout
    ..writeln(
      'Generated ${tickets.length} tickets for ${offices.length} offices '
      '(seed $seed, ${RowMappers.date(now)} 12:30) in ${watch.elapsedMilliseconds} ms',
    )
    ..writeln(
      '  ${TicketStatus.values.map((s) => '${s.dbValue}: ${byStatus[s.dbValue] ?? 0}').join(', ')}',
    )
    ..writeln(
      '  offices: ${offices.map((o) => '${o.name} (${o.isOpen ? 'open' : 'closed'}, '
          '${o.waitingCount} waiting)').join('; ')}',
    )
    ..writeln(
      '  my ticket: ${mine.code} at ${position!.office.name}, position '
      '${position.position}, ${position.peopleAhead} ahead, '
      '~${position.estimatedWait.inMinutes} min',
    )
    ..writeln(
      '  my position lookup: ${lookup.elapsedMicroseconds / 1000} ms; '
      'recompute an office\'s positions: ${recompute.elapsedMicroseconds / 1000} ms',
    )
    ..writeln(
      '  wrote $dbPath (${File(dbPath).lengthSync() ~/ 1024} KB) and '
      '$jsonPath (${File(jsonPath).lengthSync() ~/ 1024} KB)',
    );
}
