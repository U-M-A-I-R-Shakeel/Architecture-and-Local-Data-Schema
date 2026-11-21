import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'core/database/queue_database.dart';
import 'features/queue/data/sample_data_generator.dart';
import 'features/queue/data/sqlite_queue_repository.dart';
import 'features/queue/presentation/queue_home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await QueueDatabase.open(
    databaseFactory,
    p.join(await getDatabasesPath(), QueueDatabase.fileName),
  );
  final repository = SqliteQueueRepository(db);

  // First launch: fill the empty database with today's sample queue
  // (1000 tickets), so the app has data to show without a server.
  if (await repository.countTickets() == 0) {
    final now = DateTime.now();
    await loadSampleData(
      repository,
      generateSampleQueueData(
        now: DateTime(now.year, now.month, now.day, 12, 30),
      ),
    );
  }

  runApp(
    MaterialApp(
      title: 'Queue',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: QueueHomeScreen(repository: repository),
    ),
  );
}
