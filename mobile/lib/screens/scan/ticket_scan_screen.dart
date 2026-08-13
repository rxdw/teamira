import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/small_pieces.dart';
import '../search/search_screen.dart';

/// "scan a ticket" — one photo of a physical cinema ticket stub, read
/// entirely on-device (no upload anywhere), landing on Search with a
/// best guess at the title already typed in. From there this rides on
/// exactly the same add flow as typing the title by hand: the search
/// result row's own "add to plan to watch" (see SearchScreen), or
/// opening the title and logging it watched from there — nothing new to
/// build or maintain for that half of the job.
///
/// Caveat worth knowing: `google_mlkit_text_recognition`'s standard
/// recognizer only reads Latin script well. A ticket printed in
/// Cyrillic will often come back with garbled or missing text for the
/// title line — which is exactly why this hands off to a normal,
/// editable Search screen instead of trying to silently auto-add
/// whatever it read: the person always gets to see and fix the guess
/// before anything is added.
class TicketScanScreen extends StatefulWidget {
  const TicketScanScreen({super.key});

  @override
  State<TicketScanScreen> createState() => _TicketScanScreenState();
}

enum _ScanPhase { idle, busy, results, empty, error }

class _TicketScanScreenState extends State<TicketScanScreen> {
  _ScanPhase _phase = _ScanPhase.idle;
  List<String> _lines = [];
  late final TextEditingController _queryController;

  // A small stoplist of boilerplate that shows up on ticket stubs
  // themselves rather than the title — cinema chain names, seat/row/hall
  // labels, prices — so the auto-picked guess doesn't land on one of
  // those instead of the film.
  static const _stopWords = [
    'ticket', 'admit', 'adult', 'child', 'seat', 'row', 'hall', 'screen',
    'cinema', 'theatre', 'theater', 'price', 'total', 'date', 'time',
    'auditorium', 'session', 'showtime', 'ref', 'order', 'barcode',
  ];

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    XFile? photo;
    try {
      photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 90,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _ScanPhase.error);
      return;
    }
    // User backed out of the camera — leave them right where they were,
    // no error, nothing to recover from.
    if (photo == null) return;

    if (!mounted) return;
    setState(() => _phase = _ScanPhase.busy);

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(photo.path));
      final lines = <String>[
        for (final block in result.blocks)
          for (final line in block.lines) line.text.trim(),
      ].where((l) => l.isNotEmpty).toList();

      if (!mounted) return;
      if (lines.isEmpty) {
        setState(() => _phase = _ScanPhase.empty);
      } else {
        _queryController.text = _bestGuess(lines);
        setState(() {
          _lines = lines;
          _phase = _ScanPhase.results;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _ScanPhase.error);
    } finally {
      recognizer.close();
      try {
        File(photo.path).delete();
      } catch (_) {
        // Best-effort cleanup of the temp capture — not worth failing over.
      }
    }
  }

  /// The longest recognized line that isn't purely numbers/punctuation
  /// and doesn't read as ticket boilerplate — a real title is usually
  /// the longest, most "wordy" thing printed on the stub, and this is
  /// only ever a starting point the person can freely edit anyway.
  String _bestGuess(List<String> lines) {
    final candidates = lines.where((l) {
      if (l.length < 3) return false;
      if (!RegExp(r'[A-Za-z]').hasMatch(l)) return false;
      final lower = l.toLowerCase();
      if (_stopWords.any((w) => lower.contains(w))) return false;
      return true;
    }).toList();
    if (candidates.isEmpty) return lines.first;
    candidates.sort((a, b) => b.length.compareTo(a.length));
    return candidates.first;
  }

  void _openSearch([String? query]) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SearchScreen(initialQuery: query ?? _queryController.text),
      ),
    );
  }

  void _retry() {
    setState(() {
      _phase = _ScanPhase.idle;
      _lines = [];
      _queryController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 20, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 2),
                  Text('scan a ticket', style: SeenlyText.screenTitle),
                ],
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _ScanPhase.busy:
        return _CenteredMessage(
          icon: null,
          spinning: true,
          title: 'reading your ticket…',
          subtitle: null,
        );
      case _ScanPhase.empty:
        return _CenteredMessage(
          icon: Icons.receipt_long_outlined,
          title: "couldn't make out any text on that",
          subtitle: 'try again with better light, or hold it flatter to the camera',
          buttonLabel: 'try again',
          onButtonTap: _retry,
        );
      case _ScanPhase.error:
        return _CenteredMessage(
          icon: Icons.error_outline,
          title: "couldn't open the camera",
          subtitle: 'check the camera permission in your device settings and try again',
          buttonLabel: 'try again',
          onButtonTap: _retry,
        );
      case _ScanPhase.results:
        return _ResultsBody(
          lines: _lines,
          controller: _queryController,
          onUseLine: (l) {
            _queryController.text = l;
            _openSearch(l);
          },
          onSearch: () => _openSearch(),
          onRetake: _retry,
        );
      case _ScanPhase.idle:
        return _IntroBody(onTakePhoto: _takePhoto);
    }
  }
}

