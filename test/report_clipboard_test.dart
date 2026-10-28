import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daily_report_reminder/report.dart';
import 'package:daily_report_reminder/report_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('empty projects are omitted and nonempty projects retain newlines', () {
    expect(formatProjectCommits('Empty', []), isNull);
    expect(
      formatProjectCommits('App', ['First', 'Second']),
      '**App/**\n- First\n- Second',
    );
  });
  test(
    'HTML clipboard includes headings, bold projects, bullets and safe content',
    () {
      final html = reportHtml(
        '**App/**\n- Fix login\n- Support العربية & <script>alert(1)</script>',
        '- Tests',
        '- Need API',
      );
      expect(
        html,
        contains('<strong>1. What I have worked on today:</strong>'),
      );
      expect(html, contains('<strong>App/</strong>'));
      expect(html, contains('<ul>'));
      expect(html, contains('<li>Fix login</li>'));
      expect(html, contains('العربية'));
      expect(html, contains('&lt;script&gt;'));
      expect(html, isNot(contains('<script>')));
      expect(html, isNot(contains('**')));
    },
  );
  test('plain text fallback strips Markdown without losing bullets', () {
    final plain = reportPlainText(
      '**App/**\n- Fixed **login**',
      '- Tests',
      '- Need API',
    );
    expect(plain, contains('App/\n- Fixed login'));
    expect(plain, isNot(contains('**')));
    expect(plain, contains('2. What I will work on tomorrow:'));
  });
  test('copy writes both rich and plain formats to native clipboard', () async {
    MethodCall? captured;
    const channel = MethodChannel('daily_report/clipboard');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await copyFormattedReport('**App/**\n- Fixed', '- Tests', '');
    expect(captured?.method, 'write');
    final args = captured!.arguments as Map;
    expect(args['html'], contains('<strong>App/</strong>'));
    expect(args['text'], contains('App/\n- Fixed'));
  });
}
