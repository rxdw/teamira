import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/watchlist_entry.dart';
import '../screens/title/title_detail_screen.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'small_pieces.dart';
import 'themed_poster_tile.dart';

/// A single random draw from your own "plan to watch" shelf — same
/// reroll-in-place idea as Home's random pick card, just scoped to this
/// one shelf and opened right from its tab instead of living on its own.
/// Nothing to sync here (it's already on your list), so this is purely
/// client-side: pick from what's already loaded, reroll locally, open
/// the title when you're set on it.
Future<void> showPlannedRandomPickSheet(BuildContext context, List<WatchlistEntry> shelf) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: SeenlyPalette.paper,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _PlannedRandomPickSheet(shelf: shelf),
  );
}

class _PlannedRandomPickSheet extends StatefulWidget {
  final List<WatchlistEntry> shelf;
  const _PlannedRandomPickSheet({required this.shelf});

  @override
  State<_PlannedRandomPickSheet> createState() => _PlannedRandomPickSheetState();
}

class _PlannedRandomPickSheetState extends State<_PlannedRandomPickSheet> {
  late WatchlistEntry _pick = widget.shelf[math.Random().nextInt(widget.shelf.length)];

  void _reroll() {
    if (widget.shelf.length < 2) return;
    final current = _pick;
    WatchlistEntry next;
    do {
      next = widget.shelf[math.Random().nextInt(widget.shelf.length)];
    } while (identical(next, current));
    setState(() => _pick = next);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 20, 22, MediaQuery.of(context).viewInsets.bottom + 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.casino_outlined, size: 16, color: SeenlyPalette.accent),
              const SizedBox(width: 6),
              Text('random pick', style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
              const Spacer(),
              if (widget.shelf.length > 1)
                GestureDetector(
                  onTap: _reroll,
                  behavior: HitTestBehavior.opaque,
                  child: const Icon(Icons.refresh, size: 17, color: SeenlyPalette.inkMuted),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 74,
                child: ThemedPosterTile(
                  title: _pick.displayTitle,
                  posterUrl: _pick.posterUrl,
                  mediaType: _pick.mediaType,
                  fallbackColor: SeenlyPalette.mediaColor(_pick.mediaType),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_pick.displayTitle, style: SeenlyText.serif(size: 16, italic: true, weight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(_pick.mediaType, style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          PrimaryButton(
            label: 'open it',
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TitleDetailScreen(
                    mediaId: _pick.mediaId,
                    source: _pick.source,
                    mediaType: _pick.mediaType,
                    seedTitle: _pick.displayTitle,
                    seedPosterUrl: _pick.posterUrl,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
