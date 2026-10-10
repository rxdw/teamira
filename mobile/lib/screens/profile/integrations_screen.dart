import 'package:flutter/material.dart';
import '../../widgets/wow_motion.dart' show PressScale;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/integration_token.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../services/app_translations.dart';
import '../../widgets/settings_motion.dart';
import '../../widgets/decide_motion.dart' show BouncingDots;
import '../../widgets/soft_motion.dart';
import '../../theme/clay_kit.dart';

/// Settings > Integrations — everything needed to hook up automatic watch
/// tracking: Plex/Jellyfin webhooks (paste one URL, done), Kodi and the
/// browser extension (a server address + a token, entered separately in
/// their own settings), and a rotate button for if the token ever leaks.
/// See backend/app/routers/integrations.py for what actually happens with
/// these once something starts calling them.
class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({super.key});

  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
  IntegrationToken? _token;
  List<ScrobbleEvent> _events = [];
  bool _loading = true;
  bool _rotating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final integrations = context.read<AppState>().integrations;
      final results = await Future.wait([integrations.getToken(), integrations.recentEvents()]);
      if (!mounted) return;
      setState(() {
        _token = results[0] as IntegrationToken;
        _events = results[1] as List<ScrobbleEvent>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label ${'copied'.tr}')));
  }

  Future<void> _rotate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SeenlyPalette.paper,
        title: Text('rotate your token?'.tr, style: SeenlyText.serif(size: 16)),
        content: Text(
          "every URL you've already pasted into Plex, Jellyfin, Kodi, or the browser extension stops working — you'll need to paste the new one into each of them again.".tr,
          style: SeenlyText.serif(italic: true, size: 12, color: SeenlyPalette.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('cancel'.tr, style: SeenlyText.mono(size: 11)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('rotate'.tr, style: SeenlyText.mono(size: 11, color: SeenlyPalette.coral)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _rotating = true);
    try {
      final token = await context.read<AppState>().integrations.rotateToken();
      if (!mounted) return;
      setState(() {
        _token = token;
        _rotating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _rotating = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("couldn't rotate the token just now".tr)));
    }
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
              padding: const EdgeInsets.fromLTRB(16, 8, 20, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 4),
                  Text('auto-tracking'.tr, style: SeenlyText.screenTitle),
                ],
              ),
            ),
            Expanded(
              // Loading, the error and the settled page glide into one
              // another instead of cutting.
              child: SoftSwap(
                expand: true,
                alignment: Alignment.topCenter,
                rise: 0.015,
                duration: const Duration(milliseconds: 280),
                child: KeyedSubtree(
                  key: ValueKey<String>(_loading ? 'loading' : (_token == null ? 'error' : 'list')),
                  child: _loading
                      ? Center(
                  child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent),
                )
                      : _token == null
                          ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("couldn't load this just now".tr,
                            style: SeenlyText.serif(italic: true, size: 14, color: SeenlyPalette.inkMuted)),
                        const SizedBox(height: 14),
                        PrimaryButton(label: 'try again'.tr, onTap: _load, expand: false),
                      ],
                    ),
                  ),
                )
                          : ListView(
                  padding: const EdgeInsets.fromLTRB(22, 6, 22, 28),
                  children: staggerChildren([
                    Text(
                      'normally you log something by opening the app yourself. auto-tracking flips that around: you connect one thing below, one time, and after that, finishing an episode or a movie somewhere else logs it here on its own — no app, no remembering.'.tr,
                      style: SeenlyText.serif(italic: true, size: 12, color: SeenlyPalette.inkMuted),
                    ),
                    const SizedBox(height: 14),
                    _HowItWorksStrip(),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: ClayBoxDecoration(
                        boxShadow: SeenlyPalette.flatCardShadow,
                        color: SeenlyPalette.paper,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('which one is mine?'.tr, style: SeenlyText.metaLabel),
                          const SizedBox(height: 8),
                          _PickHintRow(
                            label: 'Plex or Jellyfin',
                            detail: 'you (or a friend) run one of these to store and stream your own library'.tr,
                          ),
                          _PickHintRow(
                            label: 'Kodi',
                            detail: 'a media-center app on a TV box, PC, or console'.tr,
                          ),
                          _PickHintRow(
                            label: 'browser extension'.tr,
                            detail: 'you just watch things on streaming sites like Netflix or Kinopoisk in a normal browser'.tr,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text('media servers'.tr, style: SeenlyText.metaLabel),
                    const SizedBox(height: 10),
                    _IntegrationCard(
                      title: 'Plex',
                      steps: const [
                        'Plex Settings → Webhooks → Add Webhook',
                        'paste the URL below',
                      ],
                      child: _CopyRow(value: _token!.plexWebhookUrl, onCopy: () => _copy(_token!.plexWebhookUrl, 'Plex webhook URL'.tr)),
                    ),
                    const SizedBox(height: 10),
                    _IntegrationCard(
                      title: 'Jellyfin',
                      steps: const [
                        'install the official "Webhook" plugin',
                        'add this as a webhook destination',
                        'enable "Playback Stop" and "Item Marked Played"',
                      ],
                      child: _CopyRow(value: _token!.jellyfinWebhookUrl, onCopy: () => _copy(_token!.jellyfinWebhookUrl, 'Jellyfin webhook URL'.tr)),
                    ),
                    const SizedBox(height: 22),
                    Text('kodi'.tr, style: SeenlyText.metaLabel),
                    const SizedBox(height: 10),
                    _IntegrationCard(
                      title: 'Kodi addon',
                      steps: const [
                        'install the tanè Scrobbler addon (see integrations/kodi in the project)',
                        'open its settings and paste both values below',
                      ],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('server'.tr, style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder)),
                          const SizedBox(height: 4),
                          _CopyRow(value: _serverUrl(_token!), onCopy: () => _copy(_serverUrl(_token!), 'server URL'.tr)),
                          const SizedBox(height: 10),
                          Text('token'.tr, style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder)),
                          const SizedBox(height: 4),
                          _CopyRow(value: _token!.token, onCopy: () => _copy(_token!.token, 'token')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text('browser extension'.tr, style: SeenlyText.metaLabel),
                    const SizedBox(height: 10),
                    _IntegrationCard(
                      title: 'Netflix · Hulu · Disney+ · Crunchyroll',
                      steps: const [
                        'load the extension (see integrations/browser-extension in the project)',
                        'open its popup and paste both values below',
                        "it's a best-effort scraper, not an official API — if a "
                            'watch stops showing up for one service, that one may need a small fix',
                      ],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('server'.tr, style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder)),
                          const SizedBox(height: 4),
                          _CopyRow(value: _serverUrl(_token!), onCopy: () => _copy(_serverUrl(_token!), 'server URL'.tr)),
                          const SizedBox(height: 10),
                          Text('token'.tr, style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder)),
                          const SizedBox(height: 4),
                          _CopyRow(value: _token!.token, onCopy: () => _copy(_token!.token, 'token')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _IntegrationCard(
                      title: 'Кинопоиск HD · ivi · Okko · Wink · START · KION · Rutube'.tr,
                      steps: const [
                        'same browser extension as above — one install, one server/token pair '
                            'covers every site it knows how to read',
                        'Rutube is the most reliable of these; the rest read the page\'s own '
                            'structured data and may need a quick fix if a service changes its '
                            'layout (see integrations/browser-extension/README.md for the exact steps)',
                      ],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('server'.tr, style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder)),
                          const SizedBox(height: 4),
                          _CopyRow(value: _serverUrl(_token!), onCopy: () => _copy(_serverUrl(_token!), 'server URL'.tr)),
                          const SizedBox(height: 10),
                          Text('token'.tr, style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder)),
                          const SizedBox(height: 4),
                          _CopyRow(value: _token!.token, onCopy: () => _copy(_token!.token, 'token')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    PressScale(
                      onTap: _rotating ? null : _rotate,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: ClayBoxDecoration(
                          boxShadow: SeenlyPalette.flatCardShadow,
                          color: SeenlyPalette.paper,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: SeenlyPalette.coral.withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.autorenew, size: 16, color: SeenlyPalette.coral),
                            const SizedBox(width: 10),
                            Text('rotate token'.tr, style: SeenlyText.serif(italic: true, color: SeenlyPalette.coral)),
                            const Spacer(),
                            if (_rotating)
                              BouncingDots(color: SeenlyPalette.coral, dotSize: 4),
                          ],
                        ),
                      ),
                    ),
                    if (_events.isNotEmpty) ...[
                      const SizedBox(height: 26),
                      Text('recent activity'.tr, style: SeenlyText.metaLabel),
                      const SizedBox(height: 10),
                      for (final e in _events)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _EventRow(event: e),
                        ),
                    ],
                  ]),
                ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _serverUrl(IntegrationToken token) =>
      token.kodiUrl.replaceFirst('/integrations/${token.token}/scrobble', '');
}

