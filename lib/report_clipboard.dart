import 'dart:convert';

import 'report.dart';

import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;

const _clipboard = MethodChannel('daily_report/clipboard');

String reportHtml(String today, String tomorrow, String blockers) {
  final sections = [
    ('What I have worked on today:', today),
    ('What I will work on tomorrow:', tomorrow),
    ('I have the following blockers and issues:', blockers),
  ];
  return '<div style="font-family:Arial,sans-serif;font-size:14px;line-height:1.5;color:#202124">${[for (var i = 0; i < sections.length; i++) '<p><strong>${i + 1}. ${sections[i].$1}</strong></p>${_htmlBody(sections[i].$2)}'].join('<br>')}</div>';
}

String _plainBody(String source) {
  final nodes = md.Document(encodeHtml: false)
      .parseLines(_listSource(source).split('\n'));
  String render(md.Node node) {
    if (node is md.Text) return node.text;
    if (node is! md.Element) return '';
    final text = (node.children ?? []).map(render).join();
    if (node.tag == 'ul' || node.tag == 'ol') {
      final items = (node.children ?? [])
          .whereType<md.Element>()
          .where((e) => e.tag == 'li')
          .toList();
      return '${[for (var i = 0; i < items.length; i++) '${(i + 1).toString().padLeft(2, '0')}- ${render(items[i]).trim()}'].join('\n')}\n';
    }
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

String _htmlBody(String source) {
  final nodes = md.Document(encodeHtml: true)
      .parseLines(const HtmlEscape().convert(_listSource(source)).split('\n'));
  String render(md.Node node) {
    if (node is md.Text) return node.text;
    if (node is! md.Element) return '';
    if (node.tag == 'ul' || node.tag == 'ol') {
      final items = (node.children ?? [])
          .whereType<md.Element>()
          .where((e) => e.tag == 'li')
          .toList();
      return '<table role="presentation" style="border-collapse:collapse;margin:8px 0 16px 12px">${[for (var i = 0; i < items.length; i++) '<tr><td style="vertical-align:top;padding:2px 12px 2px 0;white-space:nowrap">${(i + 1).toString().padLeft(2, '0')}-</td><td style="vertical-align:top;padding:2px 0">${render(items[i])}</td></tr>'].join()}</table>';
    }
    final content = (node.children ?? []).map(render).join();
    if (node.tag == 'li') return content;
    if (node.tag == 'br' || node.tag == 'hr') return '<${node.tag}>';
    return '<${node.tag}${node.tag == 'p' ? ' style="margin:0 0 8px"' : ''}>$content</${node.tag}>';
  }

  return nodes.map(render).join();
}

String _listSource(String source) => normalizeReportBody(source)
    .replaceAllMapped(
      RegExp(r'^([ \t]*)\d+[.-]\s+', multiLine: true),
      (match) => '${match[1]}- ',
    );
