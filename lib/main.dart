// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_selector/file_selector.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/window_manager.dart';

import 'report.dart';
import 'report_clipboard.dart';
import 'app_theme.dart';
import 'schedule.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';
import 'reminder_dialog.dart';
import 'reminder_sound.dart';
import 'gmail/gmail_service.dart';
import 'gmail/gmail_delivery.dart';
import 'gmail/gmail_settings_screen.dart';
import 'gmail/gmail_reply_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setTitle('Daily Report');
  await windowManager.setMinimumSize(const Size(840, 650));
  launchAtStartup.setup(
    appName: 'Daily Report',
    appPath: Platform.resolvedExecutable,
  );
  runApp(ReportApp(prefs: await SharedPreferences.getInstance()));
}

class ReportApp extends StatelessWidget {
  const ReportApp({super.key, required this.prefs});
  final SharedPreferences prefs;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Daily Report',
    theme: reportTheme(),
    home: ProfileGate(prefs: prefs),
  );
}

class ProfileGate extends StatefulWidget {
  const ProfileGate({super.key, required this.prefs});
  final SharedPreferences prefs;
  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  @override
  Widget build(BuildContext context) =>
      widget.prefs.getBool('profile.complete') == true
      ? ReportHome(prefs: widget.prefs)
      : ProfileScreen(
          prefs: widget.prefs,
          welcome: true,
          onComplete: () => setState(() {}),
        );
}

class ReportHome extends StatefulWidget {
  const ReportHome({super.key, required this.prefs});
  final SharedPreferences prefs;
  @override
  State<ReportHome> createState() => _Home();
}

class _Home extends State<ReportHome> with WindowListener, TrayListener {
  static const showHistory = false;
  final today = TextEditingController(),
      tomorrow = TextEditingController(),
      blockers = TextEditingController(),
      author = TextEditingController();
  List<String> projects = [];
  late DailySchedule schedule;
  late String day;

  bool busy = false,
      completed = false,
      startup = false,
      trayReady = false,
      checking = false,
      loading = false;
  String? error;
  GmailSendBlocked? blockedSend;
  Timer? timer;
  bool reminderVisible = false;
  final reportKey = GlobalKey();
  final gmail = GmailService();
  bool mailBusy = false;
  bool sendValidation = false;
  SharedPreferences get prefs => widget.prefs;

