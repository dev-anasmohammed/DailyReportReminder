// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_selector/file_selector.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/window_manager.dart';

import 'report.dart';

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
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff22665c)),
      scaffoldBackgroundColor: const Color(0xfff4f7f6),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    home: ReportHome(prefs: prefs),
  );
}

class ReportHome extends StatefulWidget {
  const ReportHome({super.key, required this.prefs});
  final SharedPreferences prefs;
  @override
  State<ReportHome> createState() => _Home();
}

class _Home extends State<ReportHome> with WindowListener, TrayListener {
  final today = TextEditingController(),
      tomorrow = TextEditingController(),
      blockers = TextEditingController(),
      author = TextEditingController();
  List<String> projects = [];
  late DateTime start;
  late String day;
  int first = 240, before = 30;
  bool busy = false,
      completed = false,
      startup = false,
      trayReady = false,
      checking = false,
      loading = false;
  String? error;
  Timer? timer;
  final notifications = <LocalNotification>[];
  final reportKey = GlobalKey();
  SharedPreferences get prefs => widget.prefs;
  DateTime get end => start.add(const Duration(hours: 8));
  @override
  void initState() {
    super.initState();
    projects = prefs.getStringList('projects') ?? [];
    author.text = prefs.getString('author') ?? '';
    first = prefs.getInt('first') ?? 240;
    before = prefs.getInt('before') ?? 30;
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

  void loadDay({DateTime? suggested}) {
    loading = true;
    day = dateKey(DateTime.now());
    start =
        DateTime.tryParse(prefs.getString('$day.start') ?? '') ??
        suggested ??
        DateTime.now();
    today.text = prefs.getString('$day.today') ?? '';
    tomorrow.text = prefs.getString('$day.tomorrow') ?? '';
    blockers.text = prefs.getString('$day.blockers') ?? '';
    completed = prefs.getBool('$day.completed') ?? false;
    unawaited(prefs.setString('$day.start', start.toIso8601String()));
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
      setState(() => error = e.toString());
    }
  }

