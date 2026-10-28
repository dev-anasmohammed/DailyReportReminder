import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gmail_service.dart';

class GmailSettingsScreen extends StatefulWidget {
  const GmailSettingsScreen({
    super.key,
    required this.gmail,
    required this.prefs,
  });
  final GmailService gmail;
  final SharedPreferences prefs;
  @override
  State<GmailSettingsScreen> createState() => _GmailSettingsScreenState();
}

class _GmailSettingsScreenState extends State<GmailSettingsScreen> {
  bool loading = true, connecting = false, working = false;
  String? error;
  GmailThread? selected;
  GmailService get gmail => widget.gmail;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      await gmail.load();
      if (widget.prefs.getString('gmail.thread.account') != gmail.email) {
        await widget.prefs.remove('gmail.thread.id');
      }
      final id = widget.prefs.getString('gmail.thread.id');
      if (gmail.connected && id != null) selected = await gmail.thread(id);
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      working = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> importClient() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Google OAuth client JSON',
          extensions: ['json'],
        ),
      ],
    );
    if (file == null) return;
    await run(() async {
      await gmail.importClient(await file.readAsString());
      await widget.prefs.remove('gmail.thread.id');
      selected = null;
    });
  }

  Future<void> connect() async {
    setState(() {
      connecting = true;
      error = null;
    });
    try {
      await gmail.connect();
      if (widget.prefs.getString('gmail.thread.account') != gmail.email) {
        await widget.prefs.remove('gmail.thread.id');
        selected = null;
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => connecting = false);
    }
  }

  Future<void> choose() async {
    final thread = await showDialog<GmailThread>(
      context: context,
      builder: (_) => GmailThreadPicker(gmail: gmail),
    );
    if (thread == null) return;
    await widget.prefs.setString('gmail.thread.id', thread.id);
    await widget.prefs.setString('gmail.thread.account', gmail.email);
    if (mounted) setState(() => selected = thread);
  }

  @override
  void dispose() {
    if (connecting) gmail.cancelConnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Gmail delivery')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            Text(
              'Reply with your daily report',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Connect Gmail, choose your report conversation, then preview and send a reply from your report screen.',
            ),
            const SizedBox(height: 28),
            if (loading)
              const LinearProgressIndicator()
            else ...[
              Text(
                '1. Google app setup',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Create a Google Cloud project, enable Gmail API, configure the consent screen with your account as a test user, and create an OAuth client of type Desktop app. Download its JSON and import it here. Your Gmail password is never requested by this app.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: connecting || working ? null : importClient,
                    icon: const Icon(Icons.file_open_outlined),
                    label: Text(
                      gmail.configured
                          ? 'Replace OAuth client JSON'
                          : 'Import OAuth client JSON',
                    ),
                  ),
                  TextButton(
                    onPressed: () => gmail.openBrowser(
                      Uri.parse(
                        'https://developers.google.com/identity/protocols/oauth2/native-app',
                      ),
                    ),
                    child: const Text('Google setup guide'),
                  ),
                ],
              ),
              if (gmail.configured)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Desktop OAuth client configured.',
                    style: TextStyle(color: Colors.green),
                  ),
                ),
              const Divider(height: 40),
              Text(
                '2. Gmail account',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                gmail.connected
                    ? 'Connected as ${gmail.email}'
                    : 'Not connected',
              ),
              const SizedBox(height: 10),
              const Text(
                'Requests permission to send email and read message headers. Message bodies are not downloaded. Tokens are kept in this computer’s secure storage.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                children: [
                  FilledButton(
                    onPressed: !gmail.configured || connecting || working
                        ? null
                        : connect,
                    child: Text(
                      connecting
                          ? 'Waiting for Google sign-in…'
                          : gmail.connected
                          ? 'Reconnect Gmail'
                          : 'Connect Gmail',
                    ),
                  ),
                  if (connecting)
                    TextButton(
                      onPressed: gmail.cancelConnect,
                      child: const Text('Cancel sign-in'),
                    ),
                  if (gmail.connected && !connecting)
                    TextButton(
                      onPressed: working
                          ? null
                          : () => run(() async {
                              await gmail.disconnect();
                              await widget.prefs.remove('gmail.thread.id');
                              selected = null;
                            }),
                      child: const Text('Disconnect'),
                    ),
                ],
              ),
              const Divider(height: 40),
              Text(
                '3. Report conversation',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                selected?.subject ??
                    'Choose the Gmail thread you normally reply to.',
              ),
              if (selected != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Latest message: ${selected!.latest.header('from')}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: gmail.connected && !working && !connecting
                    ? choose
                    : null,
                icon: const Icon(Icons.forum_outlined),
                label: Text(
                  selected == null
                      ? 'Choose conversation'
                      : 'Change conversation',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Reply all by default'),
                subtitle: const Text(
                  'You can review and edit To and CC before sending.',
                ),
                value: widget.prefs.getBool('gmail.replyAll') ?? false,
                onChanged: (value) async {
                  await widget.prefs.setBool('gmail.replyAll', value);
                  if (mounted) setState(() {});
                },
              ),
              const SizedBox(height: 20),
              const Text(
                'Nothing is sent from this settings screen. Use Preview & send on your report. Disconnect removes local account credentials; you can also revoke access in your Google Account settings.',
              ),
            ],
            if (working) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: SelectableText(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class GmailThreadPicker extends StatefulWidget {
  const GmailThreadPicker({super.key, required this.gmail});
  final GmailService gmail;
  @override
  State<GmailThreadPicker> createState() => _GmailThreadPickerState();
}

class _GmailThreadPickerState extends State<GmailThreadPicker> {
  final threads = <GmailThread>[];
  String filter = '';
  String? nextPage, error;
  bool loading = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final page = await widget.gmail.recentThreads(pageToken: nextPage);
      if (mounted) {
        setState(() {
          threads.addAll(page.threads);
          nextPage = page.nextPage;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final matches = threads
        .where(
          (t) => '${t.subject} ${t.latest.header('from')}'
              .toLowerCase()
              .contains(filter.toLowerCase()),
        )
        .toList();
    return AlertDialog(
      title: const Text('Choose report conversation'),
      content: SizedBox(
        width: 680,
        height: 480,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Filter loaded conversations',
                hintText: 'Subject or sender',
              ),
              onChanged: (value) => setState(() => filter = value),
            ),
            const SizedBox(height: 8),
            const Text(
              'Recent conversations, headers only. Load more to find older threads.',
              style: TextStyle(fontSize: 12),
            ),
            if (loading) const LinearProgressIndicator(),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Expanded(
              child: ListView(
                children: [
                  for (final thread in matches)
                    ListTile(
                      title: Text(
                        thread.subject.isEmpty
                            ? '(No subject)'
                            : thread.subject,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${thread.latest.header('from')}\n${thread.messages.length} messages',
                        maxLines: 2,
                      ),
                      onTap: () => Navigator.pop(context, thread),
                    ),
                  if (!loading && matches.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No matching conversations loaded.'),
                    ),
                ],
              ),
            ),
            if (nextPage != null || error != null)
              TextButton(
                onPressed: loading ? null : load,
                child: Text(
                  error == null ? 'Load more conversations' : 'Retry',
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
