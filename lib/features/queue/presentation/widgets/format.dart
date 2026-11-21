/// Small text formatters shared by the dashboard widgets.
abstract final class QueueFormat {
  /// `HH:mm`, 24-hour.
  static String hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  /// "Under 1 min", "~30 min", "~1 h 20 min".
  static String wait(Duration d) {
    final minutes = d.inMinutes;
    if (minutes < 1) return 'Under 1 min';
    if (minutes < 60) return '~$minutes min';
    final h = minutes ~/ 60, m = minutes % 60;
    return m == 0 ? '~$h h' : '~$h h $m min';
  }

  /// "You're next", "1 person ahead", "20 people ahead".
  static String ahead(int people) => switch (people) {
    0 => "You're next",
    1 => '1 person ahead',
    _ => '$people people ahead',
  };

  static const serviceNames = {
    'A': 'General',
    'B': 'Payments',
    'C': 'Documents',
  };

  static String service(String code) => serviceNames[code] ?? 'Service $code';
}
