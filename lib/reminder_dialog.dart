import 'package:flutter/material.dart';

enum ReminderAction { openReport, snooze, dismiss }

class ReminderDialog extends StatelessWidget {
  const ReminderDialog({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AlertDialog(
      icon: const Icon(Icons.alarm, size: 44),
      title: const Text('Time for your daily report'),
      content: SizedBox(
        width: 380,
        child: Text(message, textAlign: TextAlign.center),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ReminderAction.dismiss),
          child: const Text('Dismiss'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(context, ReminderAction.snooze),
          child: const Text('Snooze 10 minutes'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, ReminderAction.openReport),
          child: const Text('Open report'),
        ),
      ],
    ),
  );
}
