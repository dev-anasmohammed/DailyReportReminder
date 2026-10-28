import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class DailySchedule {
  const DailySchedule({
    this.start = 540,
    this.end = 1080,
    this.reminders = const [840, 1020, 1080],
  });
  final int start;
  final int end;
  final List<int> reminders;
  static DailySchedule load(SharedPreferences prefs) {
    final raw = prefs.getString('dailySchedule');
    if (raw == null) return const DailySchedule();
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return DailySchedule(
      start: data['start'] as int,
      end: data['end'] as int,
      reminders: (data['reminders'] as List).cast<int>(),
    );
  }

  String? get validationError {
    if (start < 0 || end > 1439 || start >= end) {
      return 'End time must be later than start time.';
    }
    if (reminders.any((m) => m < start || m > end)) {
      return 'Reminders must fall within your working hours.';
    }
    if (reminders.toSet().length != reminders.length) {
      return 'Each reminder must have a different time.';
    }
    return null;
  }

  Future<void> save(SharedPreferences prefs) async {
    if (validationError != null) throw ArgumentError(validationError);
    await prefs.setString(
      'dailySchedule',
      jsonEncode({'start': start, 'end': end, 'reminders': reminders}),
    );
  }

  DateTime at(DateTime day, int minute) =>
      DateTime(day.year, day.month, day.day, minute ~/ 60, minute % 60);
  List<int> due(DateTime now, Set<int> delivered) =>
      now.isBefore(at(now, start))
      ? []
      : [
          for (final m in reminders)
            if (!now.isBefore(at(now, m)) && !delivered.contains(m)) m,
        ];
}
