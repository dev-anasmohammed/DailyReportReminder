import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_report_reminder/main.dart';
import 'package:daily_report_reminder/report.dart';

void main() {
  testWidgets('restores today draft and saves edits without touching history', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = dateKey(DateTime.now());
    SharedPreferences.setMockInitialValues({
      '$day.today': '**App/**\n- Saved work',
      '$day.tomorrow': '- Existing plan',
      '$day.blockers': '- Existing blocker',
      '2020-01-01.today': '- Historical work',
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ReportApp(prefs: prefs));
    await tester.pumpAndSettle();
    expect(find.text('Make your work count.'), findsOneWidget);
    expect(find.text('Your workday'), findsNothing);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(prefs.getString('$day.tomorrow'), '- Existing plan');
    final workField = find.byType(TextField).at(1);
    await tester.ensureVisible(workField);
    await tester.enterText(workField, '- Updated work');
    await tester.pump();
    expect(prefs.getString('$day.today'), '- Updated work');
    expect(prefs.getString('2020-01-01.today'), '- Historical work');
    await tester.pumpWidget(const SizedBox());
  });
}