/// Three-step plain-language summary of what "set this up" actually
/// means, so someone can tell at a glance whether it's worth the two
/// minutes before they hit the technical steps in the cards below.
class _HowItWorksStrip extends StatelessWidget {
  // Getter, not a const/final field: `.tr` is a runtime lookup, so the list
  // has to be rebuilt per access to follow the current language.
  static List<(String, String, String)> get _steps => [
    ('1', 'pick what you use'.tr, 'a media server, Kodi, or just a normal browser — see below'.tr),
    ('2', 'paste one link (and maybe a code)'.tr, "it's already filled in for you — just copy and paste".tr),
    ('3', 'watch things like normal'.tr, "finishing something logs it here automatically from then on".tr),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (number, title, detail) in _steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: SeenlyPalette.accent.withOpacity(0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Text(number, style: SeenlyText.mono(size: 10, color: SeenlyPalette.accent, weight: FontWeight.w700)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: SeenlyText.serif(size: 12.5, weight: FontWeight.w600)),
                      Text(detail, style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One row of the "which one is mine?" card — a plain-language label
/// plus a description in ordinary words, no protocol names, so someone
/// can match themselves to a card below without knowing what a webhook
/// or a token is first.
class _PickHintRow extends StatelessWidget {
  final String label;
  final String detail;
  const _PickHintRow({required this.label, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toLowerCase(), style: SeenlyText.serif(size: 12, weight: FontWeight.w600)),
          Text(detail, style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint)),
        ],
      ),
    );
  }
}

