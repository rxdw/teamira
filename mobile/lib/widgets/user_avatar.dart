import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile_stats.dart';
import '../state/app_state.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';

/// Renders whichever of the three avatar states a user is in — a photo
/// they uploaded (avatarUrl, relative to the API's own base URL), a
/// bundled mascot they picked (avatarPreset, matched against
/// [kAvatarPresets]), or neither, in which case this falls back to the
/// same first-letter-of-username circle the app always used. One widget
/// so the profile header and every friend row render avatars identically.
class UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String? avatarPreset;
  final String fallbackLetter;
  final double size;
  final Color borderColor;

  const UserAvatar({
    super.key,
    required this.avatarUrl,
    required this.avatarPreset,
    required this.fallbackLetter,
    this.size = 56,
    this.borderColor = SeenlyPalette.accent,
  });

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      final resolved = avatarUrl!.startsWith('http')
          ? Future.value(avatarUrl!)
          : context.read<AppState>().client.resolveBaseUrl().then((base) => '$base$avatarUrl');
      child = FutureBuilder<String>(
        future: resolved,
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox.shrink();
          return ClipOval(
            child: Image.network(
              snap.data!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _letter(),
            ),
          );
        },
      );
    } else if (avatarPreset != null) {
      final preset = kAvatarPresets.where((p) => p.id == avatarPreset).toList();
      child = preset.isEmpty
          ? _letter()
          : ClipOval(
              child: Image.asset(preset.first.assetPath, width: size, height: size, fit: BoxFit.cover),
            );
    } else {
      child = _letter();
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: SeenlyPalette.paper,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 1.5),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }

  Widget _letter() => Text(
        fallbackLetter,
        style: SeenlyText.serif(size: size * 0.4, italic: true, color: SeenlyPalette.accent),
      );
}
