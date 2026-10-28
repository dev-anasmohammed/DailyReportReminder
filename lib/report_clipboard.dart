import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;

const _clipboard = MethodChannel('daily_report/clipboard');

String reportHtml(String today, String tomorrow, String blockers) {
  final sections = [
    ('What I have worked on today:', today),
    ('What I will work on tomorrow:', tomorrow),
    ('I have the following blockers and issues:', blockers),
  ];
  return '<div style="font-family:Arial,sans-serif;font-size:14px;line-height:1.5;color:#202124">${[for (var i = 0; i < sections.length; i++) '<p><strong>${i + 1}. ${sections[i].$1}</strong></p>${md.markdownToHtml(const HtmlEscape().convert(sections[i].$2), encodeHtml: true)}'].join('<br>')}</div>';
}

String _plainBody(String source) {
  final nodes = md.Document(encodeHtml: false).parseLines(source.split('\n'));
  String render(md.Node node) {
    if (node is md.Text) return node.text;
    if (node is! md.Element) return '';
    final text = (node.children ?? []).map(render).join();
    if (node.tag == 'li') return '- ${text.trim()}\n';
    if (node.tag == 'br') return '\n';
    if (['p', 'ul', 'ol', 'blockquote', 'h1', 'h2', 'h3'].contains(node.tag)) {
      return '$text\n';
    }
    return text;
  }

  return nodes.map(render).join().trim();
}

String reportPlainText(String today, String tomorrow, String blockers) =>
    '1. What I have worked on today:\n\n${_plainBody(today)}\n\n'
    '2. What I will work on tomorrow:\n\n${_plainBody(tomorrow)}\n\n'
    '3. I have the following blockers and issues:\n\n${_plainBody(blockers)}\n';

Future<void> copyFormattedReport(
  String today,
  String tomorrow,
  String blockers,
) => _clipboard.invokeMethod<void>('write', {
  'html': reportHtml(today, tomorrow, blockers),
  'text': reportPlainText(today, tomorrow, blockers),
});
