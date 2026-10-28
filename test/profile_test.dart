import 'package:daily_report_reminder/main.dart';
import 'package:daily_report_reminder/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('first launch shows welcome before the report workspace', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ReportApp(prefs: prefs));
    expect(find.text('Welcome to DailyReport'), findsOneWidget);
    expect(find.text('Overview'), findsNothing);
  });
  testWidgets(
    'welcome requires a name, but not a photo, and persists completion',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            prefs: prefs,
            welcome: true,
            onComplete: () => completed = true,
          ),
        ),
      );
      await tester.ensureVisible(find.text('Get started'));
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      expect(find.text('Please enter your name.'), findsOneWidget);
      expect(completed, isFalse);
      await tester.enterText(find.byType(TextFormField), '  Anas  ');
      await tester.ensureVisible(find.text('Get started'));
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(prefs.getString('profile.name'), 'Anas');
      expect(prefs.getBool('profile.complete'), isTrue);
      expect(prefs.getString('profile.photo'), isNull);
    },
  );

  testWidgets('settings can rename the profile and remove its photo', (
    tester,
  ) async {
    const image =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII=';
    SharedPreferences.setMockInitialValues({
      'profile.name': 'Old name',
      'profile.complete': true,
      'profile.photo': image,
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => ProfileScreen(prefs: prefs)),
            ),
            child: const Text('Open profile'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open profile'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'New name');
    await tester.tap(find.text('Remove photo'));
    await tester.pump();
    await tester.tap(find.text('Save profile'));
    await tester.pumpAndSettle();
    expect(prefs.getString('profile.name'), 'New name');
    expect(prefs.getString('profile.photo'), isNull);
    expect(find.text('Open profile'), findsOneWidget);
  });
}
