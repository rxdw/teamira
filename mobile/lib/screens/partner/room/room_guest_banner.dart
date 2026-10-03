import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/co_view_room.dart';
import '../../../services/api_client.dart';
import '../../../services/co_view_room_service.dart';
import '../../../services/error_text.dart';
import '../../../theme/clay_kit.dart';
import '../../../theme/palette.dart';
import '../../../theme/text_styles.dart';
import '../../../widgets/wow_motion.dart';
import 'room_launcher.dart';
import 'room_strings.dart';

/// "аня зовёт вас смотреть «…»" — the invitation a friend sent to join their
/// room as a guest. It lives at the top of Home rather than on the circle's
/// screen because a guest need not be in any circle: this is the one place
/// everyone sees. It stays quiet (draws nothing, costs one tiny request every
/// quarter-minute) until somebody actually invites you, and goes away the
/// moment the room closes or you answer.
class RoomGuestInviteBanner extends StatefulWidget {
  const RoomGuestInviteBanner({super.key});

  @override
  State<RoomGuestInviteBanner> createState() => _RoomGuestInviteBannerState();
}

class _RoomGuestInviteBannerState extends State<RoomGuestInviteBanner> with WidgetsBindingObserver {
  final _service = CoViewRoomService(ApiClient.instance);
  List<GuestInvite> _invites = const [];
  final Set<String> _answering = {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final list = await _service.myInvites();
      if (mounted) setState(() => _invites = list);
    } catch (_) {
      // Silent on purpose: an invitation banner that errors at people is worse than none.
    }
  }

  Future<void> _join(GuestInvite i) async {
    if (_answering.contains(i.roomId)) return;
    setState(() => _answering.add(i.roomId));
    try {
      await RoomLauncher.enterAsGuest(context, i.roomId);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    } finally {
      if (mounted) setState(() => _answering.remove(i.roomId));
      _refresh();
    }
  }

  Future<void> _decline(GuestInvite i) async {
    setState(() => _invites = _invites.where((x) => x.roomId != i.roomId).toList());
    try {
      // "me": the server reads it as the caller, so no user id is needed here.
      await _service.removeGuest(i.roomId, 'me');
    } catch (_) {}
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return AnimatedSize(
      duration: Duration(milliseconds: reduce ? 1 : 320),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        children: [
          for (final i in _invites)
            Padding(
              key: ValueKey(i.roomId),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: _InviteCard(
                invite: i,
                busy: _answering.contains(i.roomId),
                onJoin: () => _join(i),
                onLater: () => _decline(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  final GuestInvite invite;
  final bool busy;
  final VoidCallback onJoin;
  final VoidCallback onLater;
  const _InviteCard({required this.invite, required this.busy, required this.onJoin, required this.onLater});

  @override
  Widget build(BuildContext context) {
    final who = invite.inviterName.toLowerCase();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: ClayBoxDecoration(
        gradient: LinearGradient(colors: [
          Color.alphaBlend(SeenlyPalette.sage.withOpacity(0.2), SeenlyPalette.paper),
          Color.alphaBlend(SeenlyPalette.pink.withOpacity(0.12), SeenlyPalette.paper),
        ]),
        clayBase: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: SeenlyPalette.sage.withOpacity(0.5), width: 1.3),
        boxShadow: SeenlyPalette.softShadow,
      ),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 54,
            height: 54,
            child: invite.posterUrl == null
                ? ColoredBox(
                    color: SeenlyPalette.cork,
                    child: Icon(
                      invite.isReading ? Icons.menu_book_rounded : (invite.isGame ? Icons.sports_esports_rounded : Icons.live_tv_rounded),
                      color: SeenlyPalette.inkFaint,
                    ),
                  )
                : FadeInNetworkImage(url: invite.posterUrl!, placeholder: ColoredBox(color: SeenlyPalette.cork)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              invite.isReading
                  ? (invite.isLive ? at('$who уже читает', '$who is reading') : at('$who зовёт читать', '$who invites you to read'))
                  : invite.isGame
                      ? (invite.isLive ? at('$who уже играет', '$who is playing') : at('$who зовёт играть', '$who invites you to play'))
                      : (invite.isLive ? at('$who уже смотрит', '$who is watching') : at('$who зовёт смотреть', '$who invites you to watch')),
              style: SeenlyText.serif(size: 14.5, weight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text('«${invite.title}»',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: SeenlyText.serif(size: 13, italic: true, color: SeenlyPalette.inkMuted)),
            const SizedBox(height: 8),
            Row(children: [
              PressScale(
                haptics: true,
                onTap: busy ? null : onJoin,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: ClayBoxDecoration(color: SeenlyPalette.sage, borderRadius: BorderRadius.circular(16)),
                  child: busy
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(at('войти', 'join'), style: SeenlyText.serif(size: 14, weight: FontWeight.w700, color: Colors.white)),
                ),
              ),
              const SizedBox(width: 6),
              PressScale(
                onTap: onLater,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(at('не сейчас', 'not now'), style: SeenlyText.serif(size: 13, italic: true, color: SeenlyPalette.inkFaint)),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}
