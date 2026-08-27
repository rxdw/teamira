import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';
import '../services/app_translations.dart';

/// Every pairing code this app hands out is 6 characters from
/// _CODE_ALPHABET in backend/app/routers/partner.py (and the matching
/// alphabet in together.py) — no 0/O/1/I. Used here to tell an actual
/// pairing code apart from whatever else a camera might point at.
final RegExp _pairingCodePattern = RegExp(r'^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$');

/// The code as a small scannable square, dropped in wherever
/// `_PendingCodeBody` already shows the plain-text code — meant for two
/// people sitting near each other so one can just point a phone at the
/// other's screen instead of reading six characters aloud. Framed like a
/// little instant photo (paper mat, soft shadow, a strip of washi tape)
/// to match the rest of the app rather than looking like a bare
/// generated graphic dropped in from nowhere.
class PairingQrCode extends StatelessWidget {
  final String code;
  final double size;

  const PairingQrCode({super.key, required this.code, this.size = 168});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: SeenlyPalette.ink.withOpacity(0.10), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: QrImageView(
        data: code,
        version: QrVersions.auto,
        size: size,
        gapless: false,
        backgroundColor: SeenlyPalette.paper,
        eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: SeenlyPalette.ink),
        dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: SeenlyPalette.ink),
      ),
    );
  }
}

/// Opens the camera, styled to match — a warm dark scrim instead of flat
/// black, a rounded viewfinder in the accent color, soft mono copy. Pops
/// itself with the 6-character code the moment it recognizes one; hands
/// back null if the person backs out first.
Future<String?> showPairingScanner(BuildContext context) {
  return Navigator.of(context).push<String>(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, anim, __) => FadeTransition(opacity: anim, child: const _PairingScannerScreen()),
    ),
  );
}

class _PairingScannerScreen extends StatefulWidget {
  const _PairingScannerScreen();

  @override
  State<_PairingScannerScreen> createState() => _PairingScannerScreenState();
}

class _PairingScannerScreenState extends State<_PairingScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim().toUpperCase();
      if (raw != null && _pairingCodePattern.hasMatch(raw)) {
        _handled = true;
        Navigator.of(context).pop(raw);
        return;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // A soft dark wash rather than pure black — keeps the camera
          // feed readable while still framing the cut-out square.
          Container(color: SeenlyPalette.ink.withOpacity(0.35)),
          Center(
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: SeenlyPalette.accent, width: 2.5),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 64,
            child: Text(
              'point it at their code'.tr,
              textAlign: TextAlign.center,
              style: SeenlyText.mono(size: 12, color: Colors.white, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
