import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'core/database/queue_database.dart';
import 'features/queue/data/queue_simulator.dart';
import 'features/queue/data/sample_data_generator.dart';
import 'features/queue/data/sqlite_queue_repository.dart';
import 'features/queue/domain/queue_repository.dart';
import 'features/queue/presentation/dashboard_controller.dart';
import 'features/queue/presentation/queue_dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await QueueDatabase.open(
    databaseFactory,
    p.join(await getDatabasesPath(), QueueDatabase.fileName),
  );
  final repository = SqliteQueueRepository(db);

  // First launch: generate today's sample queue (1000 tickets) on a
  // background isolate while the UI is already showing its loading state.
  final ready = seedSampleDataIfEmpty(repository, now: _sampleTime());

  runApp(QueueApp(repository: repository, ready: ready));
}

/// The sample data is "as seen now" during office hours, so "as of" times
/// match the clock. Outside them (offices open 09:00–17:00) it is a day as
/// seen at 12:30, and the app rightly shows that data as out of date.
DateTime _sampleTime() {
  final now = DateTime.now();
  DateTime at(int h, int m) => DateTime(now.year, now.month, now.day, h, m);
  return now.isAfter(at(9, 5)) && now.isBefore(at(16, 30)) ? now : at(12, 30);
}

class QueueApp extends StatefulWidget {
  const QueueApp({super.key, required this.repository, this.ready});

  final QueueRepository repository;
  final Future<void>? ready;

  @override
  State<QueueApp> createState() => _QueueAppState();
}

class _QueueAppState extends State<QueueApp> {
  late final controller = DashboardController(
    repository: widget.repository,
    ready: widget.ready,
  )..start();
  late final simulator = QueueSimulator(widget.repository);

  @override
  void dispose() {
    simulator.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Queue',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
      useMaterial3: true,
    ),
    home: QueueDashboardScreen(controller: controller, simulator: simulator),
  );
}
