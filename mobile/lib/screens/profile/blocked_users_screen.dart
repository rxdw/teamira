import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_translations.dart';
import '../../services/error_text.dart';
import '../../services/moderation_service.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../theme/clay_kit.dart';

/// Settings → Account → Blocked accounts.
///
/// Shows only the accounts *this* person blocked, never the ones who
/// blocked them — the backend doesn't send the latter, and shouldn't: a
/// block that the blocked person can discover is a notification, which is
/// the one thing a block must not be.
///
/// Unblocking restores visibility, not the friendship. That's said on the
/// screen rather than left to be discovered, because "I unblocked them and
/// they're not my friend any more" reads as a bug otherwise.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<BlockedUser>? _blocked;
  String? _working;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final blocked = await context.read<AppState>().moderation.blocks();
      if (mounted) setState(() => _blocked = blocked);
    } catch (_) {
      if (mounted) setState(() => _blocked = const []);
    }
  }

  Future<void> _unblock(BlockedUser user) async {
    setState(() => _working = user.userId);
    try {
      await context.read<AppState>().moderation.unblock(user.userId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _blocked;
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      appBar: AppBar(
        backgroundColor: SeenlyPalette.background,
        elevation: 0,
        iconTheme: IconThemeData(color: SeenlyPalette.inkMuted),
        title: Text('blocked accounts'.tr, style: SeenlyText.serif(size: 16)),
      ),
      body: blocked == null
          ? const Center(child: ThemedLoadingIndicator())
          : blocked.isEmpty
              ? _empty()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14, left: 4),
                      child: Text(
                        'they can\'t see your profile, your evenings, or reach you — and you won\'t see them anywhere either'
                            .tr,
                        style: SeenlyText.serif(
                            size: 12.5, color: SeenlyPalette.inkMuted),
                      ),
                    ),
                    for (final user in blocked)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: ClayBoxDecoration(
                          boxShadow: SeenlyPalette.flatCardShadow,
                          color: SeenlyPalette.paper,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.person_off_outlined,
                                size: 17, color: SeenlyPalette.inkMuted),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(user.nameForDisplay,
                                      style: SeenlyText.serif(size: 13)),
                                  const SizedBox(height: 2),
                                  Text('@${user.username}',
                                      style: SeenlyText.mono(
                                          size: 9,
                                          color: SeenlyPalette.placeholder)),
                                ],
                              ),
                            ),
                            if (_working == user.userId)
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: ThemedLoadingIndicator(
                                    strokeWidth: 2, color: SeenlyPalette.accent),
                              )
                            else
                              GestureDetector(
                                onTap: () => _unblock(user),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: SeenlyPalette.background,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text('unblock'.tr,
                                      style: SeenlyText.mono(
                                          size: 9.5,
                                          weight: FontWeight.w700,
                                          color: SeenlyPalette.accent)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    Text(
                      'unblocking doesn\'t make you friends again — that has to be asked for'
                          .tr,
                      textAlign: TextAlign.center,
                      style: SeenlyText.mono(
                          size: 9, color: SeenlyPalette.placeholder),
                    ),
                  ],
                ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sentiment_satisfied_outlined,
                  size: 26, color: SeenlyPalette.placeholder),
              const SizedBox(height: 12),
              Text('nobody blocked'.tr,
                  style: SeenlyText.serif(size: 15, weight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                'you can block anyone from their profile, any time, without saying why'
                    .tr,
                textAlign: TextAlign.center,
                style: SeenlyText.serif(
                    italic: true, size: 12.5, color: SeenlyPalette.inkMuted),
              ),
            ],
          ),
        ),
      );
}
