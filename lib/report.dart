import 'dart:io';

String dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String clock(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
String blockersOrNone(String blockers) =>
    blockers.trim().isEmpty ? 'None' : blockers;

String? reportSendValidation(String today, String tomorrow) {
  if (today.trim().isEmpty && tomorrow.trim().isEmpty) {
    return 'Add today’s work and tomorrow’s plan before sending your report.';
  }
  if (today.trim().isEmpty) {
    return 'Add today’s work before sending your report.';
  }
  if (tomorrow.trim().isEmpty) {
    return 'Add tomorrow’s plan before sending your report.';
  }
  return null;
}

String formatReport(String today, String tomorrow, String blockers) =>
    '1. **What I have worked on today:**\n\n${today.trim()}\n\n2. **What I will work on tomorrow:**\n\n${tomorrow.trim()}\n\n3. **I have the following blockers and issues:**\n\n${blockersOrNone(blockers).trim()}\n';
Future<String> git(String path, List<String> args) async {
  try {
    final r = await Process.run('git', [
      '-C',
      path,
      ...args,
    ]).timeout(const Duration(seconds: 30));
    if (r.exitCode != 0) {
      throw StateError(r.stderr.toString().trim());
    }
    return r.stdout.toString().trim();
  } on ProcessException {
    throw StateError('Install Git and restart Daily Report.');
  }
}

Future<void> validateRepository(String path) async {
  if (await git(path, ['rev-parse', '--is-inside-work-tree']) != 'true') {
    throw StateError('Choose a Git working directory.');
  }
}

Future<List<String>> readCommits(
  String path,
  DateTime date,
  String author,
) async {
  await validateRepository(path);
  final email = author.isEmpty
      ? await git(path, ['config', 'user.email'])
      : author;
  if (email.isEmpty) {
    throw StateError('Configure your Git author email.');
  }
  final output = await git(path, [
    'log',
    '--all',
    '--format=%H%x1f%aI%x1f%ae%x1f%s%x1e',
  ]);
  final records = <({String hash, DateTime time, String subject})>[];
  for (final record in output.split('\x1e')) {
    final f = record.trim().split('\x1f');
    if (f.length != 4 || f[2].toLowerCase() != email.toLowerCase()) {
      continue;
    }
    final time = DateTime.tryParse(f[1])?.toLocal();
    if (time != null && dateKey(time) == dateKey(date)) {
      records.add((hash: f[0], time: time, subject: f[3]));
    }
  }
  records.sort((a, b) {
    final c = a.time.compareTo(b.time);
    return c == 0 ? a.hash.compareTo(b.hash) : c;
  });
  return records.map((r) => r.subject).toList();
}

String? formatProjectCommits(String project, List<String> commits) =>
    commits.isEmpty
    ? null
    : normalizeReportBody(
        '**$project:**\n${commits.map((c) => '- $c').join('\n')}',
      );

String removeEmptyProjectSections(String source) {
  final blocks = source.split(RegExp(r'\r?\n[ \t]*\r?\n'));
  final kept = blocks.where((block) {
    final lines = block.trim().split('\n').map((line) => line.trim()).toList();
    return !(lines.length == 2 &&
        lines.first.startsWith('**') &&
        lines.first.endsWith('/**') &&
        lines.last == '- No commits today.');
  }).toList();
  return kept.length == blocks.length ? source : kept.join('\n\n').trim();
}

String normalizeReportBody(String source) {
  var number = 0;
  return source
      .split('\n')
      .map((line) {
        final heading = RegExp(r'^\*\*(.+?)/\*\*\s*$').firstMatch(line.trim());
        if (heading != null) {
          number = 0;
          return '**${heading[1]}:**';
        }
        final item = RegExp(r'^(\s*)(?:[-+*]|\d+[.)-])\s+(.+)$')
            .firstMatch(line);
        if (item != null) {
          number++;
          return '${item[1]}${number.toString().padLeft(2, '0')}- ${item[2]}';
        }
        if (line.trim().isNotEmpty) number = 0;
        return line;
      })
      .join('\n');
}
