import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_report_reminder/schedule.dart';
import 'package:daily_report_reminder/settings_screen.dart';

void main() {
  test('defaults are 9 AM to 6 PM with 2, 5 and 6 PM reminders', () {
    const s = DailySchedule();
    expect(s.start, 540);
    expect(s.end, 1080);
    expect(s.reminders, [840, 1020, 1080]);
    expect(s.due(DateTime(2026, 10, 28, 13, 59), {}), isEmpty);
    expect(s.due(DateTime(2026, 10, 28, 14), {}), [840]);
    expect(s.due(DateTime(2026, 10, 28, 17), {840}), [1020]);
    expect(s.due(DateTime(2026, 10, 28, 18), {840, 1020}), [1080]);
    expect(s.due(DateTime(2026, 10, 28, 19), {840, 1020, 1080}), isEmpty);
    expect(s.due(DateTime(2026, 10, 28, 19), {}), [840, 1020, 1080]);
    expect(s.due(DateTime(2026, 10, 29, 8), {}), isEmpty);
  });
  test('custom reminder list persists and validates', () async {
    SharedPreferences.setMockInitialValues({'first': 120, 'before': 15});
    final prefs = await SharedPreferences.getInstance();
    expect(DailySchedule.load(prefs).reminders, [840, 1020, 1080]);
    const s = DailySchedule(
      start: 600,
      end: 1140,
      reminders: [660, 720, 900, 1140],
    );
    await s.save(prefs);
    expect(DailySchedule.load(prefs).reminders, s.reminders);
    expect(DailySchedule.load(prefs).start, 600);
    expect(DailySchedule.load(prefs).end, 1140);
    expect(
      const DailySchedule(start: 1080, end: 540).validationError,
      isNotNull,
    );
    expect(const DailySchedule(reminders: [400]).validationError, isNotNull);
    expect(
      const DailySchedule(reminders: [840, 840]).validationError,
      isNotNull,
    );
    await const DailySchedule(reminders: []).save(prefs);
    expect(DailySchedule.load(prefs).reminders, isEmpty);
  });
  testWidgets('settings lets users remove reminders and save', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    DailySchedule? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          schedule: const DailySchedule(),
          startup: false,
          onStartup: (v) async => v,
          onTest: () async {},
          onSave: (s) async {
            saved = s;
          },
        ),
      ),
    );
    expect(find.text('Working hours'), findsOneWidget);
    expect(find.text('Reminder 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove reminder 2'));
    await tester.pump();
    expect(find.text('Reminder 3'), findsNothing);
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(saved?.reminders, [840, 1080]);
  });
}
