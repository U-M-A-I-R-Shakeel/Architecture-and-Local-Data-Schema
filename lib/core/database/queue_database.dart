import 'package:sqflite_common/sqlite_api.dart';

/// The queue app's SQLite database: schema and migrations.
///
/// Uses only `sqflite_common`, so the same code runs in the app (sqflite) and
/// in plain Dart tools and tests (sqflite_common_ffi).
abstract final class QueueDatabase {
  static const fileName = 'queue.db';
  static const version = 1;

  static Future<Database> open(DatabaseFactory factory, String path) =>
      factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: version,
          singleInstance: false,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) => _migrate(db, 0, version),
          onUpgrade: _migrate,
        ),
      );

  /// Runs each schema step after [from] up to [to]. Add a new entry to
  /// [_steps] and raise [version] to change the schema.
  static Future<void> _migrate(Database db, int from, int to) async {
    for (var v = from + 1; v <= to; v++) {
      final batch = db.batch();
      for (final sql in _steps[v]!) {
        batch.execute(sql);
      }
      await batch.commit(noResult: true);
    }
  }

  static const _steps = <int, List<String>>{
    1: [
      '''
      CREATE TABLE office_status (
        office_id               TEXT PRIMARY KEY,
        name                    TEXT NOT NULL,
        is_open                 INTEGER NOT NULL CHECK (is_open IN (0, 1)),
        opens_at                TEXT NOT NULL,              -- HH:mm
        closes_at               TEXT NOT NULL,              -- HH:mm
        now_serving             TEXT,                       -- e.g. A-031
        waiting_count           INTEGER NOT NULL DEFAULT 0,
        counters_open           INTEGER NOT NULL DEFAULT 0,
        average_service_minutes INTEGER NOT NULL DEFAULT 5,
        updated_at              TEXT NOT NULL,              -- ISO 8601
        synced_at               TEXT NOT NULL               -- ISO 8601
      )''',
      '''
      CREATE TABLE tickets (
        id                  TEXT PRIMARY KEY,
        office_id           TEXT NOT NULL
                            REFERENCES office_status (office_id),
        service_code        TEXT NOT NULL,
        number              INTEGER,                        -- null until assigned
        service_date        TEXT NOT NULL,                  -- yyyy-MM-dd
        status              TEXT NOT NULL CHECK (status IN
                              ('waiting', 'called', 'serving',
                               'completed', 'cancelled', 'no_show')),
        issued_at           TEXT NOT NULL,
        called_at           TEXT,
        completed_at        TEXT,
        counter             INTEGER,
        position            INTEGER,                        -- 1 = next
        position_updated_at TEXT,
        is_mine             INTEGER NOT NULL DEFAULT 0 CHECK (is_mine IN (0, 1)),
        sync_state          TEXT NOT NULL DEFAULT 'synced' CHECK (sync_state IN
                              ('synced', 'pending_create', 'pending_cancel')),
        updated_at          TEXT NOT NULL
      )''',
      // Line order and position counting.
      '''
      CREATE INDEX idx_tickets_line
      ON tickets (office_id, service_date, service_code, status, number)''',
      // A number is used once per office, day and service.
      '''
      CREATE UNIQUE INDEX idx_tickets_number
      ON tickets (office_id, service_date, service_code, number)
      WHERE number IS NOT NULL''',
      // The user can hold at most one active ticket per office.
      '''
      CREATE UNIQUE INDEX idx_tickets_one_active_mine
      ON tickets (office_id)
      WHERE is_mine = 1 AND status IN ('waiting', 'called', 'serving')''',
      // Fast lookups of the user's tickets and of unsynced changes.
      'CREATE INDEX idx_tickets_mine ON tickets (is_mine) WHERE is_mine = 1',
      '''
      CREATE INDEX idx_tickets_pending ON tickets (sync_state)
      WHERE sync_state != 'synced' ''',
    ],
  };
}
