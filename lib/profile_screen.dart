import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.prefs, this.radius = 22});
  final SharedPreferences prefs;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final photo = prefs.getString('profile.photo');
    Uint8List? bytes;
    try {
      if (photo != null) bytes = base64Decode(photo);
    } on FormatException {
      // Fall back to initials if saved image data is invalid.
    }
    return CircleAvatar(
      radius: radius,
      child: bytes == null
          ? Text(
              ((prefs.getString('profile.name') ?? '').trim().isEmpty
                      ? '?'
                      : prefs.getString('profile.name')!)
                  .characters
                  .first
                  .toUpperCase(),
            )
          : ClipOval(
              child: Image.memory(
                bytes,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.person_outline),
              ),
            ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.prefs,
    this.welcome = false,
    this.onComplete,
  });
  final SharedPreferences prefs;
  final bool welcome;
  final VoidCallback? onComplete;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(
    text: widget.prefs.getString('profile.name') ?? '',
  );
  Uint8List? photo;
  bool saving = false, choosing = false;
  String? error;

  @override
  void initState() {
    super.initState();
    try {
      final saved = widget.prefs.getString('profile.photo');
      if (saved != null) photo = base64Decode(saved);
    } on FormatException {
      /* Allow replacing invalid saved image data. */
    }
  }

  Future<void> choosePhoto() async {
    setState(() {
      choosing = true;
      error = null;
    });
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Profile photo',
            extensions: ['png', 'jpg', 'jpeg', 'webp'],
          ),
        ],
      );
      if (file == null) return;
      if (await file.length() > 10 * 1024 * 1024) {
        throw const FormatException('Choose an image smaller than 10 MB.');
      }
      final codec = await ui.instantiateImageCodecWithSize(
        await ui.ImmutableBuffer.fromUint8List(await file.readAsBytes()),
        getTargetSize: (width, height) {
          final scale = math.min(1.0, 256 / math.max(width, height));
          return ui.TargetImageSize(
            width: math.max(1, (width * scale).round()),
            height: math.max(1, (height * scale).round()),
          );
        },
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final data = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (data == null) {
            throw const FormatException('Could not read this image.');
          }
          if (mounted) setState(() => photo = data.buffer.asUint8List());
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not open photo. Choose a PNG, JPG, or WebP image smaller than 10 MB.',
        );
      }
    } finally {
      if (mounted) setState(() => choosing = false);
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (photo == null) {
        if (!await widget.prefs.remove('profile.photo')) {
          throw StateError('Photo could not be saved.');
        }
      } else if (!await widget.prefs.setString(
        'profile.photo',
        base64Encode(photo!),
      )) {
        throw StateError('Photo could not be saved.');
      }
      if (!await widget.prefs.setString('profile.name', name.text.trim())) {
        throw StateError('Name could not be saved.');
      }
      if (!await widget.prefs.setBool('profile.complete', true)) {
        throw StateError('Profile could not be saved.');
      }
      if (!mounted) return;
      if (widget.welcome) {
        widget.onComplete?.call();
      } else {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not save your profile. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.welcome ? null : AppBar(title: const Text('Your profile')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.welcome) ...[
                  Image.asset('assets/app_icon.png', height: 72),
                  const SizedBox(height: 28),
                  Text(
                    'Welcome to DailyReport',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'A little about you, then let’s get your daily report ready.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                ],
                Center(
                  child: CircleAvatar(
                    radius: 48,
                    child: photo == null
                        ? const Icon(Icons.person_outline, size: 40)
                        : ClipOval(
                            child: Image.memory(
                              photo!,
                              width: 96,
                              height: 96,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.person_outline),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: saving || choosing ? null : choosePhoto,
                      child: Text(
                        photo == null ? 'Add photo (optional)' : 'Change photo',
                      ),
                    ),
                    if (photo != null)
                      TextButton(
                        onPressed: saving || choosing
                            ? null
                            : () => setState(() => photo = null),
                        child: const Text('Remove photo'),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: name,
                  maxLength: 80,
                  enabled: !saving,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Your name',
                    hintText: 'How should we call you?',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Please enter your name.'
                      : null,
                  onFieldSubmitted: (_) {
                    if (!saving && !choosing) save();
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your profile stays on this computer. You can change it in Settings.',
                  textAlign: TextAlign.center,
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: saving || choosing ? null : save,
                  child: Text(
                    saving
                        ? 'Saving…'
                        : widget.welcome
                        ? 'Get started'
                        : 'Save profile',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
