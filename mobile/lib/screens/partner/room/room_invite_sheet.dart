import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/co_view_room.dart';
import '../../../models/friend.dart';
import '../../../services/api_client.dart';
import '../../../services/co_view_room_service.dart';
import '../../../services/error_text.dart';
import '../../../services/friends_service.dart';
import '../../../theme/clay_kit.dart';
import '../../../theme/palette.dart';
import '../../../theme/text_styles.dart';
import '../../../widgets/user_avatar.dart';
import '../../../widgets/wow_motion.dart';
import 'room_controller.dart';
import 'room_strings.dart';

/// "позвать друга": friends who aren't in your circle can join this one room
/// as guests — they watch, chat and talk with you, while the playback and the
/// saving stay with the circle. Up to three at once. Free for everyone.
///
/// The sheet reads the live room (so a friend flips from "позвать" to "в
/// комнате" the moment they arrive) and sends invitations through the room's
/// own endpoint; the server decides who can come (friends only, no blocks,
/// free slots), and its reason is shown as it is.
Future<void> showRoomInviteSheet(BuildContext context, RoomController room) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _InviteSheet(room: room),
  );
}

class _InviteSheet extends StatefulWidget {
  final RoomController room;
  const _InviteSheet({required this.room});

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final _service = CoViewRoomService(ApiClient.instance);
  List<Friend>? _friends;
  final Set<String> _busy = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await FriendsService(ApiClient.instance).list();
      if (mounted) setState(() => _friends = data.friends);
    } catch (e) {
      if (mounted) {
        setState(() {
          _friends = const [];
          _error = describeError(e);
        });
      }
    }
  }

  Future<void> _invite(Friend f) async {
    if (_busy.contains(f.userId)) return;
    setState(() {
      _busy.add(f.userId);
      _error = null;
    });
    HapticFeedback.selectionClick();
    try {
      await _service.inviteGuest(widget.room.roomId, f.userId);
      // The room socket brings the new guest list; nothing to merge here.
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy.remove(f.userId));
    }
  }

  Future<void> _uninvite(String userId) async {
    if (_busy.contains(userId)) return;
    setState(() => _busy.add(userId));
    try {
      await _service.removeGuest(widget.room.roomId, userId);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy.remove(userId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.66,
      decoration: ClayBoxDecoration(
        color: SeenlyPalette.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: SeenlyPalette.border),
      ),
      child: ListenableBuilder(
        listenable: widget.room,
        builder: (context, _) {
          final s = widget.room.state;
          final guestsById = {for (final g in s.guests) g.userId: g};
          final circleIds = {for (final p in s.participants.where((p) => !p.isGuest)) p.userId};
          final candidates = (_friends ?? const <Friend>[])
              .where((f) => !circleIds.contains(f.userId))
              .toList()
            ..sort((a, b) {
              final ga = guestsById.containsKey(a.userId) ? 0 : 1;
              final gb = guestsById.containsKey(b.userId) ? 0 : 1;
              return ga != gb ? ga - gb : a.username.compareTo(b.username);
            });

          return Column(
            children: [
              const SizedBox(height: 10),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: SeenlyPalette.border, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 14),
              Text(at('позвать друга', 'invite a friend'), style: SeenlyText.serif(size: 19, weight: FontWeight.w600)),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: Text(
                  s.isGame
                      ? at('друг зайдёт в эту комнату гостем: играть рядом, писать и говорить с вами. таймер и перерывы будете вести вы. '
                          'ещё мест: ${s.guestSlotsLeft}',
                          'a friend joins this room as a guest: playing alongside, chatting and talking with you. you run the timer and the breaks. '
                          'spots left: ${s.guestSlotsLeft}')
                  : s.isReading
                      ? at('друг зайдёт в эту комнату гостем: читать, писать на полях и говорить с вами. общую страницу листать будете вы. '
                          'ещё мест: ${s.guestSlotsLeft}',
                          'a friend joins this room as a guest: reading, writing in the margin and talking with you. you turn the shared page. '
                          'spots left: ${s.guestSlotsLeft}')
                      : at('друг зайдёт в эту комнату гостем: смотреть, писать и говорить с вами. включать и ставить на паузу будете вы. '
                          'ещё мест: ${s.guestSlotsLeft}',
                          'a friend joins this room as a guest: watching, chatting and talking with you. you stay in charge of play and pause. '
                          'spots left: ${s.guestSlotsLeft}'),
                  textAlign: TextAlign.center,
                  style: SeenlyText.serif(size: 13, italic: true, color: SeenlyPalette.inkMuted),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: SeenlyText.serif(size: 13, italic: true, color: SeenlyPalette.coral)),
                ),
              const SizedBox(height: 8),
              Expanded(
                child: _friends == null
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                    : candidates.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Text(
                                at('пока некого звать — добавьте друзей в разделе друзей', 'no one to invite yet — add friends first'),
                                textAlign: TextAlign.center,
                                style: SeenlyText.serif(size: 14, italic: true, color: SeenlyPalette.placeholder),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                            itemCount: candidates.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final f = candidates[i];
                              final guest = guestsById[f.userId];
                              return _FriendRow(
                                friend: f,
                                state: guest == null
                                    ? _Invitable.canInvite
                                    : (guest.present ? _Invitable.inRoom : _Invitable.invited),
                                busy: _busy.contains(f.userId),
                                canInvite: s.guestSlotsLeft > 0,
                                onInvite: () => _invite(f),
                                onRemove: () => _uninvite(f.userId),
                              );
                            },
                          ),
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _Invitable { canInvite, invited, inRoom }

class _FriendRow extends StatelessWidget {
  final Friend friend;
  final _Invitable state;
  final bool busy;
  final bool canInvite;
  final VoidCallback onInvite;
  final VoidCallback onRemove;
  const _FriendRow({
    required this.friend,
    required this.state,
    required this.busy,
    required this.canInvite,
    required this.onInvite,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final name = (friend.displayName != null && friend.displayName!.trim().isNotEmpty) ? friend.displayName! : friend.username;
    final letter = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
    final (label, color) = switch (state) {
      _Invitable.inRoom => (at('в комнате', 'in the room'), SeenlyPalette.sage),
      _Invitable.invited => (at('позвали', 'invited'), SeenlyPalette.accent),
      _Invitable.canInvite => (at('позвать', 'invite'), SeenlyPalette.accent),
    };
    final disabled = busy || (state == _Invitable.canInvite && !canInvite);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: ClayBoxDecoration(
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SeenlyPalette.border),
      ),
      child: Row(children: [
        UserAvatar(avatarUrl: friend.avatarUrl, avatarPreset: friend.avatarPreset, fallbackLetter: letter, size: 42),
        const SizedBox(width: 12),
        Expanded(
          child: Text(name.toLowerCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: SeenlyText.serif(size: 15.5, weight: FontWeight.w600)),
        ),
        if (state == _Invitable.invited || state == _Invitable.inRoom)
          PressScale(
            onTap: busy ? null : onRemove,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.close_rounded, size: 18, color: SeenlyPalette.inkFaint),
            ),
          ),
        PressScale(
          haptics: true,
          onTap: (disabled || state != _Invitable.canInvite) ? null : onInvite,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: state == _Invitable.canInvite && !disabled ? color : color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: busy
                ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: color))
                : Text(label,
                    style: SeenlyText.serif(
                      size: 13.5,
                      weight: FontWeight.w600,
                      color: state == _Invitable.canInvite && !disabled ? SeenlyPalette.accentOnAccent : color,
                    )),
          ),
        ),
      ]),
    );
  }
}