class _IntroBody extends StatelessWidget {
  final VoidCallback onTakePhoto;
  const _IntroBody({required this.onTakePhoto});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Spacer(),
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: SeenlyPalette.accent.withOpacity(0.14),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.confirmation_number_outlined, size: 34, color: SeenlyPalette.accent),
          ),
          const SizedBox(height: 22),
          Text('got a ticket stub from tonight?',
              textAlign: TextAlign.center,
              style: SeenlyText.serif(size: 19, weight: FontWeight.w600)),
          const SizedBox(height: 10),
          Text(
            'take a photo of it and we\'ll pull the title off it, straight into '
            'search — from there it\'s one tap to plan to watch or watched, same '
            'as any other title.',
            textAlign: TextAlign.center,
            style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkMuted),
          ),
          const Spacer(),
          PrimaryButton(label: 'take a photo', onTap: onTakePhoto),
          const SizedBox(height: 10),
          Text('read entirely on your device — nothing is uploaded',
              style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.placeholder)),
        ],
      ),
    );
  }
}

class _ResultsBody extends StatelessWidget {
  final List<String> lines;
  final TextEditingController controller;
  final ValueChanged<String> onUseLine;
  final VoidCallback onSearch;
  final VoidCallback onRetake;

  const _ResultsBody({
    required this.lines,
    required this.controller,
    required this.onUseLine,
    required this.onSearch,
    required this.onRetake,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
      children: [
        Text('does this look right?',
            style: SeenlyText.serif(size: 17, weight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('edit it, or tap another line we picked up below',
            style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: SeenlyPalette.paper,
            borderRadius: BorderRadius.circular(16),
          ),
          child: TextField(
            controller: controller,
            style: SeenlyText.serif(italic: true, size: 15),
            decoration: const InputDecoration(isDense: true, border: InputBorder.none),
          ),
        ),
        const SizedBox(height: 20),
        PrimaryButton(label: 'search', onTap: onSearch),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: onRetake,
            child: Text('retake photo', style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint)),
          ),
        ),
        const SizedBox(height: 20),
        Text('everything we read off the ticket', style: SeenlyText.sectionTitle),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final l in lines)
              GestureDetector(
                onTap: () => onUseLine(l),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: SeenlyPalette.border),
                  ),
                  child: Text(l, style: SeenlyText.mono(size: 11, color: SeenlyPalette.ink)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final IconData? icon;
  final bool spinning;
  final String title;
  final String? subtitle;
  final String? buttonLabel;
  final VoidCallback? onButtonTap;

  const _CenteredMessage({
    this.icon,
    this.spinning = false,
    required this.title,
    this.subtitle,
    this.buttonLabel,
    this.onButtonTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spinning)
              const SizedBox(
                width: 26, height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: SeenlyPalette.accent),
              )
            else if (icon != null)
              Icon(icon, size: 30, color: SeenlyPalette.placeholder),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: SeenlyText.serif(italic: true, size: 15, color: SeenlyPalette.inkMuted)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.placeholder)),
            ],
            if (buttonLabel != null) ...[
              const SizedBox(height: 18),
              PrimaryButton(label: buttonLabel!, onTap: onButtonTap, expand: false),
            ],
          ],
        ),
      ),
    );
  }
}
