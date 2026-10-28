import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import 'gmail_service.dart';

class GmailReplyScreen extends StatefulWidget {
  const GmailReplyScreen({
    super.key,
    required this.thread,
    required this.account,
    required this.replyAll,
    required this.plain,
    required this.html,
    required this.onSend,
  });
  final GmailThread thread;
  final String account, plain, html;
  final bool replyAll;
  final Future<void> Function(PreparedReply) onSend;
  @override
  State<GmailReplyScreen> createState() => _GmailReplyScreenState();
}

class _GmailReplyScreenState extends State<GmailReplyScreen> {
  final to = TextEditingController(), cc = TextEditingController();
  late bool replyAll;
  bool sending = false;
  String? error;
  @override
  void initState() {
    super.initState();
    replyAll = widget.replyAll;
    recipients();
  }

  void recipients() {
    try {
      final result = replyRecipients(widget.thread, widget.account, replyAll);
      to.text = result.to.map((a) => a.encode()).join(', ');
      cc.text = result.cc.map((a) => a.encode()).join(', ');
    } catch (e) {
      error = e.toString();
    }
  }

  @override
  void dispose() {
    to.dispose();
    cc.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (sending) return;
    PreparedReply reply;
    try {
      reply = prepareReply(
        thread: widget.thread,
        from: widget.account,
        to: to.text,
        cc: cc.text,
        plain: widget.plain,
        html: widget.html,
      );
    } catch (e) {
      setState(() => error = e.toString());
      return;
    }
    setState(() {
      sending = true;
      error = null;
    });
    try {
      await widget.onSend(reply);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !sending,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Preview reply'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 24),
            child: FilledButton.icon(
              onPressed: sending ? null : send,
              icon: const Icon(Icons.send_outlined, size: 16),
              label: Text(sending ? 'Sending…' : 'Send reply'),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(28),
            children: [
              Text(
                widget.thread.subject,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text('From: ${widget.account}'),
              const SizedBox(height: 6),
              const Text(
                'This sends a reply in the selected conversation. Review the recipients and report below.',
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Reply all'),
                value: replyAll,
                onChanged: sending
                    ? null
                    : (value) => setState(() {
                        replyAll = value;
                        error = null;
                        recipients();
                      }),
              ),
              TextField(
                controller: to,
                enabled: !sending,
                decoration: const InputDecoration(
                  labelText: 'To',
                  helperText: 'Separate addresses with commas.',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: cc,
                enabled: !sending,
                decoration: const InputDecoration(labelText: 'CC (optional)'),
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xffe9eaed)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: HtmlWidget(widget.html, onTapUrl: (_) async => false),
              ),
              if (sending)
                const Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: LinearProgressIndicator(),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: SelectableText(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              const Text(
                'Your report is marked completed only after Gmail confirms sending.',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
