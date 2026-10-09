import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/media_item.dart';
import '../../models/title_extras.dart';
import '../../services/app_translations.dart';
import '../../services/locale_service.dart';
import '../../theme/clay_kit.dart';
import '../../theme/palette.dart';
import '../../theme/seenly_skin.dart';
import '../../theme/text_styles.dart';
import '../../widgets/themed_poster_tile.dart';
import '../../widgets/wow_motion.dart';

/// The richer layer of the title screen for games, books, manga and anime —
/// everything GET /media/detail now sends in [MediaItem.extras]. Each widget
/// here owns one slice and hides itself (zero height) when that slice is
/// empty, so title_detail_screen.dart can list them in order without a
/// condition per section, and a title nobody had extras for looks exactly as
/// it did before.
///
/// Visual language is the screen's own: serif-italic accent headings, mono
/// captions, soft clay surfaces (flat bordered ones on the non-clay skins),
/// horizontal shelves that reveal as they scroll in.

// ---------------------------------------------------------------------------
// Small shared pieces
// ---------------------------------------------------------------------------

/// A soft surface: a puffy clay card on the clay skin, a quiet bordered one on
/// the others. Same split GenreTag makes, so these sit naturally beside the
/// genre chips above them.
class _Soft extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color? tint;
  final double elevation;
  const _Soft({
    required this.child,
    this.radius = 16,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    this.tint,
    this.elevation = 0.4,
  });

  @override
  Widget build(BuildContext context) {
    final base = tint == null
        ? SeenlyPalette.paper
        : Color.alphaBlend(tint!.withOpacity(0.16), SeenlyPalette.paper);
    if (SeenlySkin.isClay) {
      return ClaySurface(
        radius: radius,
        elevation: elevation,
        color: base,
        padding: padding,
        child: child,
      );
    }
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tint == null ? null : base,
        border: Border.all(color: SeenlyPalette.border),
        borderRadius: BorderRadius.circular(radius > 12 ? 12.0 : radius),
      ),
      child: child,
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const _SectionHeading(this.text, {this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(text, style: SeenlyText.serif(italic: true, size: 14, color: SeenlyPalette.accent)),
          if (trailing != null) ...[const Spacer(), trailing!],
        ],
      ),
    );
  }
}

/// 12300 -> "12.3k", 1500000 -> "1.5M". Short on purpose: it sits in a chip.
String _compact(int n) {
  if (n < 1000) return '$n';
  if (n < 10000) {
    final v = (n / 1000).toStringAsFixed(1);
    return '${v.endsWith('.0') ? v.substring(0, v.length - 2) : v}k';
  }
  if (n < 1000000) return '${(n / 1000).round()}k';
  final v = (n / 1000000).toStringAsFixed(1);
  return '${v.endsWith('.0') ? v.substring(0, v.length - 2) : v}M';
}

/// 15.0 -> "15", 7.5 -> "7.5", 0.4 -> "0.4".
String _hoursText(double h) {
  if (h >= 10) return h.round().toString();
  final v = h.toStringAsFixed(1);
  return v.endsWith('.0') ? v.substring(0, v.length - 2) : v;
}

const _monthsEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monthsRu = ['янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];

/// "Oct 10" / "10 окт" for an ISO timestamp, in the device's own time zone;
/// null when it can't be read.
String? _shortDate(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return null;
  return LocaleService.appIsRussian
      ? '${d.day} ${_monthsRu[d.month - 1]}'
      : '${_monthsEn[d.month - 1]} ${d.day}';
}

int? _yearOf(String? date) {
  if (date == null || date.length < 4) return null;
  return int.tryParse(date.substring(0, 4));
}

/// "Russian" -> "Русский" via the translation tables; "Spanish - Spain" and
/// "Portuguese (Brazil)" translate their first word and keep the qualifier.
String _languageName(String name) {
  final direct = name.tr;
  if (direct != name) return direct;
  final cut = RegExp(r'\s*[-(]').firstMatch(name);
  if (cut == null) return name;
  final head = name.substring(0, cut.start);
  final tail = name.substring(cut.start);
  final translated = head.tr;
  return translated == head ? name : '$translated$tail';
}

Future<void> _openUrl(BuildContext context, String url) async {
  try {
    final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) _linkError(context);
  } catch (_) {
    if (context.mounted) _linkError(context);
  }
}

void _linkError(BuildContext context) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text("couldn't open that link just now".tr)));
}

class _NetImage extends StatelessWidget {
  final String? url;
  final Color fallback;
  const _NetImage({required this.url, required this.fallback});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return Container(color: fallback);
    return FadeInNetworkImage(url: url!, fit: BoxFit.cover, placeholder: Container(color: fallback));
  }
}

// ---------------------------------------------------------------------------
// Highlights — the quick facts as soft chips
// ---------------------------------------------------------------------------

