// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_selector/file_selector.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/window_manager.dart';

import 'report.dart';
import 'schedule.dart';
import 'settings_screen.dart';
import 'reminder_dialog.dart';

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
  late DailySchedule schedule;
  late String day;

  bool busy = false,
      completed = false,
      startup = false,
      trayReady = false,
      checking = false,
      loading = false;
  String? error;
  Timer? timer;
  bool reminderVisible = false;
  final reportKey = GlobalKey();
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
    today.text = prefs.getString('$day.today') ?? '';
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
      setState(() => error = e.toString());
    }
  }

  Future<void> desktop() async {
    try {
      startup = await launchAtStartup.isEnabled();
      await trayManager.setIcon(
        Platform.isWindows ? 'assets/tray.ico' : 'assets/tray.png',
        isTemplate: Platform.isMacOS,
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
    try {
      wasOnTop = await windowManager.isAlwaysOnTop();
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.center();
      await windowManager.setAlwaysOnTop(true);
      await open();
      if (!mounted) return;
      action = await showDialog<ReminderAction>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ReminderDialog(message: body),
      );
    } finally {
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
              Image.asset('assets/app_icon.png', width: 36, height: 36),
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
              IconButton(
                tooltip: 'Settings',
                onPressed: settings,
                icon: const Icon(Icons.settings_outlined),
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
