import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/friend.dart';
import '../state/app_state.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'themed_loading_indicator.dart';
import '../services/app_translations.dart';
import '../services/locale_service.dart';

/// The invite flow's only surface — opened by tapping "invite friends" in
/// the profile friends block or on the friends screen itself. Never
/// shown unprompted (no auto-popup on first launch, no periodic nag): the
/// whole point is that inviting stays a one-tap, opt-in thing to reach
/// for, not something the app pushes on people.
///
/// Same soft, blurred-backdrop card language as HowItWorksSheet.
Future<void> showInviteFriendsSheet(BuildContext context) {
  return showGeneralDialog(
    context: context,
    barrierLabel: 'invite friends',
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, _, __) => const InviteFriendsSheet(),
    transitionBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(curved), child: child),
      );
    },
  );
}

class InviteFriendsSheet extends StatefulWidget {
  const InviteFriendsSheet({super.key});

  @override
  State<InviteFriendsSheet> createState() => _InviteFriendsSheetState();
}

class _InviteFriendsSheetState extends State<InviteFriendsSheet> {
  InviteInfo? _invite;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final invite = await context.read<AppState>().friends.invite();
      if (!mounted) return;
      setState(() {
        _invite = invite;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _copy() async {
    final code = _invite?.code;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('code copied'.tr)));
  }

  void _share() {
    final invite = _invite;
    if (invite == null) return;
    Share.share(invite.shareText);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(color: SeenlyPalette.ink.withOpacity(0.28)),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  width: 320,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                  decoration: BoxDecoration(
                    color: SeenlyPalette.paper,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(color: SeenlyPalette.ink.withOpacity(0.18), blurRadius: 30, offset: const Offset(0, 12)),
                    ],
                  ),
                  child: _loading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 30),
                          child: Center(child: ThemedLoadingIndicator()),
                        )
                      : _invite == null
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text("couldn't load your invite code — try again in a bit".tr,
                                  textAlign: TextAlign.center,
                                  style: SeenlyText.serif(italic: true, size: 12, color: SeenlyPalette.inkMuted)),
                            )
                          : _body(_invite!),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(InviteInfo invite) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('invite friends'.tr, style: SeenlyText.serif(size: 16, weight: FontWeight.w700)),
            ),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(color: SeenlyPalette.background, shape: BoxShape.circle),
                child: Icon(Icons.close, size: 13, color: SeenlyPalette.inkMuted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          "${'every friend who joins with your code earns you'.tr} +${invite.xpPerFriend} xp",
          style: SeenlyText.serif(italic: true, size: 11, color: SeenlyPalette.inkMuted),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _copy,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: SeenlyPalette.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: SeenlyPalette.dashedBorder, width: 1.2),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(invite.code,
                    style: SeenlyText.mono(size: 18, color: SeenlyPalette.ink, weight: FontWeight.w700)
                        .copyWith(letterSpacing: 3)),
                const SizedBox(width: 10),
                Icon(Icons.copy_rounded, size: 14, color: SeenlyPalette.inkFaint),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 24),
          decoration: BoxDecoration(color: SeenlyPalette.accent, borderRadius: BorderRadius.circular(24)),
          child: GestureDetector(
            onTap: _share,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.ios_share_rounded, size: 15, color: SeenlyPalette.accentOnAccent),
                const SizedBox(width: 8),
                Text('share invite'.tr, style: SeenlyText.serif(italic: true, size: 14, color: SeenlyPalette.accentOnAccent)),
              ],
            ),
          ),
        ),
        if (invite.invitedCount > 0) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: SeenlyPalette.background, borderRadius: BorderRadius.circular(12)),
            child: Text(
              LocaleService.appIsRussian
                  ? '${ruCount(invite.invitedCount, one: 'друг', few: 'друга', many: 'друзей', englishOne: '', englishOther: '')} '
                      '${invite.invitedCount == 1 ? 'присоединился' : 'присоединились'} с твоим кодом — +${invite.xpBonus} xp пока что'
                  : '${invite.invitedCount} ${invite.invitedCount == 1 ? "friend has" : "friends have"} '
                      'joined with your code — +${invite.xpBonus} xp so far',
              style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.inkFaint),
            ),
          ),
        ],
      ],
    );
  }
}
