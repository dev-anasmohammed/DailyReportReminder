import 'dart:convert';
import 'dart:io';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daily_report_reminder/gmail/gmail_service.dart';
import 'package:daily_report_reminder/gmail/gmail_delivery.dart';

class RealHttpOverrides extends HttpOverrides {}

class MemoryVault implements GmailVault {
  String? value;
  MemoryVault([this.value]);
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

Map<String, dynamic> message(
  String id,
  String sender, {
  String to = 'me@example.com, Team <team@example.com>',
  String cc = 'CC <cc@example.com>',
  bool sent = false,
  int time = 1,
  String subject = 'Daily reports',
}) => {
  'id': id,
  'internalDate': '$time',
  'labelIds': [sent ? 'SENT' : 'INBOX'],
  'payload': {
    'headers': [
      {'name': 'Subject', 'value': subject},
      {'name': 'From', 'value': sender},
      {'name': 'To', 'value': to},
      {'name': 'Cc', 'value': cc},
      {'name': 'Message-ID', 'value': '<$id@example.com>'},
      {'name': 'References', 'value': '<root@example.com>'},
    ],
  },
};
GmailThread sampleThread() => GmailThread.fromJson({
  'id': 'thread-1',
  'messages': [
    message('received', '"Manager, A" <manager@example.com>'),
    message(
      'my-report',
      'me@example.com',
      to: 'manager@example.com',
      cc: 'team@example.com',
      sent: true,
      time: 2,
    ),
  ],
});
String credentials({bool expired = false}) => jsonEncode({
  'clientId': 'desktop.apps.googleusercontent.com',
  'clientSecret': 'desktop-public-value',
  'refreshToken': 'fake-refresh',
  'accessToken': 'fake-access',
  'email': 'me@example.com',
  'expires': expired
      ? 0
      : DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
});
PreparedReply sampleReply() => prepareReply(
  thread: sampleThread(),
  from: 'me@example.com',
  to: 'manager@example.com',
  cc: 'team@example.com',
  plain: '01- Finished العربية',
  html: '<strong>App:</strong><p>01- Finished العربية</p>',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'reply recipients exclude self and handle replying after our own report',
    () {
      final direct = replyRecipients(sampleThread(), 'me@example.com', false);
      expect(direct.to.map((a) => a.email), ['manager@example.com']);
      expect(direct.cc, isEmpty);
      final all = replyRecipients(sampleThread(), 'me@example.com', true);
      expect(all.to.map((a) => a.email), [
        'manager@example.com',
        'team@example.com',
      ]);
      expect(all.cc.map((a) => a.email), ['cc@example.com']);
      expect(
        parseAddresses('"Last, First" <one@example.com>, two@example.com')
            .length,
        2,
      );
      expect(
        () => parseAddresses('one@example.com\r\nBcc: other@example.com'),
        throwsFormatException,
      );
    },
  );
  test('outgoing MIME preserves subject, reply headers, Unicode and both body formats', () {
    final reply = sampleReply();
    final raw = utf8.decode(base64Url.decode(base64Url.normalize(reply.raw)));
    final mime = MimeMessage.parseFromText(raw);
    expect(mime.decodeSubject(), 'Daily reports');
    expect(mime.getHeaderValue('In-Reply-To'), '<my-report@example.com>');
    expect(mime.getHeaderValue('References'), contains('<root@example.com>'));
    expect(
      mime.getHeaderValue('References'),
      contains('<my-report@example.com>'),
    );
    expect(mime.decodeTextPlainPart(), contains('العربية'));
    expect(mime.decodeTextHtmlPart(), contains('<strong>App:</strong>'));
    expect(mime.getHeaderValue('Message-ID'), reply.messageId);
    expect(reply.threadId, 'thread-1');
  });
  test('metadata browsing uses no body access or unsupported search and send targets thread', () async {
    var sent = 0;
    final service = GmailService(
      vault: MemoryVault(credentials()),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/threads')) {
          expect(request.url.queryParameters.containsKey('q'), false);
          return http.Response(
            jsonEncode({
              'threads': [
                {'id': 'thread-1'},
              ],
              'nextPageToken': 'next',
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/threads/thread-1')) {
          expect(request.url.queryParameters['format'], 'metadata');
          expect(
            request.url.queryParametersAll['metadataHeaders'],
            contains('Message-ID'),
          );
          return http.Response(
            jsonEncode({
              'id': 'thread-1',
              'messages': [message('received', 'manager@example.com')],
            }),
            200,
          );
        }
        expect(request.method, 'POST');
        expect(request.url.path.endsWith('/messages/send'), true);
        final body = jsonDecode(request.body) as Map;
        expect(body['threadId'], 'thread-1');
        expect(body['raw'], isNotEmpty);
        sent++;
        return http.Response('{"id":"sent-id","threadId":"thread-1"}', 200);
      }),
    );
    addTearDown(service.dispose);
    await service.load();
    final page = await service.recentThreads();
    expect(page.nextPage, 'next');
    expect(page.threads.single.subject, 'Daily reports');
    expect(await service.send(sampleReply()), 'sent-id');
    expect(sent, 1);
  });
  test('concurrent requests refresh once and persist the new access token securely', () async {
    var refreshes = 0;
    final vault = MemoryVault(credentials(expired: true));
    final service = GmailService(
      vault: vault,
      client: MockClient((request) async {
        if (request.url.host == 'oauth2.googleapis.com') {
          refreshes++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return http.Response(
            '{"access_token":"renewed","expires_in":3600}',
            200,
          );
        }
        expect(request.headers['Authorization'], 'Bearer renewed');
        return http.Response('{"emailAddress":"me@example.com"}', 200);
      }),
    );
    addTearDown(service.dispose);
    await service.load();
    await Future.wait([service.get('profile'), service.get('profile')]);
    expect(refreshes, 1);
    expect(jsonDecode(vault.value!)['accessToken'], 'renewed');
  });
  test('send errors are not automatically retried', () async {
    var posts = 0;
    final service = GmailService(
      vault: MemoryVault(credentials()),
      client: MockClient((r) async {
        posts++;
        throw const SocketException('connection dropped');
      }),
    );
    addTearDown(service.dispose);
    await service.load();
    await expectLater(
      service.send(sampleReply()),
      throwsA(isA<SocketException>()),
    );
    expect(posts, 1);
  });
  test(
    'confirmation completes report and blocks duplicate daily sends',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var posts = 0;
      final service = GmailService(
        vault: MemoryVault(credentials()),
        client: MockClient((r) async {
          posts++;
          return http.Response('{"id":"sent-id","threadId":"thread-1"}', 200);
        }),
      );
      addTearDown(service.dispose);
      await service.load();
      final delivery = GmailDelivery(service, prefs);
      final day = DateTime(2026, 10, 28);
      await delivery.send(sampleReply(), day);
      expect(prefs.getBool('2026-10-28.completed'), true);
      expect(delivery.record(day, 'pending'), isNull);
      expect(delivery.record(day, 'sent')?['gmailMessageId'], 'sent-id');
      await expectLater(delivery.send(sampleReply(), day), throwsStateError);
      expect(posts, 1);
      await delivery.dismissSendBlock(day);
      expect(posts, 1);
      expect(delivery.record(day, 'sent'), isNull);
      expect(prefs.getBool('2026-10-28.completed'), true);
      await delivery.send(sampleReply(), day);
      expect(posts, 2);
    },
  );
  test('uncertain send preserves draft and pending record; metadata can confirm it', () async {
    SharedPreferences.setMockInitialValues({'2026-10-28.today': 'Draft work'});
    final prefs = await SharedPreferences.getInstance();
    final reply = sampleReply();
    final service = GmailService(
      vault: MemoryVault(credentials()),
      client: MockClient((r) async {
        if (r.method == 'POST') throw const SocketException('uncertain');
        final found = message('confirmed', 'me@example.com', sent: true);
        (found['payload']['headers'] as List).removeWhere(
          (dynamic h) => h['name'] == 'Message-ID',
        );
        (found['payload']['headers'] as List).add({
          'name': 'Message-ID',
          'value': reply.messageId,
        });
        return http.Response(
          jsonEncode({
            'id': 'thread-1',
            'messages': [found],
          }),
          200,
        );
      }),
    );
    addTearDown(service.dispose);
    await service.load();
    final delivery = GmailDelivery(service, prefs);
    final day = DateTime(2026, 10, 28);
    await expectLater(delivery.send(reply, day), throwsStateError);
    expect(prefs.getString('2026-10-28.today'), 'Draft work');
    expect(prefs.getBool('2026-10-28.completed'), isNull);
    expect(delivery.record(day, 'pending'), isNotNull);
    expect(await delivery.checkPrevious(day), true);
    expect(prefs.getBool('2026-10-28.completed'), true);
  });
  test(
    'dismiss clears an uncertain send guard without sending or deleting drafts',
    () async {
      SharedPreferences.setMockInitialValues({
        '2026-10-28.gmail.pending': jsonEncode({'threadId': 'thread-1'}),
        '2026-10-28.today': 'Draft work',
      });
      final prefs = await SharedPreferences.getInstance();
      final service = GmailService(vault: MemoryVault());
      addTearDown(service.dispose);
      final delivery = GmailDelivery(service, prefs);
      await delivery.dismissSendBlock(DateTime(2026, 10, 28));
      expect(delivery.record(DateTime(2026, 10, 28), 'pending'), isNull);
      expect(prefs.getString('2026-10-28.today'), 'Draft work');
      expect(prefs.getBool('2026-10-28.completed'), isNull);
    },
  );
  test('OAuth uses loopback, PKCE, state validation and send/header-only permissions', () async {
    final vault = MemoryVault();
    late String verifierChallenge;
    final service = GmailService(
      vault: vault,
      client: MockClient((r) async {
        if (r.url.host == 'oauth2.googleapis.com') {
          final body = Uri.splitQueryString(r.body);
          expect(pkceChallenge(body['code_verifier']!), verifierChallenge);
          return http.Response(
            jsonEncode({
              'access_token': 'fake-access',
              'refresh_token': 'fake-refresh',
              'expires_in': 3600,
              'scope': GmailService.scopes.join(' '),
            }),
            200,
          );
        }
        return http.Response('{"emailAddress":"me@example.com"}', 200);
      }),
      openBrowser: (url) async {
        expect(url.host, 'accounts.google.com');
        expect(url.queryParameters['scope'], GmailService.scopes.join(' '));
        expect(url.queryParameters['code_challenge_method'], 'S256');
        verifierChallenge = url.queryParameters['code_challenge']!;
        final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
        expect(redirect.host, '127.0.0.1');
        final wrong = await http.get(
          redirect.replace(queryParameters: {'state': 'wrong', 'code': 'bad'}),
        );
        expect(wrong.statusCode, 400);
        await http.get(
          redirect.replace(
            queryParameters: {
              'state': url.queryParameters['state']!,
              'code': 'fake-code',
            },
          ),
        );
        return true;
      },
    );
    addTearDown(service.dispose);
    await service.importClient(
      '{"installed":{"client_id":"desktop.apps.googleusercontent.com","client_secret":"public-desktop-value"}}',
    );
    await HttpOverrides.runWithHttpOverrides(
      service.connect,
      RealHttpOverrides(),
    );
    expect(service.email, 'me@example.com');
    expect(service.connected, true);
    expect(jsonDecode(vault.value!)['refreshToken'], 'fake-refresh');
    await service.disconnect();
    expect(service.connected, false);
    expect(jsonDecode(vault.value!).containsKey('refreshToken'), false);
  });
}
