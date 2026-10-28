import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// One playback per popup. Closing during asset loading also stops playback.
class ReminderSound {
  ReminderSound({AudioPlayer Function()? createPlayer})
    : _createPlayer = createPlayer ?? AudioPlayer.new;
  final AudioPlayer Function() _createPlayer;
  AudioPlayer? _player;
  Future<void>? _starting;
  bool _closed = false;

  Future<void> start() => _starting ??= _play();

  Future<void> _play() async {
    if (_closed) return;
    try {
      final player = _player = _createPlayer();
      await player.play(AssetSource('reminder_sound.mp3'));
    } catch (error) {
      // A missing audio device must not prevent the visual reminder.
      debugPrint('Reminder sound could not play: $error');
    }
  }

  Future<void> stop() async {
    if (_closed) return;
    _closed = true;
    await _starting;
    try {
      await _player?.dispose();
    } catch (error) {
      debugPrint('Reminder sound could not stop: $error');
    }
  }
}
