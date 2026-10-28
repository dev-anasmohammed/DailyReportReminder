import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daily_report_reminder/report.dart';
import 'package:daily_report_reminder/report_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('numbering restarts per project and keeps zero padding through 10', () {
    final body = formatProjectCommits(
      'App',
      List.generate(12, (i) => 'Task ${i + 1}'),
    )!;
    expect(body, startsWith('**App:**\n01. Task 1\n02. Task 2'));
    expect(body, contains('09. Task 9\n10. Task 10\n11. Task 11'));
    expect(
      normalizeReportBody('**A/**\n- One\n- Two\n\n**B/**\n- Three'),
      '**A:**\n01. One\n02. Two\n\n**B:**\n01. Three',
    );
    final html = reportHtml('**A/**\n- One\n- Two', '', '');
    expect(html, contains('>01</td>'));
    expect(html, contains('>02</td>'));
    expect(html, isNot(contains('<ul>')));
  });
  test('old empty placeholders are removed without touching real work', () {
    const work =
        '**App/**\n- Fixed login\n\n**Empty/**\n- No commits today.\n\n**Other/**\n- Real work';
    expect(
      removeEmptyProjectSections(work),
      '**App/**\n- Fixed login\n\n**Other/**\n- Real work',
    );
    expect(
      removeEmptyProjectSections(
        '**App/**\n- No commits today.\n- Manual note',
      ),
      '**App/**\n- No commits today.\n- Manual note',
    );
  });
  test('empty projects are omitted and nonempty projects retain newlines', () {
    expect(formatProjectCommits('Empty', []), isNull);
    expect(
      formatProjectCommits('App', ['First', 'Second']),
      '**App:**\n01. First\n02. Second',
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
      expect(html, contains('<strong>App:</strong>'));
      expect(html, contains('<table role="presentation"'));
      expect(html, contains('>Fix login</td>'));
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
    expect(plain, contains('App:\n01 Fixed login'));
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
    expect(args['html'], contains('<strong>App:</strong>'));
    expect(args['text'], contains('App:\n01 Fixed'));
  });
}
