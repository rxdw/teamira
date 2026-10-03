import 'package:flutter/material.dart';

import '../../../models/pair_album.dart';
import '../../../services/api_client.dart';
import '../../../services/error_text.dart';
import '../../../services/locale_service.dart';
import '../../../services/pair_album_service.dart';
import '../../../theme/palette.dart';
import '../../../theme/text_styles.dart';
import '../../../utils/album_dates.dart';
import '../../../widgets/themed_loading_indicator.dart';
import '../../../widgets/themed_pull_to_refresh.dart';
import '../../../widgets/wow_motion.dart';
import 'album_anniversary_screen.dart';
import 'album_book_screen.dart';
import 'album_capsules_screen.dart';
import 'album_paywall.dart';
import 'album_strings.dart';
import 'album_widgets.dart';

/// The card on the co-viewing screen's "мы" tab. Loads the album status
/// itself and draws nothing for a circle that isn't a couple (an album is
/// for exactly two) or while the status is loading/failed — the entry
/// point should never be the thing that errors.
///
/// A free couple sees the card too: it's the pitch. Tapping opens the home
/// screen, where everything already written stays readable, and any write
/// answers with the paywall.
class AlbumEntryCard extends StatefulWidget {
  const AlbumEntryCard({super.key});

  @override
  State<AlbumEntryCard> createState() => _AlbumEntryCardState();
}

