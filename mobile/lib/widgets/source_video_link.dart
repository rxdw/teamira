import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/palette.dart';
import '../theme/text_styles.dart';
import '../services/app_translations.dart';

/// Where a "your sources" entry's original video/VOD actually lives —
/// same construction as SourcesScreen._openExternally, pulled out here so
/// the watched-preview card and the title screen's [WatchOnSourceButton]
/// don't each grow their own copy of the URL logic.
Uri sourceVideoUri(String source, String mediaId) => source == 'twitch'
    ? Uri.parse('https://www.twitch.tv/videos/$mediaId')
    : Uri.parse('https://www.youtube.com/watch?v=$mediaId');

bool isSourceVideo(String source) => source == 'youtube' || source == 'twitch';

String sourceLabel(String source) => source == 'twitch' ? 'twitch' : 'youtube';

/// Opens a source's original video externally — same failure handling as
/// _openTrailer in title_detail_screen.dart.
Future<void> openSourceVideo(
  BuildContext context, {
  required String source,
  required String mediaId,
}) async {
  try {
    final opened = await launchUrl(
      sourceVideoUri(source, mediaId),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("couldn't open that link just now".tr)));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("couldn't open that link just now".tr)));
    }
  }
}

/// The one action that actually matters wherever a "your sources" entry
/// ends up without its own catalog page — the watched-preview card and
/// title_detail_screen both have no title to show for a YouTube/Twitch
/// row (see SourcesScreen's own doc comment on why), so this is the
/// button that gets someone back to the actual video instead.
class WatchOnSourceButton extends StatelessWidget {
  final String source;
  final String mediaId;
  final bool expand;

  const WatchOnSourceButton({
    super.key,
    required this.source,
    required this.mediaId,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final icon = source == 'twitch' ? Icons.videocam_rounded : Icons.smart_display_rounded;
    final button = Container(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 24),
      decoration: BoxDecoration(
        color: SeenlyPalette.accent,
        borderRadius: BorderRadius.circular(24),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: SeenlyPalette.accentOnAccent),
          const SizedBox(width: 8),
          Text(
            'watch on ${sourceLabel(source)}',
            style: SeenlyText.serif(italic: true, size: 14, color: SeenlyPalette.accentOnAccent),
          ),
        ],
      ),
    );
    final tappable = GestureDetector(
      onTap: () => openSourceVideo(context, source: source, mediaId: mediaId),
      child: button,
    );
    return expand ? SizedBox(width: double.infinity, child: tappable) : tappable;
  }
}