  Future<void> desktop() async {
    try {
      await localNotifier.setup(
        appName: 'Daily Report',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      startup = await launchAtStartup.isEnabled();
      await trayManager.setIcon(
        Platform.isWindows ? 'assets/tray.ico' : 'assets/tray.png',
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
    final n = LocalNotification(
      title: 'Your daily report',
      body: body,
      actions: [
        LocalNotificationAction(text: 'Open report'),
        LocalNotificationAction(text: 'Snooze 10 min'),
      ],
    );
    n.onClick = () => unawaited(open());
    n.onClickAction = (index) {
      if (index == 0) {
        unawaited(open());
      } else {
        unawaited(
          prefs.setString(
            '$day.snooze',
            DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
          ),
        );
      }
    };
    notifications.add(n);
    await n.show();
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
        loadDay(
          suggested: DateTime(
            now.year,
            now.month,
            now.day,
            start.hour,
            start.minute,
          ),
        );
      }
      if (mounted) {
        setState(() {});
      }
      if (completed) {
        return;
      }
      final snooze = DateTime.tryParse(prefs.getString('$day.snooze') ?? '');
      if (snooze != null) {
        if (now.isBefore(snooze)) {
          return;
        }
        await notify('Your snoozed report reminder is due.');
        await prefs.remove('$day.snooze');
      }
      final due = dueReminders(now, start, first, before, {
        for (var i = 0; i < 2; i++)
          if (prefs.getBool('$day.reminder$i') ?? false) i,
      });
      if (due.isNotEmpty) {
        await notify(
          'Update your report before you leave. Your workday ends at ${clock(end)}.',
        );
        for (final i in due) {
          await prefs.setBool('$day.reminder$i', true);
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
        sections.add(
          '**${name(path)}/**\n${commits.isEmpty ? '- No commits today.' : commits.map((c) => '- $c').join('\n')}',
        );
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

  Future<void> changeStart() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(start),
    );
    if (t == null) {
      return;
    }
    setState(
      () => start = DateTime(
        start.year,
        start.month,
        start.day,
        t.hour,
        t.minute,
      ),
    );
    await prefs.setString('$day.start', start.toIso8601String());
    await tick();
  }

  Future<void> toggleStartup(bool v) async {
    try {
      if (v) {
        await launchAtStartup.enable();
      } else {
        await launchAtStartup.disable();
      }
      final enabled = await launchAtStartup.isEnabled();
      if (mounted) {
        setState(() => startup = enabled);
      }
    } catch (e) {
      fail('Could not change startup: $e');
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    for (final c in [today, tomorrow, blockers, author]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget panel(String title, List<Widget> children) => Card(
    elevation: 0,
    color: Colors.white,
    key: title == 'Your report' ? reportKey : null,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    ),
  );
  Widget field(TextEditingController c, String label, String hint, int lines) =>
      Padding(
        padding: const EdgeInsets.only(top: 20),
        child: TextField(
          controller: c,
          minLines: lines,
          maxLines: null,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            alignLabelWithHint: true,
          ),
        ),
      );
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(32),
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_motion, size: 36),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Make your work count.',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text('Daily Report / $day / Saved on this computer'),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: showReport,
                icon: const Icon(Icons.logout),
                label: const Text('I’m leaving now'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(child: SelectableText(error!)),
                    IconButton(
                      onPressed: () => setState(() => error = null),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
          panel('Your workday', [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Start ${clock(start)} → Finish ${clock(end)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                OutlinedButton(
                  onPressed: changeStart,
                  child: const Text('Change start'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Eight hours from your start time. Today’s first launch suggests your start; adjust it if needed. Reminders run on days you use the app.',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: first,
                    decoration: const InputDecoration(
                      labelText: 'First reminder after starting',
                    ),
                    items: [120, 180, 240, 300, 360]
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text('${v ~/ 60} hours'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => first = v);
                        unawaited(prefs.setInt('first', v));
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: before,
                    decoration: const InputDecoration(
                      labelText: 'Second reminder before finishing',
                    ),
                    items: [0, 15, 30, 60]
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text('$v minutes'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => before = v);
                        unawaited(prefs.setInt('before', v));
                      }
                    },
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Open when I sign in'),
              value: startup,
              onChanged: toggleStartup,
            ),
            TextButton.icon(
              onPressed: () async {
                try {
                  await notify(
                    'Test reminder — your report is one click away.',
                  );
                } catch (e) {
                  fail(e);
                }
              },
              icon: const Icon(Icons.notifications_outlined),
              label: const Text('Test notification'),
            ),
            TextButton(
              onPressed: () async {
                await prefs.setString(
                  '$day.snooze',
                  DateTime.now()
                      .add(const Duration(minutes: 10))
                      .toIso8601String(),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Reminder snoozed for 10 minutes'),
                    ),
                  );
                }
              },
              child: const Text('Remind me in 10 minutes'),
            ),
            const Text(
              'Closing the window keeps reminders running in the tray. Quit from the tray to stop them.',
            ),
          ]),
          panel('Your projects', [
            for (final path in projects)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_outlined),
                title: Text(name(path)),
                subtitle: Text(path),
                trailing: IconButton(
                  tooltip: 'Remove project',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() => projects.remove(path));
                    unawaited(prefs.setStringList('projects', projects));
                  },
                ),
              ),
            OutlinedButton.icon(
              onPressed: add,
              icon: const Icon(Icons.add),
              label: const Text('Add project folder'),
            ),
            field(
              author,
              'Git author email (optional)',
              'Blank uses each repository’s configured email.',
              1,
            ),
            const SizedBox(height: 12),
            const Text(
              'Your commits across local branches, oldest first, using today’s local date. Git must be installed.',
            ),
          ]),
          panel('Your report', [
            Row(
              children: [
                FilledButton.icon(
                  onPressed: busy || projects.isEmpty ? null : collect,
                  icon: const Icon(Icons.sync),
                  label: Text(
                    busy ? 'Reading commits…' : 'Collect today’s commits',
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(
                        text: formatReport(
                          today.text,
                          tomorrow.text,
                          blockers.text,
                        ),
                      ),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Report copied as Markdown'),
                        ),
                      );
                    }
                  },
                  child: const Text('Copy report'),
                ),
              ],
            ),
            field(
              today,
              '1. What I have worked on today',
              '**Project X/**\n- Finished…',
              5,
            ),
            field(
              tomorrow,
              '2. What I will work on tomorrow',
              '**Project Z/**\n- I’ll finish…',
              3,
            ),
            field(
              blockers,
              '3. Blockers and issues',
              '- I need…\n- I faced…',
              2,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Report completed for today'),
              subtitle: const Text(
                'Stops today’s reminders. Copy your report to share it.',
              ),
              value: completed,
              onChanged: (v) {
                setState(() => completed = v ?? false);
                unawaited(prefs.setBool('$day.completed', completed));
              },
            ),
            TextButton(
              onPressed: history,
              child: const Text('View saved reports'),
            ),
          ]),
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
