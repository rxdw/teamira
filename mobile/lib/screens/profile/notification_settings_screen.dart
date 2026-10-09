import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/push_service.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/decide_motion.dart' show BouncingDots;
import '../../widgets/settings_motion.dart';
import '../../widgets/soft_motion.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/wow_motion.dart' show Entrance;
import '../../theme/clay_kit.dart';
import '../../services/app_translations.dart';

/// Settings > Notifications — per-category push toggles. Renders
/// whatever GET /push/preferences hands back (see app/push.py's
/// CATEGORY_COPY on the backend) rather than hardcoding the category
/// list here, so a new category added server-side shows up the next
/// time this screen loads, no client release required.
///
/// The category names and descriptions come from the server in Russian and are
/// translated here (`.tr` finds the English by the Russian text — lowercased
/// first, since the server capitalises and the ARB pairs are all lowercase). A category
/// added server-side shows up in Russian until its pair is added to the ARB
/// files — the one thing a new category still needs from an app release.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  List<PushPreference> _prefs = [];
  bool _loading = true;
  String? _error;
  // category apiValue -> in-flight PATCH, so a rapid double-tap on the
  // same switch can't fire two overlapping requests that might resolve
  // out of order and leave the toggle showing the wrong state.
  final Set<String> _saving = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await context.read<AppState>().pushApi.getPreferences();
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'не удалось загрузить настройки — попробуйте ещё раз'.tr;
      });
    }
  }

  Future<void> _toggle(PushPreference pref, bool enabled) async {
    final category = pref.category;
    if (category == null || _saving.contains(pref.rawCategory)) return;

    // Optimistic — flips immediately, rolled back below only if the
    // PATCH actually fails. A settings toggle that visibly lags behind
    // the tap reads as broken far more often than an occasional silent
    // rollback reads as surprising.
    final previous = List<PushPreference>.of(_prefs);
    setState(() {
      _saving.add(pref.rawCategory);
      _prefs = _prefs
          .map((p) => p.rawCategory == pref.rawCategory
              ? PushPreference(
                  category: p.category,
                  rawCategory: p.rawCategory,
                  label: p.label,
                  description: p.description,
                  enabled: enabled,
                )
              : p)
          .toList();
    });
    try {
      final updated = await context.read<AppState>().pushApi.updatePreferences({category: enabled});
      if (!mounted) return;
      setState(() {
        _prefs = updated;
        _saving.remove(pref.rawCategory);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _prefs = previous;
        _saving.remove(pref.rawCategory);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('не получилось сохранить — попробуйте ещё раз'.tr)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      appBar: AppBar(
        backgroundColor: SeenlyPalette.background,
        elevation: 0,
        title: Text('уведомления'.tr, style: SeenlyText.serif(size: 16)),
      ),
      // Loading, the error and the list glide into one another; the list
      // itself settles in row by row.
      body: SoftSwap(
        expand: true,
        alignment: Alignment.topCenter,
        rise: 0.015,
        duration: const Duration(milliseconds: 280),
        child: KeyedSubtree(
          key: ValueKey<String>(_loading ? 'loading' : (_error != null ? 'error' : 'list')),
          child: _loading
              ? const Center(child: ThemedLoadingIndicator())
              : _error != null
                  ? _ErrorState(message: _error!, onRetry: _load)
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      children: staggerChildren([
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                          child: Text(
                            'какие пуши вы хотите получать — остальное просто не будет присылаться.'.tr,
                            style: SeenlyText.serif(italic: true, size: 12, color: SeenlyPalette.inkMuted),
                          ),
                        ),
                        const SizedBox(height: 16),
                        for (final pref in _prefs) ...[
                          _PreferenceRow(
                            pref: pref,
                            saving: _saving.contains(pref.rawCategory),
                            onChanged: (v) => _toggle(pref, v),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ]),
                    ),
        ),
      ),
    );
  }
}

class _PreferenceRow extends StatelessWidget {
  final PushPreference pref;
  final bool saving;
  final ValueChanged<bool> onChanged;

  const _PreferenceRow({required this.pref, required this.saving, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: ClayBoxDecoration(
          boxShadow: SeenlyPalette.flatCardShadow,
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              // A category that's switched off looks a little quieter.
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 240),
                opacity: pref.enabled ? 1 : 0.6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pref.label.toLowerCase().tr, style: SeenlyText.serif(size: 13)),
                    const SizedBox(height: 2),
                    Text(
                      pref.description.toLowerCase().tr,
                      style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
                    ),
                  ],
                ),
              ),
            ),
            // The switch stays put and flips smoothly by itself; while the
            // change is on its way, three dots hop beside it.
            SoftSwap(
              alignment: Alignment.center,
              duration: const Duration(milliseconds: 200),
              child: saving
                  ? Padding(
                      key: const ValueKey<String>('saving'),
                      padding: const EdgeInsets.only(right: 6),
                      child: BouncingDots(color: SeenlyPalette.accent, dotSize: 4),
                    )
                  : const SizedBox(key: ValueKey<String>('idle'), width: 1, height: 1),
            ),
            Switch(
              value: pref.enabled,
              activeColor: SeenlyPalette.accent,
              onChanged: (pref.category == null || saving) ? null : onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Entrance(
          riseBy: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: SeenlyText.serif(size: 13, color: SeenlyPalette.inkMuted),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: onRetry, child: Text('повторить'.tr)),
            ],
          ),
        ),
      ),
    );
  }
}
