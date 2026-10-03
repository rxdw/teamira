import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/co_view_entry.dart';
import '../../../models/watchlist_entry.dart';
import '../../../services/api_client.dart';
import '../../../services/partner_service.dart';
import '../../../state/app_state.dart';
import '../../../theme/clay_kit.dart';
import '../../../theme/palette.dart';
import '../../../theme/text_styles.dart';
import '../../../widgets/wow_motion.dart';
import 'play/play_start_panel.dart';
import 'reading/reading_start_panel.dart';
import 'room_launcher.dart';
import 'room_strings.dart';

/// "что смотрим?" / "что читаем?" — the one sheet behind the big card's
/// "начать". Up top you pick *watch* or *read*; reading has its own panel
/// (reading/reading_start_panel.dart). For watching there are three ways to
/// choose, from the cosiest to the most manual:
///  * something you already planned together (opens as a parallel room),
///  * a video from your sources (plays inside the app),
///  * a link someone pasted (YouTube, Twitch, or a direct file).
Future<void> showRoomStartSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _StartSheet(),
  );
}

class _StartSheet extends StatefulWidget {
  const _StartSheet();

  @override
  State<_StartSheet> createState() => _StartSheetState();
}

class _StartSheetState extends State<_StartSheet> {
  int _what = 0; // 0 watch, 1 read, 2 play
  int _tab = 0; // 0 planned, 1 sources, 2 link
  List<CoViewEntry>? _planned;
  List<WatchlistEntry>? _videos;
  final _link = TextEditingController();
  final _title = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadPlanned();
    _loadVideos();
  }

  Future<void> _loadPlanned() async {
    try {
      final list = await PartnerService(ApiClient.instance).coViewing();
      if (mounted) setState(() => _planned = list.planned);
    } catch (_) {
      if (mounted) setState(() => _planned = const []);
    }
  }

  Future<void> _loadVideos() async {
    try {
      final c = await context.read<AppState>().sources.collections();
      final all = [...c.watching, ...c.watchLater, ...c.watched].where((e) => e.source == 'youtube' || e.source == 'twitch');
      final seen = <String>{};
      final unique = [for (final e in all) if (seen.add('${e.source}:${e.mediaId}')) e];
      if (mounted) setState(() => _videos = unique);
    } catch (_) {
      if (mounted) setState(() => _videos = const []);
    }
  }

  @override
  void dispose() {
    _link.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _go(Future<void> Function() launch) async {
    if (_busy) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    nav.pop();
    await launch();
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: ClayBoxDecoration(
          color: SeenlyPalette.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: SeenlyPalette.border),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: SeenlyPalette.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 14),
            Text(
              switch (_what) {
                1 => at('что читаем?', 'what are we reading?'),
                2 => at('во что играем?', 'what are we playing?'),
                _ => at('что смотрим?', 'what are we watching?'),
              },
              style: SeenlyText.serif(size: 19, weight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                for (final (i, label, icon) in [
                  (0, at('смотреть', 'watch'), Icons.live_tv_rounded),
                  (1, at('читать', 'read'), Icons.menu_book_rounded),
                  (2, at('играть', 'play'), Icons.sports_esports_rounded),
                ])
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                      child: PressScale(
                        onTap: () => setState(() => _what = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: ClayBoxDecoration(
                            color: _what == i ? SeenlyPalette.accent : SeenlyPalette.paper,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: _what == i ? SeenlyPalette.accent : SeenlyPalette.border),
                          ),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(icon, size: 16, color: _what == i ? SeenlyPalette.accentOnAccent : SeenlyPalette.inkMuted),
                            const SizedBox(width: 5),
                            Text(label,
                                style: SeenlyText.serif(
                                    size: 14.5,
                                    weight: FontWeight.w600,
                                    color: _what == i ? SeenlyPalette.accentOnAccent : SeenlyPalette.inkMuted)),
                          ]),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            if (_what == 2)
              Expanded(
                child: PlayStartPanel(
                  planned: _planned,
                  onPlanned: (e) => _go(() => RoomLauncher.startForPlanned(context, e)),
                  onManual: (title, platform) {
                    final host = Navigator.of(context).context;
                    _go(() => RoomLauncher.startPlay(host, title: title, platform: platform));
                  },
                ),
              )
            else if (_what == 1)
              Expanded(
                child: ReadingStartPanel(
                  onStart: (r) {
                    // The sheet is about to close; the room opens from the
                    // navigator's own context, which outlives it.
                    final host = Navigator.of(context).context;
                    _go(() => RoomLauncher.startReading(
                          host,
                          mediaType: r.mediaType,
                          title: r.title,
                          kind: r.kind,
                          contentHash: r.contentHash,
                          units: r.units,
                          mode: r.mode,
                        ));
                  },
                ),
              )
            else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                for (final (i, label) in [
                  at('запланированное', 'planned'),
                  at('мои источники', 'my sources'),
                  at('по ссылке', 'from a link'),
                ].indexed)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: i == 2 ? 0 : 8),
                      child: PressScale(
                        onTap: () => setState(() => _tab = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _tab == i ? SeenlyPalette.accent.withOpacity(0.14) : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _tab == i ? SeenlyPalette.accent.withOpacity(0.5) : SeenlyPalette.border),
                          ),
                          child: Text(label,
                              style: SeenlyText.serif(
                                  size: 13,
                                  italic: true,
                                  weight: _tab == i ? FontWeight.w600 : FontWeight.w500,
                                  color: _tab == i ? SeenlyPalette.accent : SeenlyPalette.inkMuted)),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 260), child: _body())),
            ],
          ],
        ),
      ),
    );
  }

  Widget _body() {
    switch (_tab) {
      case 0:
        return _listOr(
          key: const ValueKey('planned'),
          loading: _planned == null,
          empty: at('пока ничего не запланировано — добавьте фильм в «запланировано» или вставьте ссылку',
              'nothing planned yet — add a film to “planned” or paste a link'),
          children: [
            for (final e in _planned ?? const <CoViewEntry>[])
              _Row(
                title: (e.titleRu ?? e.titleEn ?? ''),
                subtitle: at('каждый включает у себя, мы синхронизируем', 'each of you plays it, we keep it in sync'),
                imageUrl: e.posterUrl,
                onTap: () => _go(() => RoomLauncher.startForPlanned(context, e)),
              ),
          ],
        );
      case 1:
        return _listOr(
          key: const ValueKey('sources'),
          loading: _videos == null,
          empty: at('в «your sources» пока нет видео', 'no videos in “your sources” yet'),
          children: [
            for (final v in _videos ?? const <WatchlistEntry>[])
              _Row(
                title: v.displayTitle,
                subtitle: v.source == 'twitch'
                    ? at('запись twitch · общий таймер', 'twitch recording · shared clock')
                    : at('youtube · играет прямо в приложении', 'youtube · plays right in the app'),
                imageUrl: v.posterUrl,
                wide: true,
                onTap: () => _go(() => RoomLauncher.startForVideo(
                      context,
                      source: v.source,
                      videoId: v.mediaId,
                      title: v.displayTitle,
                      thumbnailUrl: v.posterUrl,
                    )),
              ),
          ],
        );
      default:
        return ListView(
          key: const ValueKey('link'),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              at('вставьте ссылку на youtube, запись twitch или прямую ссылку на видео (https)',
                  'paste a youtube link, a twitch recording or a direct video link (https)'),
              style: SeenlyText.serif(size: 13.5, italic: true, color: SeenlyPalette.inkMuted),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: clayWellDecoration(radius: 22),
              child: TextField(
                controller: _link,
                keyboardType: TextInputType.url,
                style: SeenlyText.serif(size: 15),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'https://…',
                  hintStyle: SeenlyText.serif(size: 15, italic: true, color: SeenlyPalette.placeholder),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: clayWellDecoration(radius: 22),
              child: TextField(
                controller: _title,
                style: SeenlyText.serif(size: 15),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: at('название — по желанию', 'title — optional'),
                  hintStyle: SeenlyText.serif(size: 15, italic: true, color: SeenlyPalette.placeholder),
                ),
              ),
            ),
            const SizedBox(height: 18),
            PressScale(
              haptics: true,
              onTap: () {
                if (_link.text.trim().isEmpty) return;
                _go(() => RoomLauncher.startForLink(context, _link.text, title: _title.text));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                alignment: Alignment.center,
                decoration: ClayBoxDecoration(color: SeenlyPalette.accent, borderRadius: BorderRadius.circular(22)),
                child: Text(at('открыть комнату', 'open the room'),
                    style: SeenlyText.serif(size: 16, weight: FontWeight.w600, color: SeenlyPalette.accentOnAccent)),
              ),
            ),
          ],
        );
    }
  }

  Widget _listOr({required Key key, required bool loading, required String empty, required List<Widget> children}) {
    if (loading) return Center(key: key, child: const CircularProgressIndicator(strokeWidth: 2));
    if (children.isEmpty) {
      return Center(
        key: key,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(empty, textAlign: TextAlign.center, style: SeenlyText.serif(size: 14, italic: true, color: SeenlyPalette.placeholder)),
        ),
      );
    }
    return ListView.separated(
      key: key,
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
      itemCount: children.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => children[i],
    );
  }
}

class _Row extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? imageUrl;
  final bool wide;
  final VoidCallback onTap;
  const _Row({required this.title, required this.subtitle, required this.imageUrl, required this.onTap, this.wide = false});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      scaleTo: 0.98,
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
              width: wide ? 96 : 50,
              height: wide ? 56 : 72,
              child: imageUrl == null
                  ? ColoredBox(color: SeenlyPalette.cork)
                  : FadeInNetworkImage(url: imageUrl!, placeholder: ColoredBox(color: SeenlyPalette.cork)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: SeenlyText.serif(size: 15, weight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(subtitle, maxLines: 2, style: SeenlyText.serif(size: 12, italic: true, color: SeenlyPalette.inkFaint)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: SeenlyPalette.inkFaint),
        ]),
      ),
    );
  }
}