  @override
  void initState() {
    super.initState();
    projects = prefs.getStringList('projects') ?? [];
    author.text = prefs.getString('author') ?? '';
    schedule = DailySchedule.load(prefs);
    loadDay();
    for (final c in [today, tomorrow, blockers, author]) {
      c.addListener(save);
    }
    windowManager.addListener(this);
    trayManager.addListener(this);
    unawaited(desktop());
    timer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(tick()),
    );
  }

  void loadDay() {
    loading = true;
    day = dateKey(DateTime.now());
    final savedWork = prefs.getString('$day.today') ?? '';
    today.text = normalizeReportBody(removeEmptyProjectSections(savedWork));
    if (today.text != savedWork) {
      unawaited(prefs.setString('$day.today', today.text));
    }
    tomorrow.text = prefs.getString('$day.tomorrow') ?? '';
    blockers.text = prefs.getString('$day.blockers') ?? '';
    completed = prefs.getBool('$day.completed') ?? false;
    loading = false;
  }

  void save() {
    if (loading) {
      return;
    }
    unawaited(prefs.setString('$day.today', today.text));
    unawaited(prefs.setString('$day.tomorrow', tomorrow.text));
    unawaited(prefs.setString('$day.blockers', blockers.text));
    unawaited(prefs.setString('author', author.text));
  }

  void fail(Object e) {
    if (mounted) {
      setState(() {
        error = e.toString();
        blockedSend = e is GmailSendBlocked ? e : null;
      });
    }
  }

  Future<void> dismissError() async {
    if (mailBusy) return;
    final block = blockedSend;
    if (block != null) {
      setState(() => mailBusy = true);
      try {
        await GmailDelivery(gmail, prefs).dismissSendBlock(block.day);
      } catch (e) {
        if (mounted) setState(() => error = e.toString());
        return;
      } finally {
        if (mounted) setState(() => mailBusy = false);
      }
    }
    if (mounted) {
      setState(() {
        error = null;
        blockedSend = null;
      });
    }
  }

  Future<void> desktop() async {
    try {
      startup = await launchAtStartup.isEnabled();
      await trayManager.setIcon(
        Platform.isWindows ? 'assets/tray.ico' : 'assets/tray.png',
        isTemplate: false,
      );
      await trayManager.setToolTip('Daily Report');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'open', label: 'Open report'),
            MenuItem(key: 'leave', label: 'I am leaving now'),
            MenuItem.separator(),
            MenuItem(key: 'quit', label: 'Quit (stop reminders)'),
          ],
        ),
      );
      trayReady = true;
      await windowManager.setPreventClose(true);
      if (mounted) {
        setState(() {});
      }
      await tick();
    } catch (e) {
      fail('Desktop integration: $e');
    }
  }

  Future<void> showReport() async {
    await open();
    if (projectView && mounted) {
      setState(() => projectView = false);
      await WidgetsBinding.instance.endOfFrame;
    }
    final target = reportKey.currentContext;
    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 300),
      );
    }
  }

  Future<void> open() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onWindowClose() {
    if (reminderVisible) {
      unawaited(open());
      return;
    }
    if (trayReady) {
      unawaited(windowManager.hide());
    }
  }

  @override
  void onTrayIconMouseDown() => unawaited(open());
  @override
  void onTrayIconRightMouseDown() => unawaited(trayManager.popUpContextMenu());
  @override
  void onTrayMenuItemClick(MenuItem item) {
    if (item.key == 'quit') {
      unawaited(windowManager.destroy());
    } else {
      unawaited(showReport());
    }
  }

  Future<void> notify(String body) async {
    if (reminderVisible || !mounted) return;
    reminderVisible = true;
    bool? wasOnTop;
    ReminderAction? action;
    final sound = ReminderSound();
    try {
      wasOnTop = await windowManager.isAlwaysOnTop();
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.center();
      await windowManager.setAlwaysOnTop(true);
      await open();
      if (!mounted) return;
      unawaited(sound.start());
      action = await showDialog<ReminderAction>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ReminderDialog(message: body),
      );
    } finally {
      await sound.stop();
      reminderVisible = false;
      if (wasOnTop != null) await windowManager.setAlwaysOnTop(wasOnTop);
    }
    if (action == ReminderAction.snooze) {
      await prefs.setString(
        '$day.snooze',
        DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
      );
    } else if (action == ReminderAction.openReport && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      await showReport();
    }
  }

  Future<void> tick() async {
    if (checking) {
      return;
    }
    checking = true;
    try {
      final now = DateTime.now();
      if (day != dateKey(now)) {
        save();
        loadDay();
      }
      if (mounted) {
        setState(() {});
      }
      if (completed) {
        return;
      }
      final snooze = DateTime.tryParse(prefs.getString('$day.snooze') ?? '');
      if (snooze != null && now.isBefore(snooze)) {
        return;
      }
      final due = schedule.due(now, {
        for (final minute in schedule.reminders)
          if (prefs.getBool('$day.scheduled.$minute') ?? false) minute,
      });
      if (due.isNotEmpty || snooze != null) {
        await notify(
          'Update your report before you leave. Your workday ends at ${clock(schedule.at(now, schedule.end))}.',
        );
        if (snooze != null &&
            prefs.getString('$day.snooze') == snooze.toIso8601String()) {
          await prefs.remove('$day.snooze');
        }
        for (final i in due) {
          await prefs.setBool('$day.scheduled.$i', true);
        }
      }
    } catch (e) {
      fail('Reminder: $e');
    } finally {
      checking = false;
    }
  }

  Future<void> add() async {
    final path = await getDirectoryPath(confirmButtonText: 'Add Git project');
    if (path == null) {
      return;
    }
    try {
      await validateRepository(path);
      if (!projects.contains(path)) {
        setState(() => projects.add(path));
        await prefs.setStringList('projects', projects);
      }
    } catch (e) {
      fail(e);
    }
  }

  String name(String path) => path.split(RegExp(r'[/\\]')).last;
  Future<void> collect() async {
    if (today.text.trim().isNotEmpty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Refresh today’s work?'),
          content: const Text(
            'This replaces your work section with Git commits. Your plans and blockers stay saved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Replace work section'),
            ),
          ],
        ),
      );
      if (replace != true) {
        return;
      }
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final sections = <String>[];
      for (final path in projects) {
        final commits = await readCommits(
          path,
          DateTime.now(),
          author.text.trim(),
        );
        final section = formatProjectCommits(name(path), commits);
        if (section != null) sections.add(section);
      }
      today.text = sections.join('\n\n');
    } catch (e) {
      fail('$e\nYour existing draft was kept.');
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<bool> toggleStartup(bool value) async {
    if (value) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
    final enabled = await launchAtStartup.isEnabled();
    if (mounted) setState(() => startup = enabled);
    return enabled;
  }

  Future<void> settings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          schedule: schedule,
          startup: startup,
          onStartup: toggleStartup,
          onGmail: gmailSettings,
          onProfile: profileSettings,
          onTest: () =>
              notify('Take a moment to update your work, plans, and blockers.'),
          onSave: (value) async {
            await value.save(prefs);
            if (mounted) setState(() => schedule = value);
          },
        ),
      ),
    );
    await tick();
  }

  Future<void> profileSettings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => ProfileScreen(prefs: prefs)),
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    timer?.cancel();
    gmail.dispose();
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    for (final c in [today, tomorrow, blockers, author]) {
      c.dispose();
    }
    super.dispose();
  }

  bool projectView = false;

  Future<void> gmailSettings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => GmailSettingsScreen(gmail: gmail, prefs: prefs),
      ),
    );
  }

  Future<void> sendReport() async {
    if (mailBusy) return;
    setState(() => sendValidation = true);
    setState(() => mailBusy = true);
    final reportDay = DateTime.parse(day);
    final work = today.text, plans = tomorrow.text, issues = blockers.text;
    try {
      final validation = reportSendValidation(work, plans);
      if (validation != null) throw StateError(validation);
      await gmail.load();
      if (!mounted) return;
      final threadId = prefs.getString('gmail.thread.id');
      if (!gmail.connected ||
          threadId == null ||
          prefs.getString('gmail.thread.account') != gmail.email) {
        await gmailSettings();
        return;
      }
      final delivery = GmailDelivery(gmail, prefs);
      if (delivery.record(reportDay, 'sent') != null) {
        throw GmailSendBlocked(
          reportDay,
          'A report was already sent today. Check Gmail Sent.',
        );
      }
      if (delivery.record(reportDay, 'pending') != null) {
        if (await delivery.checkPrevious(reportDay)) {
          if (mounted) {
            setState(
              () => completed = prefs.getBool('$day.completed') ?? completed,
            );
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Previous reply confirmed in Gmail.'),
              ),
            );
          }
          return;
        }
        if (!mounted) return;
        final retry = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Previous send is unconfirmed'),
            content: const Text(
              'A matching sent message is not visible yet. Check Gmail Sent before allowing another attempt, to avoid sending your report twice.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep waiting'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('I checked Gmail; allow another attempt'),
              ),
            ],
          ),
        );
        if (retry != true) return;
        await delivery.clearPending(reportDay);
      }
      final thread = await gmail.thread(threadId);
      if (!mounted) return;
      final sent = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => GmailReplyScreen(
            thread: thread,
            account: gmail.email,
            replyAll: prefs.getBool('gmail.replyAll') ?? false,
            plain: reportPlainText(work, plans, issues),
            html: reportHtml(work, plans, issues),
            onSend: (reply) => delivery.send(reply, reportDay),
            onDismissSendBlock: () => delivery.dismissSendBlock(reportDay),
          ),
        ),
      );
      if (sent == true && mounted) {
        setState(
          () => completed = prefs.getBool('$day.completed') ?? completed,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reply sent. Today’s reminders are stopped.'),
          ),
        );
      }
    } catch (e) {
      fail(e);
    } finally {
      if (mounted) setState(() => mailBusy = false);
    }
  }

  Future<void> copyReport() async {
    try {
      await copyFormattedReport(today.text, tomorrow.text, blockers.text);
    } catch (e) {
      fail('Could not copy report: $e');
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Formatted report copied')));
    }
  }

  Widget field(
    TextEditingController controller,
    String title,
    String hint,
    int lines,
  ) => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        TextField(
          key: ValueKey(title),
          controller: controller,
          minLines: lines,
          maxLines: null,
          style: const TextStyle(fontSize: 13, height: 1.7),
          onChanged: (_) {
            if (sendValidation) setState(() {});
          },
          decoration: InputDecoration(
            hintText: hint,
            helperText: controller == today || controller == tomorrow
                ? 'Required to send'
                : null,
            errorText:
                sendValidation &&
                    (controller == today || controller == tomorrow) &&
                    controller.text.trim().isEmpty
                ? 'This field is required to send your report.'
                : null,
          ),
        ),
      ],
    ),
  );

  Widget railButton(
    IconData icon,
    String tooltip,
    VoidCallback onTap, {
    bool selected = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor: selected
            ? const Color(0xfff0f1f3)
            : Colors.transparent,
        foregroundColor: selected ? ink : muted,
        fixedSize: const Size(40, 40),
      ),
      icon: Icon(icon),
    ),
  );

  Widget projectsPanel() => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.folder_open_outlined, size: 18),
            const SizedBox(width: 9),
            const Expanded(
              child: Text(
                'Your projects',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
            Text(
              '${projects.length}',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Connect the repositories you work on.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 20),
        if (projects.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xfff8f9fb),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.create_new_folder_outlined,
                  color: Color(0xffabb6c7),
                  size: 28,
                ),
                SizedBox(height: 10),
                Text(
                  'A place for your projects',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                SizedBox(height: 4),
                Text(
                  'Add a Git folder to get started.',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ),
        for (final path in projects)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: const Color(0xffeef4ff),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.folder_outlined,
                    size: 17,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name(path),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Tooltip(
                        message: path,
                        child: Text(
                          path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, color: muted),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove project',
                  onPressed: () {
                    setState(() => projects.remove(path));
                    unawaited(prefs.setStringList('projects', projects));
                  },
                  icon: const Icon(Icons.close, size: 15),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: add,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add project folder'),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 22),
          child: Divider(),
        ),
        const Text(
          'Git identity',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: author,
          decoration: const InputDecoration(hintText: 'Your email (optional)'),
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 8),
        const Text(
          'Leave blank to use each repository’s configured email.',
          style: TextStyle(color: muted, fontSize: 11),
        ),
        const SizedBox(height: 20),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 14, color: muted),
            SizedBox(width: 7),
            Expanded(
              child: Text(
                'Commits are collected oldest first. Only your commits from today are included.',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget reportPanel() => Column(
    key: reportKey,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Today’s report',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: completed
                  ? const Color(0xffedf7f0)
                  : const Color(0xfff2f5fa),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              completed ? 'Completed' : 'Draft',
              style: TextStyle(
                fontSize: 11,
                color: completed ? const Color(0xff3e8762) : muted,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 5),
      const Text(
        'A clear record of your day. Everything saves as you type.',
        style: TextStyle(color: muted, fontSize: 12),
      ),
      const SizedBox(height: 20),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          FilledButton.icon(
            onPressed: busy || projects.isEmpty ? null : collect,
            icon: const Icon(Icons.sync, size: 16),
            label: Text(busy ? 'Reading commits…' : 'Collect today’s commits'),
          ),
          OutlinedButton.icon(
            onPressed: copyReport,
            icon: const Icon(Icons.copy_outlined, size: 15),
            label: const Text('Copy report'),
          ),
          OutlinedButton.icon(
            onPressed: mailBusy ? null : sendReport,
            icon: const Icon(Icons.send_outlined, size: 15),
            label: Text(mailBusy ? 'Preparing reply…' : 'Preview & send'),
          ),
        ],
      ),
      field(
        today,
        '1. What I have worked on today',
        '**Project X:**\n- Finished…',
        6,
      ),
      field(
        tomorrow,
        '2. What I will work on tomorrow',
        '**Project Z:**\n- I’ll finish…',
        3,
      ),
      field(blockers, '3. Blockers and issues', 'None', 2),
      const SizedBox(height: 20),
      const Divider(),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text(
          'Report completed for today',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        subtitle: const Text(
          'Stops your reminders for the rest of the day.',
          style: TextStyle(fontSize: 11, color: muted),
        ),
        value: completed,
        onChanged: (v) {
          setState(() => completed = v ?? false);
          unawaited(prefs.setBool('$day.completed', completed));
        },
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Row(
        children: [
          Container(
            width: 68,
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: line)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 22),
                Image.asset('assets/app_icon.png', width: 32, height: 32),
                const SizedBox(height: 34),
                railButton(
                  Icons.article_outlined,
                  'Daily report',
                  () => setState(() => projectView = false),
                  selected: !projectView,
                ),
                railButton(
                  Icons.folder_open_outlined,
                  'Projects',
                  () => setState(() => projectView = true),
                  selected: projectView,
                ),
                if (showHistory)
                  railButton(Icons.history_outlined, 'Saved reports', history),
                const Spacer(),
                railButton(Icons.settings_outlined, 'Settings', settings),
                const SizedBox(height: 18),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 72,
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: line)),
                  ),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => setState(() => projectView = false),
                        child: Text(
                          'Overview',
                          style: TextStyle(
                            fontWeight: !projectView
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: !projectView ? ink : muted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: () => setState(() => projectView = true),
                        child: Text(
                          'Projects',
                          style: TextStyle(color: projectView ? ink : muted),
                        ),
                      ),
                      if (showHistory) ...[
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: history,
                          child: const Text(
                            'History',
                            style: TextStyle(color: muted),
                          ),
                        ),
                      ],
                      const Spacer(),
                      const Icon(Icons.lock_outline, size: 13, color: muted),
                      const SizedBox(width: 6),
                      const Text(
                        'Local workspace',
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                      const SizedBox(width: 18),
                      Tooltip(
                        message:
                            prefs.getString('profile.name') ?? 'Your profile',
                        child: InkWell(
                          onTap: profileSettings,
                          borderRadius: BorderRadius.circular(24),
                          child: ProfileAvatar(prefs: prefs, radius: 18),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      padding: EdgeInsets.all(
                        constraints.maxWidth < 950 ? 24 : 38,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      projectView ? 'Projects' : 'Daily report',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium,
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      projectView
                                          ? 'Your connected repositories, in one place.'
                                          : '$day  /  Make room for a better end to your day.',
                                      style: const TextStyle(
                                        color: muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: showReport,
                                icon: const Icon(Icons.north_east, size: 15),
                                label: const Text('I’m leaving now'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),
                          const Divider(),
                          const SizedBox(height: 28),
                          if (error != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 20),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xfffff6f4),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: SelectableText(
                                      error!,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: mailBusy ? null : dismissError,
                                    child: const Text('Dismiss'),
                                  ),
                                ],
                              ),
                            ),
                          if (projectView)
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 620),
                              child: projectsPanel(),
                            )
                          else if (constraints.maxWidth >= 1000)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: reportPanel()),
                                const SizedBox(width: 36),
                                SizedBox(width: 300, child: projectsPanel()),
                              ],
                            )
                          else
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                projectsPanel(),
                                const SizedBox(height: 32),
                                reportPanel(),
                              ],
                            ),
                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  void history() {
    final keys = prefs.getKeys().where((k) => k.endsWith('.today')).toList()
      ..sort((a, b) => b.compareTo(a));
    final text = keys
        .map((k) {
          final d = k.substring(0, 10);
          return '$d\n${formatReport(prefs.getString(k) ?? '', prefs.getString('$d.tomorrow') ?? '', prefs.getString('$d.blockers') ?? '')}';
        })
        .join('\n\n──────────────────\n\n');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Saved report history'),
        content: SizedBox(
          width: 650,
          child: SingleChildScrollView(
            child: SelectableText(
              text.isEmpty ? 'No saved reports yet.' : text,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
