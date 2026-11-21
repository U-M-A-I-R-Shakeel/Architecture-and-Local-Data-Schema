# Local storage: why SQLite (`sqflite`), and what it costs

The app must show the user's ticket, place in line and office status with no
internet connection. That needs storage that keeps ~1000+ tickets per day,
answers "how many people are ahead of me?" quickly, and never corrupts the
user's ticket. This compares the main Flutter options and records the
trade-offs of the one chosen.

## Options compared

| | **sqflite (SQLite)** — chosen | drift (SQLite) | Hive / hive_ce | Isar | shared_preferences |
|---|---|---|---|---|---|
| Kind | Relational SQL | Relational SQL, typed Dart API | Key–value boxes | Object (NoSQL) DB | Small key–value settings |
| "People ahead of me" | One indexed `COUNT(*)` query | Same, type-checked | Load the line into memory and count in Dart | Indexed query | Not suitable |
| Rules enforced by storage (one active ticket per office, unique numbers) | Yes: unique and partial indexes, CHECK, foreign keys | Yes | No, app code only | Unique indexes, no CHECK or foreign keys | No |
| Transactions | Yes | Yes | Limited | Yes | No |
| Schema changes | Version number + SQL migration steps | Generated migration helpers | No schema; old objects must be handled in code | Schema in code | — |
| Code generation | None | Required (`build_runner`) | Optional (adapters) | Required | None |
| Live updates to the UI | Not built in | Built in (`watch()`) | Built in (box listeners) | Built in | No |
| Web | No | Yes (wasm) | Yes | Limited | Yes |
| Use from plain Dart tools and tests | Yes, `sqflite_common_ffi` | Yes | Yes | Yes | No |
| Inspect the data file | Any SQLite tool (`sqlite3`, DB Browser) | Same | Hive-specific | Isar Inspector | — |

Maintenance status changes over time. At the time of writing, the original
Hive and Isar projects had slowed down and community forks (`hive_ce`,
`isar_community`) carry them on; sqflite and drift are actively maintained.
Check pub.dev before starting a new project.

## Why SQLite fits this data model

- **Queue position is a counting query.** "Waiting tickets in my line with a
  lower number" is a single `COUNT(*)` over the `idx_tickets_line` index. On
  the 1000-row sample, reading the user's position took **3–6 ms** and
  recalculating every position at an office **~2 ms** (measured on a Mac
  with `sqflite_common_ffi`; phones are slower but in the same range).
- **The database itself guards the rules.** A partial unique index allows
  only one active ticket per user per office; another stops a ticket number
  being used twice in a line; CHECK constraints reject unknown statuses. A
  bug in app code can't save a broken queue.
- **Transactions** keep a ticket change and the recalculated positions
  together: both happen or neither does.
- **Predictable migrations.** `QueueDatabase` has a version number and a
  list of SQL steps per version.
- **Same model as a server.** A backend is most likely relational too, so
  sync can map rows almost one to one.
- **One codebase for app, script and tests.** The schema and repository use
  `sqflite_common`, so the sample-data script and the tests run the exact
  same code on a computer via `sqflite_common_ffi`.

## What it costs

| Cost | How this project handles it |
|---|---|
| **Hand-written SQL and row mapping.** A typo in a column name only fails at run time. | All mapping is in one file (`row_mappers.dart`); repository tests cover every query. Moving to drift would make queries type-checked. |
| **No live updates.** sqflite can't watch a query, so the screen doesn't learn about changes by itself. | The repository announces its own writes on a `changes` stream (one event per committed transaction), and `DashboardController` re-reads on each one. This only sees writes made through the repository; drift's `watch()` would also catch raw SQL. |
| **Android uses the phone's own SQLite**, and older phones have old versions: Android 7 ships SQLite 3.9. `ON CONFLICT … DO UPDATE` (upsert) needs 3.24 and window functions need 3.25, which only Android 11+ have. | No upsert or window functions are used. Saves are "update by id, insert if missing"; positions use a correlated `COUNT(*)` subquery. |
| **`INSERT OR REPLACE` is a trap.** On a clash with any unique index it silently deletes the *other* row. In this model that would delete the user's existing ticket. | Not used. A clash raises an error, which the repository turns into a `QueueException`. Found by a test during development. |
| **No date type.** | Dates are ISO 8601 text (`2026-11-21T12:30:00.000`), days are `yyyy-MM-dd`; both sort correctly as text. |
| **Every call crosses from Dart to native code.** | Bulk saves run in one transaction; the 1000-row sample loads in about a second. |
| **No web support.** | Not needed for a phone app. drift (wasm) would be the switch if a web version is wanted. |
| **No encryption built in.** | Ticket data isn't sensitive (no names). If it becomes so, use an encrypted SQLite build (SQLCipher). |

## When to choose something else

- The UI must update live everywhere, or the team wants type-checked
  queries: **drift** (still SQLite, same schema).
- Only a few independent records, no queries or rules: **hive_ce**.
- A web version is required: **drift** with its web backend.
