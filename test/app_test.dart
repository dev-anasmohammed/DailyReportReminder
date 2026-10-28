import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_report_reminder/main.dart';
import 'package:daily_report_reminder/report.dart';

void main() {
  testWidgets(
    'sending highlights missing required report sections before Gmail setup',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'profile.complete': true,
        'profile.name': 'Test',
      });
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ReportApp(prefs: prefs));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preview & send'));
      await tester.pumpAndSettle();
      expect(
        find.text('This field is required to send your report.'),
        findsNWidgets(2),
      );
      expect(find.text('Gmail delivery'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('1. What I have worked on today')),
        'Finished work',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('This field is required to send your report.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('2. What I will work on tomorrow')),
        'Finish tests',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('This field is required to send your report.'),
        findsNothing,
      );
      expect(
        prefs.getString('${dateKey(DateTime.now())}.blockers') ?? '',
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('restores today draft and saves edits without touching history', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = dateKey(DateTime.now());
    SharedPreferences.setMockInitialValues({
      'profile.complete': true,
      'profile.name': 'Test user',
      '$day.today': '**App/**\n- Saved work',
      '$day.tomorrow': '- Existing plan',
      '$day.blockers': '- Existing blocker',
      '2020-01-01.today': '- Historical work',
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ReportApp(prefs: prefs));
    await tester.pumpAndSettle();
    expect(find.text('Daily report'), findsOneWidget);
    expect(find.text('Your workday'), findsNothing);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(prefs.getString('$day.tomorrow'), '- Existing plan');
    final workField = find.byKey(
      const ValueKey('1. What I have worked on today'),
    );
    await tester.ensureVisible(workField);
    await tester.enterText(workField, '- Updated work');
    await tester.pump();
    expect(prefs.getString('$day.today'), '- Updated work');
    expect(prefs.getString('2020-01-01.today'), '- Historical work');
    tester.view.physicalSize = const Size(840, 650);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Projects'));
    await tester.pumpAndSettle();
    expect(find.text('Your projects'), findsOneWidget);
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();
    expect(prefs.getString('$day.today'), '- Updated work');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
