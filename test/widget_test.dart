import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:daily_report_reminder/report.dart';

void main() {
  test('report retains three sections and project formatting', () {
    final report = formatReport(
      '**App/**\n- Finished login',
      '**App/**\n- Tests',
      '- Need API',
    );
    expect(report, contains('1. **What I have worked on today:**'));
    expect(report, contains('2. **What I will work on tomorrow:**'));
    expect(
      report,
      contains('3. **I have the following blockers and issues:**'),
    );
    expect(report, contains('**App/**\n- Finished login'));
  });
  test(
    'collect exact author and local day across branches oldest first',
    () async {
      final dir = await Directory.systemTemp.createTemp('daily-report-test-');
      try {
        await git(dir.path, ['init']);
        await git(dir.path, ['config', 'user.name', 'Test']);
        await git(dir.path, ['config', 'user.email', 'me@example.com']);
        final date = DateTime(2026, 10, 28);
        Future<void> commit(String subject, String email, DateTime time) async {
          final r = await Process.run(
            'git',
            [
              '-C',
              dir.path,
              '-c',
              'commit.gpgsign=false',
              'commit',
              '--allow-empty',
              '-m',
              subject,
            ],
            environment: {
              'GIT_AUTHOR_NAME': 'Test',
              'GIT_AUTHOR_EMAIL': email,
              'GIT_AUTHOR_DATE': time.toIso8601String(),
              'GIT_COMMITTER_DATE': time.toIso8601String(),
            },
          );
          expect(r.exitCode, 0, reason: r.stderr.toString());
        }

        await commit(
          'Yesterday',
          'me@example.com',
          date.subtract(const Duration(hours: 1)),
        );
        await commit(
          'Later',
          'me@example.com',
          date.add(const Duration(hours: 14)),
        );
        await git(dir.path, ['branch', 'other']);
        await commit(
          'Wrong author',
          'other@example.com',
          date.add(const Duration(hours: 15)),
        );
        await git(dir.path, ['checkout', 'other']);
        await commit(
          'Earlier',
          'me@example.com',
          date.add(const Duration(hours: 9)),
        );
        expect(await readCommits(dir.path, date, ''), ['Earlier', 'Later']);
        expect(await readCommits(dir.path, date, 'other@example.com'), [
          'Wrong author',
        ]);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
