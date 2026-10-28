import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daily_report_reminder/reminder_dialog.dart';

void main() {
  for (final entry in {
    'Open report': ReminderAction.openReport,
    'Snooze 10 minutes': ReminderAction.snooze,
    'Dismiss': ReminderAction.dismiss,
  }.entries) {
    testWidgets('center reminder returns ${entry.value.name}', (tester) async {
      ReminderAction? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<ReminderAction>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const ReminderDialog(
                      message: 'Update your daily report.',
                    ),
                  );
                },
                child: const Text('Show reminder'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Show reminder'));
      await tester.pumpAndSettle();
      expect(find.text('Time for your daily report'), findsOneWidget);
      final dialogCenter = tester.getCenter(find.byType(AlertDialog));
      expect(
        dialogCenter.dx,
        closeTo(
          tester.view.physicalSize.width / tester.view.devicePixelRatio / 2,
          1,
        ),
      );
      expect(
        dialogCenter.dy,
        closeTo(
          tester.view.physicalSize.height / tester.view.devicePixelRatio / 2,
          1,
        ),
      );
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(result, entry.value);
      expect(find.byType(AlertDialog), findsNothing);
    });
  }
}