class _Fact {
  final IconData icon;
  final String text;
  final Color? tint;
  const _Fact(this.icon, this.text, {this.tint});
}

/// The few things a person scans a title for, as icon chips: price and
/// Metacritic for a game, pages and language for a book, studio and episode
/// count for an anime. What is *not* here (developer, publisher, platforms,
/// ISBN ...) stays in the plain rows of the facts block above the synopsis.
class TitleHighlights extends StatelessWidget {
  final MediaItem item;
  const TitleHighlights({super.key, required this.item});

  static List<_Fact> _facts(MediaItem item) {
    final x = item.extras;
    if (x == null) return const [];
    final out = <_Fact>[];
    switch (item.mediaType) {
      case 'game':
        if (x.freeToPlay == true) {
          out.add(_Fact(Icons.card_giftcard_rounded, 'free to play'.tr, tint: SeenlyPalette.sage));
        } else if (x.price != null) {
          out.add(_Fact(Icons.sell_outlined, x.price!));
        }
        if (x.priceDiscountPct != null) {
          out.add(_Fact(Icons.local_offer_outlined, '−${x.priceDiscountPct}%', tint: SeenlyPalette.coral));
        }
        if (x.metacritic != null) {
          final m = x.metacritic!;
          out.add(_Fact(Icons.verified_outlined, '${'Metacritic'.tr} $m',
              tint: m >= 75 ? SeenlyPalette.sage : (m >= 50 ? SeenlyPalette.mustard : SeenlyPalette.coral)));
        } else if (x.criticScore != null) {
          out.add(_Fact(Icons.verified_outlined, '${'critics'.tr} ${x.criticScore}'));
        }
        final ttb = x.timeToBeat;
        final hours = ttb == null ? null : (ttb.normally ?? ttb.hastily ?? ttb.completely);
        if (hours != null) {
          out.add(_Fact(Icons.schedule_rounded, '~${_hoursText(hours)} ${'h'.tr}'));
        }
        if (x.achievements != null) {
          out.add(_Fact(Icons.emoji_events_outlined, '${x.achievements} ${'achievements'.tr}'));
        }
        if (x.perspectives.isNotEmpty) {
          out.add(_Fact(Icons.visibility_outlined, x.perspectives.first.tr));
        }
        for (final f in x.steamFeatures) {
          out.add(_Fact(f.contains('ontroller') ? Icons.gamepad_outlined : Icons.cloud_outlined, f.tr));
        }
        final deck = _deckLabel(x.steamDeck);
        if (deck != null) {
          out.add(_Fact(Icons.videogame_asset_outlined, deck, tint: _deckTint(x.steamDeck)));
        }
        break;
      case 'book':
        if (x.pages != null) out.add(_Fact(Icons.menu_book_outlined, '${x.pages} ${'pages'.tr}'));
        final minutes = item.runtimeMinutes;
        if (minutes != null && minutes >= 60) {
          out.add(_Fact(Icons.schedule_rounded, '≈ ${_hoursText(minutes / 60)} ${'h'.tr} ${'to read'.tr}'));
        }
        final year = _yearOf(x.publishedDate);
        if (year != null && year != item.year) out.add(_Fact(Icons.calendar_today_outlined, '$year'));
        if (x.bookLanguage != null) {
          out.add(_Fact(Icons.translate_rounded, _languageFromCode(x.bookLanguage!)));
        }
        break;
      case 'manga':
        if (x.sourceMaterial != null) out.add(_Fact(Icons.auto_stories_outlined, x.sourceMaterial!.tr));
        final span = _span(x);
        if (span != null) out.add(_Fact(Icons.calendar_today_outlined, span));
        if (x.popularity != null) {
          out.add(_Fact(Icons.people_outline_rounded, '${_compact(x.popularity!)} ${'in lists'.tr}'));
        }
        if (x.favourites != null) {
          out.add(_Fact(Icons.favorite_border_rounded, _compact(x.favourites!), tint: SeenlyPalette.pink));
        }
        break;
      case 'anime':
        if (x.studios.isNotEmpty) {
          out.add(_Fact(Icons.apartment_rounded, x.studios.take(2).join(', ')));
        }
        final eps = _episodesText(x);
        if (eps != null) out.add(_Fact(Icons.video_library_outlined, eps));
        final next = _shortDate(x.nextEpisodeAt);
        if (next != null) {
          out.add(_Fact(Icons.notifications_none_rounded, '${'next episode'.tr} $next', tint: SeenlyPalette.mustard));
        }
        if (x.sourceMaterial != null) out.add(_Fact(Icons.auto_stories_outlined, x.sourceMaterial!.tr));
        if (x.popularity != null) {
          out.add(_Fact(Icons.people_outline_rounded, '${_compact(x.popularity!)} ${'in lists'.tr}'));
        }
        break;
    }
    return out;
  }

