import 'package:flutter/material.dart';

import '../../models/media_item.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/wow_motion.dart';
import '../person/person_detail_screen.dart';

/// The full cast list for a title, reached by tapping "see all" on the
/// horizontal cast shelf in title_detail_screen.dart — same underlying
/// [CastMember] data (from MediaDetail.cast, TMDB-sourced), just laid
/// out as a scrollable grid instead of a single row so every credited
/// actor is visible at once. Tapping a tile opens PersonDetailScreen,
/// same as tapping a tile on the shelf itself, for anyone TMDB gave a
/// person id.
class FullCastScreen extends StatelessWidget {
  final String titleName;
  final List<CastMember> cast;

  const FullCastScreen({super.key, required this.titleName, required this.cast});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 20, 6),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 18, color: SeenlyPalette.ink),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text('cast',
                        style: SeenlyText.serif(size: 19, italic: true), maxLines: 1),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
              child: Text(titleName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SeenlyText.mono(size: 10, color: SeenlyPalette.placeholder)),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 18,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.46,
                ),
                itemCount: cast.length,
                itemBuilder: (context, i) => Entrance(
                  delay: Duration(milliseconds: 25 * i.clamp(0, 12)),
                  riseBy: 10,
                  child: _FullCastTile(member: cast[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullCastTile extends StatelessWidget {
  final CastMember member;
  const _FullCastTile({required this.member});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: member.personId != null
          ? () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PersonDetailScreen(
                    personId: member.personId!,
                    seedName: member.name,
                    seedPhotoUrl: member.photoUrl,
                  ),
                ),
              )
          : null,
      scaleTo: 0.94,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: (member.photoUrl != null)
                  ? Image.network(
                      member.photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: SeenlyPalette.accent),
                    )
                  : Container(color: SeenlyPalette.accent),
            ),
          ),
          const SizedBox(height: 6),
          Text(member.name,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: SeenlyText.serif(size: 12)),
          if ((member.character?.display.isNotEmpty ?? false) && member.character!.display != '—')
            Text(member.character!.display,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder)),
        ],
      ),
    );
  }
}
