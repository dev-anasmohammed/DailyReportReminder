import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_report_reminder/app_theme.dart';
import 'package:daily_report_reminder/gmail/gmail_service.dart';
import 'package:daily_report_reminder/gmail/gmail_settings_screen.dart';
import 'package:daily_report_reminder/gmail/gmail_reply_screen.dart';
import 'package:daily_report_reminder/report_clipboard.dart';

import 'gmail_test.dart' show MemoryVault, sampleThread;

void main() {
  testWidgets(
    'setup clearly identifies the missing OAuth client and gates connection',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = GmailService(vault: MemoryVault());
      addTearDown(service.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: reportTheme(),
          home: GmailSettingsScreen(gmail: service, prefs: prefs),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Import OAuth client JSON'), findsOneWidget);
      final connect = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Connect Gmail'),
      );
      expect(connect.onPressed, isNull);
      expect(find.text('Not connected'), findsOneWidget);
    },
  );
  testWidgets(
    'preview exposes recipients and blocks a second click while sending',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final result = Completer<void>();
      var calls = 0;
      final html = reportHtml('**App:**\n01- Finished work', '01- Tests', '');
      await tester.pumpWidget(
        MaterialApp(
          theme: reportTheme(),
          home: GmailReplyScreen(
            thread: sampleThread(),
            account: 'me@example.com',
            replyAll: false,
            plain: 'Report',
            html: html,
            onSend: (reply) {
              calls++;
              expect(reply.to.single.email, 'manager@example.com');
              return result.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      expect(
        tester.widget<TextField>(fields.at(0)).controller!.text,
        contains('manager@example.com'),
      );
      expect(tester.widget<TextField>(fields.at(1)).controller!.text, isEmpty);
      await tester.tap(find.text('Send reply'));
      await tester.pump();
      expect(calls, 1);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Sending…'))
            .onPressed,
        isNull,
      );
      result.completeError(StateError('Check previous send'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Check previous send'), findsOneWidget);
      expect(calls, 1);
    },
  );
}