  static String? _deckLabel(String? deck) {
    switch (deck) {
      case 'verified':
        return 'Steam Deck verified'.tr;
      case 'playable':
        return 'Steam Deck playable'.tr;
      case 'unsupported':
        return 'Steam Deck unsupported'.tr;
      default:
        return null;
    }
  }

  static Color? _deckTint(String? deck) {
    switch (deck) {
      case 'verified':
        return SeenlyPalette.sage;
      case 'playable':
        return SeenlyPalette.mustard;
      case 'unsupported':
        return SeenlyPalette.coral;
      default:
        return null;
    }
  }

  static String? _span(TitleExtras x) {
    final start = _yearOf(x.startDate);
    if (start == null) return null;
    final end = _yearOf(x.endDate);
    if (end == null) return '$start – ${'ongoing'.tr}';
    return end == start ? '$start' : '$start – $end';
  }

  static String? _episodesText(TitleExtras x) {
    final total = x.episodes;
    final aired = x.episodesAired;
    final min = x.episodeMinutes;
    String? base;
    if (total != null && aired != null && aired > 0 && aired < total) {
      base = '$aired / $total ${'episodes'.tr}';
    } else if (total != null) {
      base = '$total ${'episodes'.tr}';
    } else if (aired != null && aired > 0) {
      base = '$aired ${'episodes'.tr}';
    }
    if (base == null) return null;
    return min != null ? '$base · $min ${'min'.tr}' : base;
  }

  static String _languageFromCode(String code) {
    switch (code.toLowerCase()) {
      case 'ru':
        return 'Russian'.tr;
      case 'en':
        return 'English'.tr;
      case 'de':
        return 'German'.tr;
      case 'fr':
        return 'French'.tr;
      case 'es':
        return 'Spanish'.tr;
      case 'it':
        return 'Italian'.tr;
      case 'ja':
        return 'Japanese'.tr;
      case 'uk':
        return 'Ukrainian'.tr;
      default:
        return code.toUpperCase();
    }
  }