class _AlbumEntryCardState extends State<AlbumEntryCard> {
  late final PairAlbumService _service = PairAlbumService(ApiClient.instance);
  AlbumStatus? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await _service.status();
      if (mounted) setState(() => _status = s);
    } catch (_) {
      // Stay hidden; the hub has plenty else to show.
    }
  }

  Future<void> _open() async {
    final s = _status;
    if (s == null) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AlbumHomeScreen(status: s)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    if (s == null || !s.isCouple) return const SizedBox.shrink();
    final partner = s.partner?.name ?? at('партнёр', 'partner');

    String subtitle;
    if (s.unreadPages > 0) {
      subtitle = at('${partner} оставил(а) записку — откройте', '$partner left you a note — open it');
    } else if (s.capsulesReady > 0) {
      subtitle = at('капсула готова к открытию', 'a capsule is ready to open');
    } else if (s.waitingPartner > 0) {
      subtitle = at('${partner} оставил(а) записку — она откроется после вечера',
          '$partner left a note — it opens after your evening');
    } else if (!s.isPremium && !s.hasContent) {
      subtitle = at('попробуйте бесплатно: записки и капсула для вас двоих',
          'try it free: notes and a capsule for the two of you');
    } else if (s.daysTogether != null) {
      subtitle = at('вместе ${daysLabel(s.daysTogether!)}', 'together ${daysLabel(s.daysTogether!)}');
    } else {
      subtitle = at('записки, капсулы и годовщина', 'notes, capsules and your anniversary');
    }

    return Entrance(
      delay: const Duration(milliseconds: 80),
      child: PressScale(
        onTap: _open,
        scaleTo: 0.98,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                SeenlyPalette.coral.withOpacity(0.16),
                SeenlyPalette.accent.withOpacity(0.10),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: SeenlyPalette.coral.withOpacity(0.28)),
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(Icons.menu_book_rounded, color: SeenlyPalette.coral, size: 24),
                  if (s.hasNews)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: BreathingGlow(
                        color: SeenlyPalette.coral,
                        size: 22,
                        maxOpacity: 0.5,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: SeenlyPalette.coral,
                            shape: BoxShape.circle,
                            border: Border.all(color: SeenlyPalette.paper, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(at('альбом пары', 'pair album'),
                            style: SeenlyText.serif(size: 15, weight: FontWeight.w600)),
                        if (!s.isPremium && !s.canWriteNote && !s.canCreateCapsule) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: SeenlyPalette.accent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'premium',
                              style: SeenlyText.mono(
                                size: 9.5,
                                weight: FontWeight.w700,
                                color: SeenlyPalette.accentOnAccent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkFaint),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: SeenlyPalette.inkFaint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// The album's front page: the two of you, and three doors — the book, the
/// capsules, the anniversary.
class AlbumHomeScreen extends StatefulWidget {
  final AlbumStatus status;
  const AlbumHomeScreen({super.key, required this.status});

  @override
  State<AlbumHomeScreen> createState() => _AlbumHomeScreenState();
}

class _AlbumHomeScreenState extends State<AlbumHomeScreen> {
  late final PairAlbumService _service = PairAlbumService(ApiClient.instance);
  late AlbumStatus _status = widget.status;
  bool _loading = false;

  Future<void> _refresh() async {
    try {
      final s = await _service.status();
      if (mounted) setState(() => _status = s);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  Future<void> _go(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final ru = LocaleService.appIsRussian;
    final s = _status;
    final since = s.togetherSince;
    final partner = s.partner?.name ?? at('партнёр', 'partner');

    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      body: SafeArea(
        child: ThemedPullToRefresh(
          onRefresh: _refresh,
          child: _loading
              ? const Center(child: ThemedLoadingIndicator())
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconButton(
                        padding: EdgeInsets.zero,
                        alignment: Alignment.centerLeft,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.arrow_back, size: 20, color: SeenlyPalette.ink),
                      ),
                      Entrance(
                        child: Center(
                          child: Column(
                            children: [
                              PairAvatars(people: s.people, size: 68),
                              const SizedBox(height: 14),
                              Text(at('альбом пары', 'pair album'), style: SeenlyText.screenTitle),
                              const SizedBox(height: 4),
                              Text(
                                since != null
                                    ? at('вместе с ${albumDateLabel(since, ru: ru)}',
                                        'together since ${albumDateLabel(since, ru: ru)}')
                                    : at('всё, что вы копите вдвоём', 'everything the two of you keep'),
                                style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!s.isPremium) ...[
                        const SizedBox(height: 18),
                        Entrance(
                          delay: const Duration(milliseconds: 100),
                          child: PressScale(
                            onTap: () => showAlbumPaywall(context, source: 'pair_album_home'),
                            scaleTo: 0.98,
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: SeenlyPalette.accent.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: SeenlyPalette.accent.withOpacity(0.25)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.auto_awesome, color: SeenlyPalette.accent, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _freeBannerText(s),
                                      style: SeenlyText.mono(size: 11.5, color: SeenlyPalette.inkMuted),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      Entrance(
                        delay: const Duration(milliseconds: 160),
                        riseBy: 18,
                        child: _DoorCard(
                          icon: Icons.mail_rounded,
                          color: SeenlyPalette.coral,
                          title: at('общая книга', 'our book'),
                          subtitle: _bookSubtitle(s, partner),
                          badge: s.unreadPages > 0 ? '${s.unreadPages}' : null,
                          onTap: () => _go(AlbumBookScreen(status: s)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Entrance(
                        delay: const Duration(milliseconds: 260),
                        riseBy: 18,
                        child: _DoorCard(
                          icon: Icons.lock_clock_rounded,
                          color: SeenlyPalette.periwinkle,
                          title: at('капсулы времени', 'time capsules'),
                          subtitle: _capsuleSubtitle(s),
                          badge: s.capsulesReady > 0 ? '${s.capsulesReady}' : null,
                          onTap: () => _go(AlbumCapsulesScreen(status: s)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Entrance(
                        delay: const Duration(milliseconds: 360),
                        riseBy: 18,
                        child: _DoorCard(
                          icon: Icons.favorite_rounded,
                          color: SeenlyPalette.pink,
                          title: at('наша годовщина', 'our anniversary'),
                          subtitle: since == null
                              ? at('выберите день, с которого всё началось', 'pick the day it all began')
                              : at('вместе ${daysLabel(s.daysTogether ?? 0)}',
                                  'together ${daysLabel(s.daysTogether ?? 0)}'),
                          onTap: () => _go(AlbumAnniversaryScreen(status: s)),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  /// What the banner for a circle without a plan says: what's still free
  /// while there's something left, and what a plan adds once there isn't.
  /// Either way, what's already written stays readable.
  String _freeBannerText(AlbumStatus s) {
    final notes = s.notesLeft;
    final notesLimit = s.notesLimit;
    final capsules = s.capsulesLeft;
    final capsulesLimit = s.capsulesLimit;
    final anythingLeft = s.canWriteNote || s.canCreateCapsule;
    if (anythingLeft && notes != null && notesLimit != null && capsules != null && capsulesLimit != null) {
      return at(
        'осталось бесплатно: записок — $notes из $notesLimit, капсул — $capsules из $capsulesLimit. '
            'без счёта и с годовщиной — подписка на двоих',
        'free left: notes — $notes of $notesLimit, capsules — $capsules of $capsulesLimit. '
            'unlimited, plus your anniversary, comes with a plan for two',
      );
    }
    return at(
      'бесплатное закончилось. чтобы писать дальше и отметить годовщину — подписка на двоих. '
          'уже написанное вы всегда сможете читать',
      'the free part is used up. to keep writing and mark your anniversary you need '
          'a plan for two. whatever\'s already written stays readable',
    );
  }

  String _bookSubtitle(AlbumStatus s, String partner) {
    if (s.unreadPages > 0) {
      return at('новые записки от $partner', 'new notes from $partner');
    }
    if (s.waitingPartner > 0 || s.waitingMine > 0) {
      return at('ждут вечера: ${s.waitingMine + s.waitingPartner}',
          'waiting for their evening: ${s.waitingMine + s.waitingPartner}');
    }
    if (s.pagesCount > 0) {
      return at('страниц: ${s.pagesCount}', 'pages: ${s.pagesCount}');
    }
    return at('записки друг другу перед вечером', 'notes for each other before an evening');
  }

  String _capsuleSubtitle(AlbumStatus s) {
    if (s.capsulesReady > 0) return at('можно открывать', 'ready to open');
    if (s.capsulesSealed > 0) return at('запечатано: ${s.capsulesSealed}', 'sealed: ${s.capsulesSealed}');
    return at('письма себе-будущим — откроете через год', 'letters to your future selves');
  }
}

class _DoorCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;
  const _DoorCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      haptics: true,
      scaleTo: 0.98,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: SeenlyPalette.border),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withOpacity(0.16),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: SeenlyText.serif(size: 17, weight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted),
                  ),
                ],
              ),
            ),
            if (badge != null)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: SeenlyPalette.coral, borderRadius: BorderRadius.circular(10)),
                child: Text(
                  badge!,
                  style: SeenlyText.mono(size: 11.5, weight: FontWeight.w700, color: Colors.white),
                ),
              ),
            Icon(Icons.chevron_right, color: SeenlyPalette.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// Opens the album from somewhere that has no [AlbumStatus] in hand — a
/// push notification tap. Fetches the status, then hands over to
/// [AlbumHomeScreen]; a failure (or a circle that isn't a couple any more,
/// e.g. the link was ended after the push was sent) lands on a short
/// message instead of an empty screen.
class AlbumHomeLoader extends StatefulWidget {
  const AlbumHomeLoader({super.key});

  @override
  State<AlbumHomeLoader> createState() => _AlbumHomeLoaderState();
}

class _AlbumHomeLoaderState extends State<AlbumHomeLoader> {
  late final Future<AlbumStatus> _future = PairAlbumService(ApiClient.instance).status();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AlbumStatus>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasData && snap.data!.isCouple) {
          return AlbumHomeScreen(status: snap.data!);
        }
        final failed = snap.hasError || (snap.hasData && !snap.data!.isCouple);
        return Scaffold(
          backgroundColor: SeenlyPalette.background,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.arrow_back, size: 20, color: SeenlyPalette.ink),
                ),
                Expanded(
                  child: Center(
                    child: failed
                        ? Padding(
                            padding: const EdgeInsets.all(28),
                            child: Text(
                              snap.hasError
                                  ? describeError(snap.error!)
                                  : at('альбом больше недоступен — связь между вами закрыта',
                                      'the album is gone — the link between you was ended'),
                              textAlign: TextAlign.center,
                              style: SeenlyText.emptyState(),
                            ),
                          )
                        : const ThemedLoadingIndicator(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
