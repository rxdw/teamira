import 'package:flutter/material.dart';

import '../../../../models/co_view_entry.dart';
import '../../../../models/co_view_room.dart';
import '../../../../theme/clay_kit.dart';
import '../../../../theme/palette.dart';
import '../../../../theme/text_styles.dart';
import '../../../../widgets/wow_motion.dart';
import '../room_strings.dart';

IconData platformIcon(String key) => switch (key) {
      'pc' => Icons.computer_rounded,
      'ps' || 'xbox' => Icons.sports_esports_rounded,
      'switch' => Icons.gamepad_rounded,
      'mobile' => Icons.smartphone_rounded,
      _ => Icons.more_horiz_rounded,
    };

/// "во что играем?" — the game half of the start sheet. A game is never
/// streamed or relayed: each of you runs it on your own machine and the room
/// is the evening around it (a timer, a ready check, a tally, voice and chat),
/// so all there is to choose is *which* game and, if you like, where you play.
class PlayStartPanel extends StatefulWidget {
  /// The circle's planned entries (null while they load); only games are shown.
  final List<CoViewEntry>? planned;
  final ValueChanged<CoViewEntry> onPlanned;
  final void Function(String title, String? platform) onManual;
  const PlayStartPanel({super.key, required this.planned, required this.onPlanned, required this.onManual});

  @override
  State<PlayStartPanel> createState() => _PlayStartPanelState();
}

class _PlayStartPanelState extends State<PlayStartPanel> {
  final _title = TextEditingController();
  String? _platform;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  bool get _canStart => _title.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final games = [for (final e in widget.planned ?? const <CoViewEntry>[]) if (e.mediaType == 'game') e];
    return ListView(
      key: const ValueKey('play'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(
          at('играйте в настоящую игру — каждый у себя, на чём удобно. а здесь: общий таймер, «готов», счёт раундов, голос и чат.',
              'play a real game — each on your own, on whatever you like. here: a shared timer, a ready check, a tally of rounds, voice and chat.'),
          style: SeenlyText.serif(size: 13.5, italic: true, color: SeenlyPalette.inkMuted),
        ),
        const SizedBox(height: 14),
        if (widget.planned == null)
          const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
        else if (games.isNotEmpty) ...[
          Text(at('из запланированного', 'from your planned'), style: SeenlyText.serif(size: 13, italic: true, color: SeenlyPalette.inkFaint)),
          const SizedBox(height: 8),
          for (final g in games)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PressScale(
                scaleTo: 0.98,
                haptics: true,
                onTap: () => widget.onPlanned(g),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: ClayBoxDecoration(
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: SeenlyPalette.border),
                  ),
                  child: Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: (g.posterUrl != null && g.posterUrl!.isNotEmpty)
                            ? Image.network(g.posterUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback())
                            : _fallback(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(g.titleRu ?? g.titleEn ?? '',
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: SeenlyText.serif(size: 15, weight: FontWeight.w600)),
                    ),
                    Icon(Icons.play_arrow_rounded, color: SeenlyPalette.accent),
                  ]),
                ),
              ),
            ),
          const SizedBox(height: 10),
        ],
        Text(at('другая игра', 'another game'), style: SeenlyText.serif(size: 13, italic: true, color: SeenlyPalette.inkFaint)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: clayWellDecoration(radius: 22),
          child: TextField(
            controller: _title,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.sentences,
            style: SeenlyText.serif(size: 15),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: at('название игры', 'the game’s name'),
              hintStyle: SeenlyText.serif(size: 15, italic: true, color: SeenlyPalette.placeholder),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in RoomKeys.platforms)
            PressScale(
              scaleTo: 0.96,
              onTap: () => setState(() => _platform = _platform == k ? null : k),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _platform == k ? SeenlyPalette.accent.withOpacity(0.14) : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _platform == k ? SeenlyPalette.accent.withOpacity(0.5) : SeenlyPalette.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(platformIcon(k), size: 15, color: _platform == k ? SeenlyPalette.accent : SeenlyPalette.inkMuted),
                  const SizedBox(width: 6),
                  Text(platformLabel(k),
                      style: SeenlyText.serif(size: 13, italic: true, color: _platform == k ? SeenlyPalette.accent : SeenlyPalette.inkMuted)),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 16),
        Opacity(
          opacity: _canStart ? 1 : 0.45,
          child: PressScale(
            haptics: true,
            onTap: _canStart ? () => widget.onManual(_title.text, _platform) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              decoration: ClayBoxDecoration(color: SeenlyPalette.accent, borderRadius: BorderRadius.circular(22)),
              child: Text(at('открыть комнату', 'open the room'),
                  style: SeenlyText.serif(size: 16, weight: FontWeight.w600, color: SeenlyPalette.accentOnAccent)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fallback() => ColoredBox(color: SeenlyPalette.cork, child: Icon(Icons.sports_esports_rounded, color: SeenlyPalette.inkFaint));
}