  static bool hasContent(MediaItem item) => _facts(item).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final facts = _facts(item);
    if (facts.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final f in facts)
          _Soft(
            tint: f.tint,
            radius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(f.icon, size: 14, color: f.tint ?? SeenlyPalette.inkMuted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    f.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.ink, weight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Creators — authors of a book/manga, key staff of an anime
// ---------------------------------------------------------------------------

class TitleCreatorsSection extends StatelessWidget {
  final MediaItem item;
  const TitleCreatorsSection({super.key, required this.item});

  static bool hasContent(MediaItem item) => (item.extras?.creators ?? const []).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final creators = item.extras?.creators ?? const <TitleCreator>[];
    if (creators.isEmpty) return const SizedBox.shrink();
    final isAnime = item.mediaType == 'anime';
    final heading = isAnime
        ? 'creators'.tr
        : (creators.length == 1 ? 'author'.tr : 'authors'.tr);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(heading),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: creators.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, i) => HorizontalReveal(
              delay: Duration(milliseconds: 40 * i.clamp(0, 8)),
              child: _CreatorTile(creator: creators[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _CreatorTile extends StatelessWidget {
  final TitleCreator creator;
  const _CreatorTile({required this.creator});

  @override
  Widget build(BuildContext context) {
    final hasBio = (creator.bio ?? '').isNotEmpty;
    final initial = creator.displayName.trim().isEmpty ? '?' : creator.displayName.trim()[0].toUpperCase();
    final avatar = ClipOval(
      child: SizedBox(
        width: 58,
        height: 58,
        child: creator.photoUrl != null
            ? _NetImage(url: creator.photoUrl, fallback: SeenlyPalette.cork)
            : Container(
                color: Color.alphaBlend(SeenlyPalette.periwinkle.withOpacity(0.25), SeenlyPalette.paper),
                alignment: Alignment.center,
                child: Text(initial, style: SeenlyText.serif(size: 22, color: SeenlyPalette.inkMuted)),
              ),
      ),
    );
    return PressScale(
      onTap: hasBio ? () => _showAuthorSheet(context, creator) : null,
      scaleTo: 0.94,
      child: SizedBox(
        width: 84,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A ring marks the ones that open a biography.
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: hasBio ? SeenlyPalette.accent.withOpacity(0.55) : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: avatar,
            ),
            const SizedBox(height: 6),
            Text(
              creator.displayName,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: SeenlyText.serif(size: 11.5).copyWith(height: 1.15),
            ),
            if (creator.role != null)
              Text(
                _roleLabel(creator.role!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
              ),
          ],
        ),
      ),
    );
  }

  /// "Story, Art" -> each part translated, rejoined.
  static String _roleLabel(String role) =>
      role.split(',').map((r) => r.trim().tr).join(', ');
}

void _showAuthorSheet(BuildContext context, TitleCreator c) {
  showModalBottomSheet(
    context: context,
    backgroundColor: SeenlyPalette.paper,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: SeenlyPalette.dashedBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (c.photoUrl != null) ...[
                    ClipOval(
                      child: SizedBox(
                        width: 68,
                        height: 68,
                        child: _NetImage(url: c.photoUrl, fallback: SeenlyPalette.cork),
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.displayName, style: SeenlyText.serif(size: 19, weight: FontWeight.w600)),
                        if (c.born != null) ...[
                          const SizedBox(height: 4),
                          Text(c.born!, style: SeenlyText.mono(size: 11, color: SeenlyPalette.placeholder)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(c.bio ?? '', style: SeenlyText.bodyText),
              const SizedBox(height: 14),
              Text('about the author from Open Library'.tr,
                  style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder)),
            ],
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Storyline (games) — long text, folded
// ---------------------------------------------------------------------------

class TitleStorylineSection extends StatefulWidget {
  final String text;
  const TitleStorylineSection({super.key, required this.text});

  @override
  State<TitleStorylineSection> createState() => _TitleStorylineSectionState();
}

class _TitleStorylineSectionState extends State<TitleStorylineSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (widget.text.trim().isEmpty) return const SizedBox.shrink();
    final long = widget.text.length > 220;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading('storyline'.tr),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: Text(
            widget.text,
            maxLines: (_open || !long) ? null : 4,
            overflow: (_open || !long) ? TextOverflow.visible : TextOverflow.ellipsis,
            style: SeenlyText.bodyText,
          ),
        ),
        if (long)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _open ? 'show less'.tr : 'read more'.tr,
                style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent, weight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tags — themes with the community's weight
// ---------------------------------------------------------------------------

class TitleTagsSection extends StatelessWidget {
  final List<TitleTag> tags;
  const TitleTagsSection({super.key, required this.tags});

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading('themes'.tr),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in tags)
              _Soft(
                // The stronger the community agrees, the warmer the chip.
                tint: t.rank == null
                    ? null
                    : SeenlyPalette.accent.withOpacity((0.35 + 0.65 * (t.rank! / 100)).clamp(0.0, 1.0)),
                radius: 16,
                elevation: 0.2,
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t.name.tr,
                        style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.ink, weight: FontWeight.w700)),
                    if (t.rank != null) ...[
                      const SizedBox(width: 6),
                      Text('${t.rank}%',
                          style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.placeholder)),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class TitleAltTitles extends StatelessWidget {
  final List<String> titles;
  const TitleAltTitles({super.key, required this.titles});

  @override
  Widget build(BuildContext context) {
    if (titles.isEmpty) return const SizedBox.shrink();
    return Text.rich(
      TextSpan(children: [
        TextSpan(
            text: '${'also known as'.tr}  ',
            style: SeenlyText.mono(size: 10, color: SeenlyPalette.placeholder)),
        TextSpan(text: titles.join(', '), style: SeenlyText.serif(italic: true, size: 12.5, color: SeenlyPalette.inkMuted)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Screenshots — a gallery that opens full screen
// ---------------------------------------------------------------------------

class TitleScreenshotsSection extends StatelessWidget {
  final List<String> urls;
  const TitleScreenshotsSection({super.key, required this.urls});

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading('screenshots'.tr),
        SizedBox(
          height: 118,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) => HorizontalReveal(
              delay: Duration(milliseconds: 40 * i.clamp(0, 8)),
              child: PressScale(
                onTap: () => _openViewer(context, i),
                scaleTo: 0.96,
                child: SizedBox(
                  width: 118 * 16 / 9,
                  child: DecoratedBox(
                    decoration: ClayBoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: SeenlyPalette.softShadow,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _NetImage(url: urls[i], fallback: SeenlyPalette.cork),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _openViewer(BuildContext context, int index) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black.withOpacity(0.92),
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => _ScreenshotViewer(urls: urls, initial: index),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }
}

class _ScreenshotViewer extends StatefulWidget {
  final List<String> urls;
  final int initial;
  const _ScreenshotViewer({required this.urls, required this.initial});

  @override
  State<_ScreenshotViewer> createState() => _ScreenshotViewerState();
}

class _ScreenshotViewerState extends State<_ScreenshotViewer> {
  late final PageController _controller = PageController(initialPage: widget.initial);
  late int _page = widget.initial;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: Image.network(
                    widget.urls[i],
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) => progress == null
                        ? child
                        : const Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                            ),
                          ),
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 36),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Text('${_page + 1} / ${widget.urls.length}',
                      style: SeenlyText.mono(size: 12, color: Colors.white70, weight: FontWeight.w700)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(color: Colors.white12, shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Languages (games) — is there a Russian version, in which way
// ---------------------------------------------------------------------------

class TitleLanguagesSection extends StatefulWidget {
  final List<GameLanguage> languages;
  const TitleLanguagesSection({super.key, required this.languages});

  @override
  State<TitleLanguagesSection> createState() => _TitleLanguagesSectionState();
}

class _TitleLanguagesSectionState extends State<TitleLanguagesSection> {
  static const int _collapsedRows = 5;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final langs = widget.languages;
    if (langs.isEmpty) return const SizedBox.shrink();
    final shown = _all ? langs : langs.take(_collapsedRows).toList();
    final hasMore = langs.length > _collapsedRows;
    final ru = langs.where((l) => l.isRussian).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading('languages'.tr),
        // The one line a Russian-speaking player is really asking about.
        if (LocaleService.appIsRussian || ru.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              ru.isEmpty
                  ? 'no Russian version'.tr
                  : [
                      if (ru.first.interface) 'interface'.tr,
                      if (ru.first.subtitles) 'subtitles'.tr,
                      if (ru.first.audio) 'voice-over'.tr,
                    ].join(' · '),
              style: SeenlyText.serif(italic: true, size: 13, color: ru.isEmpty ? SeenlyPalette.coral : SeenlyPalette.sage),
            ),
          ),
        _Soft(
          radius: 18,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(child: SizedBox.shrink()),
                  _colHead(Icons.tune_rounded, 'interface'.tr),
                  _colHead(Icons.subtitles_outlined, 'subtitles'.tr),
                  _colHead(Icons.mic_none_rounded, 'voice-over'.tr),
                ],
              ),
              const SizedBox(height: 6),
              for (final l in shown) _row(l),
              if (hasMore)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _all = !_all),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 2),
                    child: Text(
                      _all ? 'show less'.tr : '${'show all'.tr} (${langs.length})',
                      style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent, weight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _colHead(IconData icon, String label) => SizedBox(
        width: 54,
        child: Column(
          children: [
            Icon(icon, size: 15, color: SeenlyPalette.placeholder),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SeenlyText.mono(size: 8.5, color: SeenlyPalette.placeholder)),
          ],
        ),
      );

  Widget _row(GameLanguage l) {
    final highlight = l.isRussian;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1.5),
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: highlight
          ? BoxDecoration(
              color: SeenlyPalette.accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                _languageName(l.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SeenlyText.serif(size: 13, weight: highlight ? FontWeight.w700 : FontWeight.w500),
              ),
            ),
          ),
          _mark(l.interface),
          _mark(l.subtitles),
          _mark(l.audio),
        ],
      ),
    );
  }

  Widget _mark(bool on) => SizedBox(
        width: 54,
        child: Center(
          child: on
              ? Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: SeenlyPalette.accent, shape: BoxShape.circle),
                )
              : Container(
                  width: 8,
                  height: 1.5,
                  decoration: BoxDecoration(
                    color: SeenlyPalette.dashedBorder,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Time to beat (games)
// ---------------------------------------------------------------------------

class TitleTimeToBeatSection extends StatelessWidget {
  final TimeToBeat? timeToBeat;
  const TitleTimeToBeatSection({super.key, required this.timeToBeat});

  @override
  Widget build(BuildContext context) {
    final t = timeToBeat;
    if (t == null || t.isEmpty) return const SizedBox.shrink();
    final cells = <_BeatCell>[
      if (t.hastily != null) _BeatCell('story'.tr, t.hastily!, SeenlyPalette.sage),
      if (t.normally != null) _BeatCell('story + extras'.tr, t.normally!, SeenlyPalette.mustard),
      if (t.completely != null) _BeatCell('completionist'.tr, t.completely!, SeenlyPalette.coral),
    ];
    final longest = cells.map((c) => c.hours).reduce((a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading('time to beat'.tr),
        _Soft(
          radius: 18,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (int i = 0; i < cells.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: _beat(cells[i], longest)),
                  ],
                ],
              ),
              if ((t.votes ?? 0) > 0) ...[
                const SizedBox(height: 10),
                Text('${'based on'.tr} ${t.votes} ${'players'.tr}',
                    style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _beat(_BeatCell c, double longest) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(_hoursText(c.hours), style: SeenlyText.serif(size: 24, weight: FontWeight.w600)),
            const SizedBox(width: 3),
            Text('h'.tr, style: SeenlyText.mono(size: 11, color: SeenlyPalette.placeholder)),
          ],
        ),
        const SizedBox(height: 6),
        // A thin bar, scaled to the longest of the three, so the gap between
        // "just the story" and "everything" can be read at a glance.
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LayoutBuilder(
            builder: (context, box) => Stack(
              children: [
                Container(height: 5, width: box.maxWidth, color: SeenlyPalette.dashedBorder.withOpacity(0.5)),
                Container(
                  height: 5,
                  width: box.maxWidth * (c.hours / longest).clamp(0.08, 1.0),
                  color: c.color,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(c.label,
            maxLines: 2,
            style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkMuted).copyWith(height: 1.2)),
      ],
    );
  }
}

class _BeatCell {
  final String label;
  final double hours;
  final Color color;
  const _BeatCell(this.label, this.hours, this.color);
}

// ---------------------------------------------------------------------------
// Characters (manga / anime)
// ---------------------------------------------------------------------------

class TitleCharactersSection extends StatelessWidget {
  final List<TitleCharacter> characters;
  const TitleCharactersSection({super.key, required this.characters});

  @override
  Widget build(BuildContext context) {
    if (characters.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading('characters'.tr),
        SizedBox(
          height: 156,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: characters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) => HorizontalReveal(
              delay: Duration(milliseconds: 40 * i.clamp(0, 8)),
              child: _CharacterTile(character: characters[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _CharacterTile extends StatelessWidget {
  final TitleCharacter character;
  const _CharacterTile({required this.character});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: _NetImage(url: character.photoUrl, fallback: SeenlyPalette.accent),
            ),
          ),
          const SizedBox(height: 6),
          Text(character.displayName,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: SeenlyText.serif(size: 11)),
          if (character.role != null)
            Text(character.role!.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SeenlyText.mono(
                  size: 9,
                  color: character.role == 'Main' ? SeenlyPalette.accent : SeenlyPalette.placeholder,
                )),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Links — where to play / read / buy
// ---------------------------------------------------------------------------

class TitleLinksSection extends StatelessWidget {
  final MediaItem item;
  const TitleLinksSection({super.key, required this.item});

  static bool hasContent(MediaItem item) => (item.extras?.links ?? const []).isNotEmpty;

  static IconData _icon(String kind) {
    switch (kind) {
      case 'steam':
      case 'gog':
      case 'epic':
      case 'playstation':
      case 'xbox':
      case 'nintendo':
      case 'itch':
        return Icons.sports_esports_outlined;
      case 'store':
      case 'buy':
        return Icons.shopping_bag_outlined;
      case 'official':
        return Icons.language_rounded;
      case 'wiki':
        return Icons.menu_book_outlined;
      case 'read':
        return Icons.auto_stories_outlined;
      case 'preview':
        return Icons.chrome_reader_mode_outlined;
      default:
        return Icons.open_in_new_rounded;
    }
  }

  /// Brand names stay as they are; generic labels are translated.
  static String _label(TitleLink l) {
    switch (l.kind) {
      case 'official':
      case 'wiki':
      case 'preview':
        return l.label.tr;
      default:
        return l.label;
    }
  }

  @override
  Widget build(BuildContext context) {
    final links = item.extras?.links ?? const <TitleLink>[];
    if (links.isEmpty) return const SizedBox.shrink();
    final heading = item.mediaType == 'game'
        ? 'where to play'.tr
        : (item.mediaType == 'manga' ? 'where to read'.tr : 'read or buy'.tr);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(heading),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final l in links)
              PressScale(
                onTap: () => _openUrl(context, l.url),
                scaleTo: 0.95,
                child: _Soft(
                  radius: 16,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_icon(l.kind), size: 15, color: SeenlyPalette.accent),
                      const SizedBox(width: 7),
                      Text(_label(l),
                          style: SeenlyText.mono(size: 12, color: SeenlyPalette.ink, weight: FontWeight.w700)),
                      const SizedBox(width: 5),
                      Icon(Icons.north_east_rounded, size: 12, color: SeenlyPalette.placeholder),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Readers (books) — what other people do with this book + its first line
// ---------------------------------------------------------------------------

class TitleReadersSection extends StatelessWidget {
  final TitleExtras extras;
  const TitleReadersSection({super.key, required this.extras});

  static bool hasContent(MediaItem item) {
    final x = item.extras;
    if (x == null) return false;
    return (x.readingLog != null && !x.readingLog!.isEmpty) || (x.firstSentence ?? '').isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final log = extras.readingLog;
    final first = extras.firstSentence;
    final hasLog = log != null && !log.isEmpty;
    if (!hasLog && (first ?? '').isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasLog) ...[
          _SectionHeading('readers'.tr),
          _Soft(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            child: Row(
              children: [
                if ((log!.want ?? 0) > 0) _stat(Icons.bookmark_border_rounded, log.want!, 'want to read'.tr),
                if ((log.reading ?? 0) > 0) _stat(Icons.auto_stories_outlined, log.reading!, 'reading'.tr),
                if ((log.read ?? 0) > 0) _stat(Icons.check_circle_outline_rounded, log.read!, 'have read'.tr),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text('reader counts from Open Library'.tr,
              style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder)),
          if ((first ?? '').isNotEmpty) const SizedBox(height: 18),
        ],
        if ((first ?? '').isNotEmpty) ...[
          _SectionHeading('first line'.tr),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: SeenlyPalette.accent.withOpacity(0.5), width: 2.5)),
            ),
            child: Text(
              first!,
              style: SeenlyText.serif(italic: true, size: 14, color: SeenlyPalette.inkMuted).copyWith(height: 1.5),
            ),
          ),
        ],
      ],
    );
  }

  Widget _stat(IconData icon, int n, String label) => Expanded(
        child: Column(
          children: [
            Icon(icon, size: 18, color: SeenlyPalette.accent),
            const SizedBox(height: 6),
            Text(_compact(n), style: SeenlyText.serif(size: 18, weight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkMuted).copyWith(height: 1.2)),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// Related — sequels, adaptations, DLC, the rest of the series
// ---------------------------------------------------------------------------

class TitleRelatedSection extends StatelessWidget {
  final List<RelatedTitle> related;
  final void Function(RelatedTitle) onOpen;
  const TitleRelatedSection({super.key, required this.related, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    if (related.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading('connected works'.tr),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: related.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final r = related[i];
              return HorizontalReveal(
                delay: Duration(milliseconds: 40 * i.clamp(0, 8)),
                child: SizedBox(
                  width: 92,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 138,
                        child: ThemedPosterTile(
                          title: r.displayTitle,
                          posterUrl: r.posterUrl,
                          mediaType: r.mediaType,
                          fallbackColor: SeenlyPalette.gridColorFor(i),
                          onTap: () => onOpen(r),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(r.relation.tr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.accent, weight: FontWeight.w700)),
                      if (r.year != null)
                        Text('${r.year}', style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// System requirements + Steam Deck (games)
// ---------------------------------------------------------------------------

class TitleRequirementsSection extends StatefulWidget {
  final SystemRequirements? requirements;
  final List<String> platforms;
  final String? deck;
  const TitleRequirementsSection({
    super.key,
    required this.requirements,
    this.platforms = const [],
    this.deck,
  });

  static bool hasContent(TitleExtras x) =>
      (x.requirements != null && !x.requirements!.isEmpty) ||
      x.steamDeck == 'verified' ||
      x.steamDeck == 'playable' ||
      x.steamDeck == 'unsupported';

  @override
  State<TitleRequirementsSection> createState() => _TitleRequirementsSectionState();
}

class _TitleRequirementsSectionState extends State<TitleRequirementsSection> {
  bool _showRecommended = false;

  static String _specLabel(String label) => label.isEmpty ? '' : label.tr;

  String? _deckSentence() {
    switch (widget.deck) {
      case 'verified':
        return 'Steam Deck verified — plays great out of the box'.tr;
      case 'playable':
        return 'Steam Deck playable — may need a few tweaks'.tr;
      case 'unsupported':
        return "Steam Deck unsupported — Valve says it won't run well".tr;
      default:
        return null;
    }
  }

  Color _deckColor() {
    switch (widget.deck) {
      case 'verified':
        return SeenlyPalette.sage;
      case 'playable':
        return SeenlyPalette.mustard;
      default:
        return SeenlyPalette.coral;
    }
  }

  static IconData _platformIcon(String p) {
    switch (p) {
      case 'mac':
        return Icons.laptop_mac_rounded;
      case 'linux':
        return Icons.terminal_rounded;
      default:
        return Icons.desktop_windows_outlined;
    }
  }

  static String _platformName(String p) {
    switch (p) {
      case 'mac':
        return 'macOS';
      case 'linux':
        return 'Linux';
      default:
        return 'Windows';
    }
  }

  @override
  Widget build(BuildContext context) {
    final reqs = widget.requirements;
    final hasReqs = reqs != null && !reqs.isEmpty;
    final deckLine = _deckSentence();
    if (!hasReqs && deckLine == null) return const SizedBox.shrink();

    final both = hasReqs && reqs.minimum.isNotEmpty && reqs.recommended.isNotEmpty;
    final rows = !hasReqs
        ? const <SpecRow>[]
        : (_showRecommended && reqs.recommended.isNotEmpty
            ? reqs.recommended
            : (reqs.minimum.isNotEmpty ? reqs.minimum : reqs.recommended));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading('system requirements'.tr),
        if (deckLine != null)
          Padding(
            padding: EdgeInsets.only(bottom: hasReqs ? 10 : 0),
            child: _Soft(
              tint: _deckColor(),
              radius: 16,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  Icon(Icons.videogame_asset_outlined, size: 18, color: _deckColor()),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(deckLine,
                        style: SeenlyText.serif(italic: true, size: 13, color: SeenlyPalette.ink)),
                  ),
                ],
              ),
            ),
          ),
        if (hasReqs)
          _Soft(
            radius: 18,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (both) ...[
                  Row(
                    children: [
                      _Tab(
                        label: 'minimum'.tr,
                        on: !_showRecommended,
                        onTap: () => setState(() => _showRecommended = false),
                      ),
                      const SizedBox(width: 8),
                      _Tab(
                        label: 'recommended'.tr,
                        on: _showRecommended,
                        onTap: () => setState(() => _showRecommended = true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Column(
                    key: ValueKey(_showRecommended),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final r in rows)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (r.label.isNotEmpty)
                                SizedBox(
                                  width: 86,
                                  child: Text(_specLabel(r.label),
                                      style: SeenlyText.mono(
                                          size: 10.5, color: SeenlyPalette.inkMuted, weight: FontWeight.w700)),
                                ),
                              Expanded(
                                child: Text(r.value,
                                    style: SeenlyText.serif(size: 12.5).copyWith(height: 1.3)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.platforms.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      for (final p in widget.platforms)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_platformIcon(p), size: 13, color: SeenlyPalette.placeholder),
                            const SizedBox(width: 5),
                            Text(_platformName(p),
                                style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.placeholder)),
                          ],
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _Tab({required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: on ? SeenlyPalette.accent.withOpacity(0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: SeenlyText.mono(
            size: 11,
            color: on ? SeenlyPalette.accent : SeenlyPalette.placeholder,
            weight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slots — where each group sits on the title screen
// ---------------------------------------------------------------------------

/// The title screen has fixed anchor points (after the genre chips, after the
/// synopsis, after the cast ...). Each slot below renders the sections that
/// belong at that point — with their own spacing and scroll-reveal — and
/// collapses to nothing when none of them has content. That keeps
/// title_detail_screen.dart to one line per anchor instead of a condition per
/// section, and puts the order of the whole extras layer in one place.
enum TitleExtrasSlot { facts, story, people, gallery, links, readers, connected }

class TitleExtrasBlock extends StatelessWidget {
  final MediaItem item;
  final TitleExtrasSlot slot;
  final void Function(RelatedTitle)? onOpenRelated;
  const TitleExtrasBlock({
    super.key,
    required this.item,
    required this.slot,
    this.onOpenRelated,
  });

  @override
  Widget build(BuildContext context) {
    final x = item.extras;
    if (x == null) return const SizedBox.shrink();
    final sections = <Widget>[];
    // Sections below the fold fade up as they scroll in, like the cast and
    // trailers shelves; the ones right under the genre chips don't, so the
    // top of the card is settled the moment it appears.
    final reveal = slot != TitleExtrasSlot.facts;

    void add(Widget w, {double gap = 20}) {
      sections.add(reveal ? ScrollReveal(riseBy: 12, child: w) : w);
      sections.add(SizedBox(height: gap));
    }

    switch (slot) {
      case TitleExtrasSlot.facts:
        if (TitleHighlights.hasContent(item)) add(TitleHighlights(item: item), gap: 18);
        if (TitleCreatorsSection.hasContent(item)) add(TitleCreatorsSection(item: item), gap: 18);
        break;
      case TitleExtrasSlot.story:
        if ((x.storyline ?? '').isNotEmpty && item.mediaType == 'game') {
          add(TitleStorylineSection(text: x.storyline!));
        }
        if (x.tags.isNotEmpty) add(TitleTagsSection(tags: x.tags));
        if (x.altTitles.isNotEmpty) add(TitleAltTitles(titles: x.altTitles));
        break;
      case TitleExtrasSlot.people:
        if (x.characters.isNotEmpty) add(TitleCharactersSection(characters: x.characters));
        break;
      case TitleExtrasSlot.gallery:
        if (x.screenshots.isNotEmpty) add(TitleScreenshotsSection(urls: x.screenshots));
        if (x.timeToBeat != null && !x.timeToBeat!.isEmpty) {
          add(TitleTimeToBeatSection(timeToBeat: x.timeToBeat));
        }
        if (x.languages.isNotEmpty) add(TitleLanguagesSection(languages: x.languages));
        if (TitleRequirementsSection.hasContent(x)) {
          add(TitleRequirementsSection(
            requirements: x.requirements,
            platforms: x.pcPlatforms,
            deck: x.steamDeck,
          ));
        }
        break;
      case TitleExtrasSlot.links:
        if (TitleLinksSection.hasContent(item)) add(TitleLinksSection(item: item));
        break;
      case TitleExtrasSlot.readers:
        if (TitleReadersSection.hasContent(item)) add(TitleReadersSection(extras: x));
        break;
      case TitleExtrasSlot.connected:
        if (x.related.isNotEmpty && onOpenRelated != null) {
          add(TitleRelatedSection(related: x.related, onOpen: onOpenRelated!));
        }
        break;
    }
    if (sections.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: sections);
  }
}
