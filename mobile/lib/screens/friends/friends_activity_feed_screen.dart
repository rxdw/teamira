import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/activity_item.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/activity_preview.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/themed_poster_tile.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/watched_preview_sheet.dart';
import '../../widgets/wow_motion.dart';
import '../../services/app_translations.dart';

/// The full-screen version of the "friends" teaser card on Home — every
/// recent friend event, each with a real poster instead of a plain text
/// line, opening the same "you watched this" card everywhere else in
/// the app uses (rating, review, and a way to jump straight to the
/// title — see widgets/activity_preview.dart). Reached by tapping either
/// the Home teaser card itself or its "see all" header.
class FriendsActivityFeedScreen extends StatefulWidget {
  const FriendsActivityFeedScreen({super.key});

  @override
  State<FriendsActivityFeedScreen> createState() => _FriendsActivityFeedScreenState();
}

class _FriendsActivityFeedScreenState extends State<FriendsActivityFeedScreen> {
  List<ActivityItem> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final feed = await context.read<AppState>().activity.feed();
      if (!mounted) return;
      setState(() {
        _items = feed.where((e) => !e.isMine).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _relativeTime(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return '';
    final diff = DateTime.now().difference(parsed);
    if (diff.inMinutes < 1) return 'just now'.tr;
    if (diff.inMinutes < 60) {
      return '${ruCount(diff.inMinutes, one: 'минуту', few: 'минуты', many: 'минут', englishOne: 'minute', englishOther: 'minutes')} ${'ago'.tr}';
    }
    if (diff.inHours < 24) {
      return '${ruCount(diff.inHours, one: 'час', few: 'часа', many: 'часов', englishOne: 'hour', englishOther: 'hours')} ${'ago'.tr}';
    }
    if (diff.inDays < 7) {
      return '${ruCount(diff.inDays, one: 'день', few: 'дня', many: 'дней', englishOne: 'day', englishOther: 'days')} ${'ago'.tr}';
    }
    return '${ruCount((diff.inDays / 7).floor(), one: 'неделю', few: 'недели', many: 'недель', englishOne: 'week', englishOther: 'weeks')} ${'ago'.tr}';
  }

  void _openItem(ActivityItem item) {
    if (!item.hasPoster) return;
    showWatchedPreview(context, watchedPreviewFromActivity(item));
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
                  Text('friends activity'.tr, style: SeenlyText.screenTitle),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: ThemedLoadingIndicator())
                  : _items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 40),
                            child: Text(
                              "nothing from friends yet — once they log something, it'll show up here".tr,
                              textAlign: TextAlign.center,
                              style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.inkMuted),
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: SeenlyPalette.accent,
                          child: GridView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 20,
                              crossAxisSpacing: 14,
                              childAspectRatio: 0.5,
                            ),
                            itemCount: _items.length,
                            itemBuilder: (context, i) => Entrance(
                              // Staggered so the grid arrives as a small
                              // held-breath cascade rather than popping in
                              // flat — capped so a long feed doesn't leave
                              // the last few tiles waiting on it.
                              delay: Duration(milliseconds: 55 * i.clamp(0, 6)),
                              riseBy: 16,
                              child: _ActivityFeedCard(
                                item: _items[i],
                                relativeTime: _relativeTime(_items[i].createdAt),
                                onTap: () => _openItem(_items[i]),
                              ),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityFeedCard extends StatelessWidget {
  final ActivityItem item;
  final String relativeTime;
  final VoidCallback onTap;
  const _ActivityFeedCard({required this.item, required this.relativeTime, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Same categorical color the shelves/grid already use for this media
    // type — a grid of mixed activity (a film here, a show there, from
    // whoever) reads as color-coded at a glance, and it's the accent the
    // verb line below borrows too, so each tile feels like one considered
    // piece rather than a poster with generic UI bolted on.
    final accent = SeenlyPalette.mediaColor(item.mediaType ?? 'movie');
    final tappable = item.hasPoster;

    return PressScale(
      haptics: tappable,
      onTap: tappable ? onTap : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Who — unlike the single-friend profile version of this grid,
          // this feed mixes everyone at once, so the byline has to live
          // on every tile rather than being implied by the screen it's on.
          Row(
            children: [
              UserAvatar(
                avatarUrl: item.avatarUrl,
                avatarPreset: item.avatarPreset,
                fallbackLetter: item.nameForDisplay.isNotEmpty ? item.nameForDisplay[0].toUpperCase() : '?',
                size: 18,
                borderColor: Colors.transparent,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(item.nameForDisplay,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeenlyText.serif(size: 11.5, weight: FontWeight.w700)),
              ),
              const SizedBox(width: 4),
              Text(relativeTime, style: SeenlyText.mono(size: 8.5, color: SeenlyPalette.inkFaint)),
            ],
          ),
          const SizedBox(height: 7),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: accent.withOpacity(0.24), blurRadius: 12, offset: const Offset(0, 5)),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ThemedPosterTile(
                      title: item.mediaTitle ?? item.text,
                      posterUrl: item.posterUrl,
                      fallbackColor: accent,
                      mediaType: item.mediaType,
                    ),
                  ),
                  if (item.rating != null && item.rating! > 0)
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: PosterRatingBadge(rating: item.rating!),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.mediaTitle ?? item.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SeenlyText.serif(size: 12.5, weight: FontWeight.w600),
          ),
          const SizedBox(height: 3),
          Text(
            item.verb ?? item.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SeenlyText.mono(size: 9.5, color: accent).copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
