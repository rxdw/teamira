import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/media_item.dart';
import '../../models/person_detail.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/poster_tile.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../title/title_detail_screen.dart';

/// Opened from a tapped cast tile or "directed by ___" name on the title
/// screen (see CastMember.personId / MediaItem.directorId, and
/// MediaService.person). Bio + photo + a filmography grid — no ratings or
/// "similar people" concept the way a title screen has.
class PersonDetailScreen extends StatefulWidget {
  final String personId;
  final String seedName;
  final String? seedPhotoUrl;

  const PersonDetailScreen({
    super.key,
    required this.personId,
    required this.seedName,
    this.seedPhotoUrl,
  });

  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends State<PersonDetailScreen> {
  PersonDetail? _person;
  bool _loading = true;
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await context.read<AppState>().media.person(personId: widget.personId);
      if (!mounted) return;
      setState(() {
        _person = result;
        _notFound = result == null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _person?.name ?? widget.seedName;
    final photoUrl = _person?.photoUrl ?? widget.seedPhotoUrl;

    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      appBar: AppBar(
        backgroundColor: SeenlyPalette.background,
        elevation: 0,
        title: Text(name, style: SeenlyText.serif(size: 16)),
      ),
      body: _loading
          ? const Center(child: ThemedLoadingIndicator())
          : _notFound
              ? Center(
                  child: Text('nothing on this person right now',
                      style: SeenlyText.mono(size: 12, color: SeenlyPalette.placeholder)),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 110,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: AspectRatio(
                                aspectRatio: 2 / 3,
                                child: (photoUrl != null && photoUrl.isNotEmpty)
                                    ? Image.network(
                                        photoUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            Container(color: SeenlyPalette.accent),
                                      )
                                    : Container(color: SeenlyPalette.accent),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: SeenlyText.serif(size: 20)),
                                if (_person?.knownForDepartment != null) ...[
                                  const SizedBox(height: 4),
                                  Text(_person!.knownForDepartment!,
                                      style: SeenlyText.mono(size: 11, color: SeenlyPalette.placeholder)),
                                ],
                                if (_person?.birthday != null) ...[
                                  const SizedBox(height: 4),
                                  Text(_person!.birthday!,
                                      style: SeenlyText.mono(size: 11, color: SeenlyPalette.placeholder)),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      if ((_person?.biography?.display ?? '').isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(_person!.biography!.display, style: SeenlyText.serif(size: 13)),
                      ],
                      if (_person != null && _person!.filmography.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text('filmography',
                            style: SeenlyText.serif(italic: true, size: 14, color: SeenlyPalette.accent)),
                        const SizedBox(height: 12),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _person!.filmography.length,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 12,
                            childAspectRatio: 2 / 3.4,
                          ),
                          itemBuilder: (context, i) {
                            final item = _person!.filmography[i];
                            return PosterTile(
                              title: item.title.display,
                              posterUrl: item.posterUrl,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => TitleDetailScreen(
                                    mediaId: item.id,
                                    source: item.source,
                                    mediaType: item.mediaType,
                                    seedTitle: item.title.display,
                                    seedPosterUrl: item.posterUrl,
                                    seedItem: item,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                      if (_person?.tmdbAttribution != null) ...[
                        const SizedBox(height: 16),
                        Text(_person!.tmdbAttribution!,
                            style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder)),
                      ],
                    ],
                  ),
                ),
    );
  }
}
