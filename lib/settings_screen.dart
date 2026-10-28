import 'package:flutter/material.dart';

import 'schedule.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.schedule,
    required this.startup,
    required this.onStartup,
    required this.onTest,
    required this.onSave,
    this.onGmail,
    this.onProfile,
  });
  final Future<void> Function()? onProfile;
  final Future<void> Function()? onGmail;
  final DailySchedule schedule;
  final bool startup;
  final Future<bool> Function(bool) onStartup;
  final Future<void> Function() onTest;
  final Future<void> Function(DailySchedule) onSave;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int start, end;
  late List<int> reminders;
  late bool startup;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    start = widget.schedule.start;
    end = widget.schedule.end;
    reminders = [...widget.schedule.reminders];
    startup = widget.startup;
  }

  String label(int m) =>
      TimeOfDay(hour: m ~/ 60, minute: m % 60).format(context);
  Future<int?> pick(int value) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: value ~/ 60, minute: value % 60),
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }

  Future<void> save() async {
    final schedule = DailySchedule(
      start: start,
      end: end,
      reminders: [...reminders]..sort(),
    );
    if (schedule.validationError != null) {
      setState(() => error = schedule.validationError);
      return;
    }
    setState(() => saving = true);
    try {
      await widget.onSave(schedule);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 850),
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            if (widget.onProfile != null) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: const Text('Your profile'),
                subtitle: const Text(
                  'Change your name, replace your photo, or remove it.',
                ),
                trailing: OutlinedButton(
                  onPressed: widget.onProfile,
                  child: const Text('Edit profile'),
                ),
              ),
              const Divider(height: 40),
            ],
            if (widget.onGmail != null) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.mail_outline),
                title: const Text('Gmail delivery'),
                subtitle: const Text(
                  'Connect your account and choose the report conversation.',
                ),
                trailing: OutlinedButton(
                  onPressed: widget.onGmail,
                  child: const Text('Configure Gmail'),
                ),
              ),
              const Divider(height: 40),
            ],
            Text(
              'Working hours',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Your daily schedule. Reminder times stay fixed regardless of when you open the app.',
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Start working'),
              trailing: OutlinedButton(
                onPressed: () async {
                  final v = await pick(start);
                  if (v != null && mounted) setState(() => start = v);
                },
                child: Text(label(start)),
              ),
            ),
            ListTile(
              title: const Text('Finish working'),
              trailing: OutlinedButton(
                onPressed: () async {
                  final v = await pick(end);
                  if (v != null && mounted) setState(() => end = v);
                },
                child: Text(label(end)),
              ),
            ),
            const Divider(height: 40),
            Text('Reminders', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
              'Add as many reminders as you need. Times use this computer’s local timezone.',
            ),
            if (reminders.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No scheduled reminders. Add one to get started.'),
              ),
            for (var i = 0; i < reminders.length; i++)
              ListTile(
                key: ValueKey('reminder-$i'),
                leading: const Icon(Icons.notifications_outlined),
                title: Text('Reminder ${i + 1}'),
                subtitle: Text(label(reminders[i])),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () async {
                        final v = await pick(reminders[i]);
                        if (v != null && mounted) {
                          setState(() => reminders[i] = v);
                        }
                      },
                      child: const Text('Change time'),
                    ),
                    IconButton(
                      tooltip: 'Remove reminder ${i + 1}',
                      onPressed: () => setState(() => reminders.removeAt(i)),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final v = await pick(end);
                  if (v != null && mounted) setState(() => reminders.add(v));
                },
                icon: const Icon(Icons.add),
                label: const Text('Add reminder'),
              ),
            ),
            const Divider(height: 40),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Open when I sign in'),
              value: startup,
              onChanged: (v) async {
                try {
                  final enabled = await widget.onStartup(v);
                  if (mounted) setState(() => startup = enabled);
                } catch (e) {
                  if (mounted) setState(() => error = e.toString());
                }
              },
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  try {
                    await widget.onTest();
                  } catch (e) {
                    if (mounted) setState(() => error = e.toString());
                  }
                },
                icon: const Icon(Icons.alarm),
                label: const Text('Test reminder'),
              ),
            ),
            const Text(
              'Closing the window keeps reminders running in the tray. Quit from the tray to stop them. Completed reports stop reminders for that day.',
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: saving ? null : save,
                child: Text(saving ? 'Saving…' : 'Save settings'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
