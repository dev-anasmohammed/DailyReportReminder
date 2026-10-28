import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

abstract class GmailVault {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class SecureGmailVault implements GmailVault {
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  static const key = 'daily_report_gmail_v1';
  @override
  Future<String?> read() => storage.read(key: key);
  @override
  Future<void> write(String value) => storage.write(key: key, value: value);
  @override
  Future<void> delete() => storage.delete(key: key);
}

String randomToken() =>
    base64UrlEncode(List.generate(32, (_) => Random.secure().nextInt(256)))
        .replaceAll('=', '');
String pkceChallenge(String verifier) =>
    base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
String cleanHeader(String value) {
  if (value.contains(RegExp(r'[\r\n\x00]'))) {
    throw const FormatException('Email headers must not contain line breaks.');
  }
  return value.trim();
}

List<MailAddress> parseAddresses(String value) {
  cleanHeader(value);
  if (value.trim().isEmpty) return [];
  final message = MimeMessage.parseFromText('To: $value\r\n\r\n');
  final addresses = message.decodeHeaderMailAddressValue('to') ?? [];
  if (addresses.isEmpty ||
      addresses.any(
        (a) =>
            !RegExp(r'^[^\s<>@,;]+@[^\s<>@,;]+\.[^\s<>@,;]+$')
                .hasMatch(a.email),
      )) {
    throw const FormatException(
      'Enter valid email addresses separated by commas.',
    );
  }
  return addresses;
}

String decodeSubject(String value) {
  cleanHeader(value);
  return (MimeMessage.parseFromText('Subject: $value\r\n\r\n'))
          .decodeSubject() ??
      value;
}

class GmailMessage {
  GmailMessage({
    required this.id,
    required this.headers,
    required this.time,
    required this.labels,
  });
  final String id;
  final Map<String, String> headers;
  final int time;
  final List<String> labels;
  String header(String name) => headers[name.toLowerCase()] ?? '';
  factory GmailMessage.fromJson(Map<String, dynamic> data) => GmailMessage(
    id: data['id'] as String,
    time: int.tryParse('${data['internalDate']}') ?? 0,
    labels: (data['labelIds'] as List? ?? []).cast<String>(),
    headers: {
      for (final h in (data['payload']?['headers'] as List? ?? []))
        (h['name'] as String).toLowerCase(): h['value'] as String,
    },
  );
}

class GmailThread {
  GmailThread({required this.id, required this.messages});
  final String id;
  final List<GmailMessage> messages;
  String get subject => decodeSubject(messages.first.header('subject'));
  GmailMessage get latest => messages.last;
  factory GmailThread.fromJson(Map<String, dynamic> data) {
    final messages =
        (data['messages'] as List? ?? [])
            .map((m) => GmailMessage.fromJson(m as Map<String, dynamic>))
            .where((m) => !m.labels.contains('DRAFT'))
            .toList()
          ..sort((a, b) => a.time.compareTo(b.time));
    if (messages.isEmpty) {
      throw const FormatException(
        'This conversation has no sent or received messages.',
      );
    }
    return GmailThread(id: data['id'] as String, messages: messages);
  }
}

class ThreadPage {
  const ThreadPage(this.threads, this.nextPage);
  final List<GmailThread> threads;
  final String? nextPage;
}

class ReplyRecipients {
  const ReplyRecipients(this.to, this.cc);
  final List<MailAddress> to, cc;
}

ReplyRecipients replyRecipients(
  GmailThread thread,
  String ownEmail,
  bool replyAll,
) {
  final own = ownEmail.toLowerCase();
  // Use the latest received message; replying to our own last report must not
  // replace the manager with ourselves as the recipient.
  final received = thread.messages
      .where(
        (m) =>
            !m.labels.contains('SENT') &&
            !parseAddresses(m.header('from'))
                .any((a) => a.email.toLowerCase() == own),
      )
      .toList();
  final parent = received.isEmpty ? thread.latest : received.last;
  final from = parseAddresses(
    parent.header('reply-to').isEmpty
        ? parent.header('from')
        : parent.header('reply-to'),
  );
  final fromSelf =
      parent.labels.contains('SENT') ||
      from.any((a) => a.email.toLowerCase() == own);
  final to = <MailAddress>[], cc = <MailAddress>[];
  final seen = <String>{own};
  void add(List<MailAddress> values, List<MailAddress> target) {
    for (final a in values) {
      if (seen.add(a.email.toLowerCase())) target.add(a);
    }
  }

  add(fromSelf ? parseAddresses(parent.header('to')) : from, to);
  if (replyAll) {
    if (!fromSelf) add(parseAddresses(parent.header('to')), to);
    add(parseAddresses(parent.header('cc')), cc);
  }
  if (to.isEmpty) {
    throw const FormatException(
      'No reply recipient found. Check this conversation in Gmail.',
    );
  }
  return ReplyRecipients(to, cc);
}

class PreparedReply {
  const PreparedReply({
    required this.threadId,
    required this.messageId,
    required this.subject,
    required this.to,
    required this.cc,
    required this.raw,
  });
  final String threadId, messageId, subject, raw;
  final List<MailAddress> to, cc;
}

PreparedReply prepareReply({
  required GmailThread thread,
  required String from,
  required String to,
  required String cc,
  required String plain,
  required String html,
  String? messageId,
}) {
  final recipients = parseAddresses(to), copies = parseAddresses(cc);
  if (recipients.isEmpty) {
    throw const FormatException('Add at least one To recipient.');
  }
  final parent = thread.latest;
  final parentId = cleanHeader(parent.header('message-id'));
  if (!RegExp(r'^<[^\s<>]+>$').hasMatch(parentId)) {
    throw const FormatException(
      'The conversation is missing a valid Message-ID. Choose another conversation.',
    );
  }
  final references = cleanHeader(parent.header('references'));
  final refs = RegExp(r'<[^\s<>]+>')
      .allMatches(references)
      .map((m) => m[0]!)
      .toList();
  if (!refs.contains(parentId)) refs.add(parentId);
  final subject = cleanHeader(thread.subject);
  final builder =
      MessageBuilder.prepareMultipartAlternativeMessage(
          plainText: plain,
          htmlText: html,
        )
        ..from = [MailAddress(null, cleanHeader(from))]
        ..to = recipients
        ..cc = copies
        ..subject = subject
        ..messageId = (messageId ?? '<${randomToken()}@dailyreport.local>');
  builder.setHeader('In-Reply-To', parentId);
  builder.setHeader('References', refs.join(' '));
  final mime = builder.buildMimeMessage().renderMessage();
  return PreparedReply(
    threadId: thread.id,
    messageId: builder.messageId!,
    subject: subject,
    to: recipients,
    cc: copies,
    raw: base64UrlEncode(utf8.encode(mime)).replaceAll('=', ''),
  );
}

class GmailService {
  GmailService({
    http.Client? client,
    GmailVault? vault,
    Future<bool> Function(Uri)? openBrowser,
  }) : client = client ?? http.Client(),
       vault = vault ?? SecureGmailVault(),
       openBrowser =
           openBrowser ??
           ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));
  final http.Client client;
  final GmailVault vault;
  final Future<bool> Function(Uri) openBrowser;
  static const scopes = [
    'https://www.googleapis.com/auth/gmail.metadata',
    'https://www.googleapis.com/auth/gmail.send',
  ];
  Map<String, dynamic> _data = {};
  Future<void>? _refreshing;
  HttpServer? _server;
  Completer<String>? _authorization;
  bool get configured => (_data['clientId'] as String? ?? '').isNotEmpty;
  bool get connected => (_data['refreshToken'] as String? ?? '').isNotEmpty;
  String get email => _data['email'] as String? ?? '';
  String get clientId => _data['clientId'] as String? ?? '';
  Future<void> load() async {
    final raw = await vault.read();
    _data = raw == null ? {} : jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> _save() => vault.write(jsonEncode(_data));
  Future<void> importClient(String source) async {
    final root = jsonDecode(source) as Map<String, dynamic>;
    final installed = root['installed'];
    if (installed is! Map ||
        installed['client_id'] is! String ||
        !(installed['client_id'] as String).endsWith(
          '.apps.googleusercontent.com',
        )) {
      throw const FormatException(
        'Choose the JSON downloaded for a Google OAuth Desktop app client.',
      );
    }
    await vault.write(
      jsonEncode({
        'clientId': installed['client_id'],
        'clientSecret': installed['client_secret'] ?? '',
      }),
    );
    await load();
  }

  Future<Map<String, dynamic>> _json(http.Response response) async {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) {
        throw StateError(
          'Gmail sign-in expired. Disconnect and connect again.',
        );
      }
      if (response.statusCode == 403) {
        throw StateError(
          'Gmail access was denied. Enable Gmail API and allow the requested permissions, or check your organization policy.',
        );
      }
      if (response.statusCode == 404) {
        throw StateError(
          'This Gmail conversation is no longer available. Choose another thread.',
        );
      }
      throw StateError(
        'Google request failed (${response.statusCode}). Try again later.',
      );
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  void cancelConnect() {
    final pending = _authorization;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('Google sign-in cancelled.'));
    }
  }

  Future<void> connect() async {
    if (!configured) {
      throw StateError('Import your Google OAuth Desktop client JSON first.');
    }
    if (_authorization != null) {
      throw StateError('Sign-in is already in progress.');
    }
    final verifier = randomToken(), state = randomToken();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    final pending = Completer<String>();
    _authorization = pending;
    final redirect = 'http://127.0.0.1:${server.port}/oauth2/callback';
    server.listen((request) async {
      if (request.method != 'GET' || request.uri.path != '/oauth2/callback') {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      if (request.uri.queryParameters['state'] != state) {
        request.response.statusCode = 400;
        request.response.write('Invalid sign-in state.');
        await request.response.close();
        return;
      }
      final code = request.uri.queryParameters['code'];
      request.response.headers.contentType = ContentType.text;
      request.response.write(
        code == null
            ? 'Sign-in was not completed. Return to Daily Report.'
            : 'You can close this tab and return to Daily Report.',
      );
      await request.response.close();
      if (!pending.isCompleted) {
        if (code == null) {
          pending.completeError(StateError('Google sign-in was declined.'));
        } else {
          pending.complete(code);
        }
      }
    });
    // Install a timeout/error handler before opening the browser.
    final result = pending.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () => throw StateError('Google sign-in timed out. Try again.'),
    );
    result.ignore(); // Also handle cancellation while the browser is opening.
    try {
      final launched = await openBrowser(
        Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
          'client_id': clientId,
          'redirect_uri': redirect,
          'response_type': 'code',
          'scope': scopes.join(' '),
          'code_challenge': pkceChallenge(verifier),
          'code_challenge_method': 'S256',
          'state': state,
          'access_type': 'offline',
          'prompt': 'consent select_account',
        }),
      );
      if (!launched) {
        cancelConnect();
      }
      final code = await result;
      final response = await client
          .post(
            Uri.https('oauth2.googleapis.com', '/token'),
            body: {
              'client_id': clientId,
              'client_secret': '${_data['clientSecret'] ?? ''}',
              'code': code,
              'code_verifier': verifier,
              'redirect_uri': redirect,
              'grant_type': 'authorization_code',
            },
          )
          .timeout(const Duration(seconds: 30));
      final token = await _json(response);
      final granted = (token['scope'] as String? ?? '').split(' ');
      if (!scopes.every(granted.contains) || token['refresh_token'] == null) {
        throw StateError(
          'Google did not grant the required permissions. Reconnect and allow both Gmail permissions.',
        );
      }
      _data = {
        ..._data,
        'accessToken': token['access_token'],
        'refreshToken': token['refresh_token'],
        'expires': DateTime.now()
            .add(Duration(seconds: (token['expires_in'] as int? ?? 3600) - 60))
            .millisecondsSinceEpoch,
      };
      try {
        final profile = await get('profile');
        _data['email'] = profile['emailAddress'];
        await _save();
      } catch (_) {
        _data.remove('accessToken');
        _data.remove('refreshToken');
        rethrow;
      }
    } finally {
      if (!pending.isCompleted) {
        pending.completeError(StateError('Google sign-in cancelled.'));
      }
      await server.close(force: true);
      _server = null;
      _authorization = null;
    }
  }

  Future<void> disconnect() async {
    cancelConnect();
    final config = {
      'clientId': _data['clientId'],
      'clientSecret': _data['clientSecret'],
    };
    await vault.write(jsonEncode(config));
    _data = config;
  }

  Future<void> _refresh() async {
    if (!connected) throw StateError('Connect your Gmail account first.');
    if ((_data['expires'] as int? ?? 0) >
            DateTime.now().millisecondsSinceEpoch &&
        _data['accessToken'] != null) {
      return;
    }
    final response = await client
        .post(
          Uri.https('oauth2.googleapis.com', '/token'),
          body: {
            'client_id': clientId,
            'client_secret': '${_data['clientSecret'] ?? ''}',
            'refresh_token': '${_data['refreshToken']}',
            'grant_type': 'refresh_token',
          },
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 400) {
      throw StateError(
        'Google sign-in expired or was revoked. Disconnect and connect again.',
      );
    }
    final token = await _json(response);
    _data['accessToken'] = token['access_token'];
    _data['expires'] = DateTime.now()
        .add(Duration(seconds: (token['expires_in'] as int? ?? 3600) - 60))
        .millisecondsSinceEpoch;
    await _save();
  }

  Future<String> _accessToken() async {
    final refreshing = _refreshing ??= _refresh();
    try {
      await refreshing;
    } finally {
      if (identical(_refreshing, refreshing)) _refreshing = null;
    }
    return _data['accessToken'] as String;
  }

  Future<Map<String, dynamic>> get(
    String path, [
    Map<String, dynamic>? query,
  ]) async {
    final token = await _accessToken();
    return _json(
      await client
          .get(
            Uri.https(
              'gmail.googleapis.com',
              '/gmail/v1/users/me/$path',
              query,
            ),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 30)),
    );
  }

  Future<GmailThread> thread(String id) async => GmailThread.fromJson(
    await get('threads/${Uri.encodeComponent(id)}', {
      'format': 'metadata',
      'metadataHeaders': [
        'Subject',
        'From',
        'To',
        'Cc',
        'Reply-To',
        'Message-ID',
        'References',
      ],
    }),
  );
  Future<ThreadPage> recentThreads({String? pageToken}) async {
    final data = await get('threads', {
      'maxResults': '15',
      'pageToken': ?pageToken,
    });
    final threads = <GmailThread>[];
    // Keep requests bounded; each page can be filtered locally by subject/sender.
    for (final entry in data['threads'] as List? ?? []) {
      try {
        threads.add(await thread(entry['id'] as String));
      } on FormatException {
        /* A draft-only thread is not a reply target. */
      }
    }
    return ThreadPage(threads, data['nextPageToken'] as String?);
  }

  Future<String> send(PreparedReply reply) async {
    final token = await _accessToken();
    // Never automatically retry this POST: a timeout may still mean it sent.
    final response = await client
        .post(
          Uri.https('gmail.googleapis.com', '/gmail/v1/users/me/messages/send'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'threadId': reply.threadId, 'raw': reply.raw}),
        )
        .timeout(const Duration(seconds: 45));
    final data = await _json(response);
    if (data['id'] is! String || data['threadId'] != reply.threadId) {
      throw StateError(
        'Gmail could not confirm the reply in the selected conversation. Check Sent in Gmail.',
      );
    }
    return data['id'] as String;
  }

  void dispose() {
    cancelConnect();
    unawaited(_server?.close(force: true));
    client.close();
  }
}