class _IntegrationCard extends StatelessWidget {
  final String title;
  final List<String> steps;
  final Widget child;

  const _IntegrationCard({required this.title, required this.steps, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: ClayBoxDecoration(
        boxShadow: SeenlyPalette.flatCardShadow,
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: SeenlyText.cardTitle),
          const SizedBox(height: 6),
          for (final step in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('· ${step.tr}',
                  style: SeenlyText.serif(size: 11, color: SeenlyPalette.inkMuted)),
            ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  final String value;
  final VoidCallback onCopy;
  const _CopyRow({required this.value, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onCopy,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: SeenlyPalette.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SeenlyText.mono(size: 10, color: SeenlyPalette.ink),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.copy_outlined, size: 14, color: SeenlyPalette.accent),
          ],
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final ScrobbleEvent event;
  const _EventRow({required this.event});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: ClayBoxDecoration(
        boxShadow: SeenlyPalette.flatCardShadow,
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            event.logged ? Icons.check_circle_outline : Icons.remove_circle_outline,
            size: 14,
            color: event.logged ? SeenlyPalette.accent : SeenlyPalette.inkFaint,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.rawTitle ?? '(no title)'.tr,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: SeenlyText.serif(size: 12)),
                Text(
                  event.logged ? '${event.integration} · logged' : '${event.integration} · ${event.detail ?? "ignored"}',
                  style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
