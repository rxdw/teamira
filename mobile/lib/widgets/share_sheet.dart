import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'small_pieces.dart';
import '../services/app_translations.dart';

/// Previews [card] centered over a softly blurred, dimmed backdrop — the
/// same quiet, gallery-like treatment the poster lightbox uses
/// (widgets/poster_lightbox.dart), rather than a sheet sliding up from
/// the bottom — with one button: render it to a PNG and hand it to the
/// device's native share sheet. This is the whole "share this evening" /
/// "share your year" flow — Letterboxd does the same thing, just baked
/// into their app instead of a reusable helper.
Future<void> showShareCardSheet(
  BuildContext context, {
  required Widget card,
  required String fileName,
  String? shareText,
}) {
  final boundaryKey = GlobalKey();

  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, animation, secondaryAnimation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return AnimatedBuilder(
          animation: curved,
          builder: (context, child) {
            final t = curved.value;
            return Stack(
              fit: StackFit.expand,
              children: [
                // Same soft blur-and-dim as the poster lightbox, so a
                // shared card and a fullscreen poster read as one
                // consistent "big overlay" moment across the app.
                GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 22 * t, sigmaY: 22 * t),
                    child: Container(color: SeenlyPalette.ink.withOpacity(0.62 * t)),
                  ),
                ),
                Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * 24),
                    child: child,
                  ),
                ),
              ],
            );
          },
          child: _ShareCardSheetBody(
            card: card,
            boundaryKey: boundaryKey,
            fileName: fileName,
            shareText: shareText,
          ),
        );
      },
    ),
  );
}

class _ShareCardSheetBody extends StatefulWidget {
  final Widget card;
  final GlobalKey boundaryKey;
  final String fileName;
  final String? shareText;

  const _ShareCardSheetBody({
    required this.card,
    required this.boundaryKey,
    required this.fileName,
    this.shareText,
  });

  @override
  State<_ShareCardSheetBody> createState() => _ShareCardSheetBodyState();
}

class _ShareCardSheetBodyState extends State<_ShareCardSheetBody> {
  bool _sharing = false;
  bool _failed = false;

  Future<void> _share() async {
    setState(() {
      _sharing = true;
      _failed = false;
    });
    try {
      final boundary = widget.boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      final image = await boundary?.toImage(pixelRatio: 3);
      final bytes = await image?.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw Exception('no image');
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes.buffer.asUint8List(),
            name: '${widget.fileName}.png',
            mimeType: 'image/png',
          ),
        ],
        text: widget.shareText,
      );
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 340,
            maxHeight: media.size.height * 0.82,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            decoration: BoxDecoration(
              color: SeenlyPalette.background,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 40,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('share'.tr,
                          style: SeenlyText.serif(
                              italic: true, size: 15, color: SeenlyPalette.accent)),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).maybePop(),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: SeenlyPalette.ink.withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.close_rounded,
                            size: 16, color: SeenlyPalette.inkMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: RepaintBoundary(key: widget.boundaryKey, child: widget.card),
                  ),
                ),
                if (_failed) ...[
                  const SizedBox(height: 10),
                  Text("couldn't share that — try again".tr,
                      style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkMuted)),
                ],
                const SizedBox(height: 18),
                PrimaryButton(
                  label: 'share the card'.tr,
                  loading: _sharing,
                  onTap: _share,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
