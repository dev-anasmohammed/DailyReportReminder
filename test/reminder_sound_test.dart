import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:daily_report_reminder/reminder_sound.dart';
import 'package:flutter_test/flutter_test.dart';

class _Player extends Fake implements AudioPlayer {
  final loading = Completer<void>();
  int plays = 0, disposals = 0;
  Source? lastSource;

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) {
    plays++;
    lastSource = source;
    return loading.future;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

void main() {
  test(
    'plays the bundled sound once and closes safely during loading',
    () async {
      final player = _Player();
      final sound = ReminderSound(createPlayer: () => player);
      final first = sound.start();
      final second = sound.start();
      expect(player.plays, 1);
    expect((player.lastSource as AssetSource).path, 'reminder_sound.mp3');
      final stopped = sound.stop();
      expect(player.disposals, 0);
      player.loading.complete();
      await Future.wait([first, second, stopped]);
      expect(player.disposals, 1);
      await sound.start();
      await sound.stop();
      expect(player.plays, 1);
      expect(player.disposals, 1);
    },
  );

  test('audio device failure does not prevent closing the reminder', () async {
    final player = _Player();
    final sound = ReminderSound(createPlayer: () => player);
    final started = sound.start();
    player.loading.completeError(StateError('No audio output'));
    await started;
    await sound.stop();
    expect(player.disposals, 1);
  });
}
