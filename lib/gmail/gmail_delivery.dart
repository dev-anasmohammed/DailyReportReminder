import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../report.dart';
import 'gmail_service.dart';

class GmailDelivery {
  GmailDelivery(this.gmail, this.prefs);
  final GmailService gmail;
  final SharedPreferences prefs;
  String key(DateTime day, String field) => '${dateKey(day)}.gmail.$field';
  Map<String, dynamic>? record(DateTime day, String field) {
    final raw = prefs.getString(key(day, field));
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> send(PreparedReply reply, DateTime day) async {
    if (record(day, 'sent') != null) {
      throw StateError('A report was already sent today. Check Gmail Sent.');
    }
    if (record(day, 'pending') != null) {
      throw StateError(
        'A previous send has an unconfirmed result. Check Gmail before trying again.',
      );
    }
    final pending = {
      'threadId': reply.threadId,
      'messageId': reply.messageId,
      'account': gmail.email,
      'started': DateTime.now().toIso8601String(),
    };
    if (!await prefs.setString(key(day, 'pending'), jsonEncode(pending))) {
      throw StateError('Could not save send status. Nothing was sent.');
    }
    try {
      final id = await gmail.send(reply);
      await _complete(day, {
        ...pending,
        'gmailMessageId': id,
        'sentAt': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      throw StateError(
        'Could not confirm sending. Your draft is saved. Check Gmail Sent or use Check previous send before trying again; the message may already have been sent.',
      );
    }
  }

  Future<void> _complete(DateTime day, Map<String, dynamic> record) async {
    if (!await prefs.setString(key(day, 'sent'), jsonEncode(record))) {
      throw StateError('Could not save confirmation.');
    }
    await prefs.setBool('${dateKey(day)}.completed', true);
    await prefs.remove(key(day, 'pending'));
  }

  Future<bool> checkPrevious(DateTime day) async {
    final pending = record(day, 'pending');
    if (pending == null) return record(day, 'sent') != null;
    if (pending['account'] != gmail.email) {
      throw StateError(
        'Connect the Gmail account used for the previous attempt.',
      );
    }
    final thread = await gmail.thread(pending['threadId'] as String);
    final matches = thread.messages.where(
      (m) =>
          m.header('message-id') == pending['messageId'] &&
          m.labels.contains('SENT'),
    );
    if (matches.isEmpty) return false;
    await _complete(day, {
      ...pending,
      'gmailMessageId': matches.first.id,
      'sentAt': DateTime.now().toIso8601String(),
    });
    return true;
  }

  Future<void> clearPending(DateTime day) => prefs.remove(key(day, 'pending'));
}
