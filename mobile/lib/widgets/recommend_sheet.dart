import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/friend.dart';
import '../services/app_translations.dart';
import '../services/error_text.dart';
import '../state/app_state.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'themed_loading_indicator.dart';
import 'user_avatar.dart';
import 'wow_motion.dart' show PressScale;
import '../theme/clay_kit.dart';

/// "Ставлю N очков, что Х оценит это на Y" — the creation half of the
/// staked-recommendation feature (see backend/app/routers/
/// recommendations.py and app/sincerity.py's module docstring). Opened
/// from a title's own screen; resolution itself happens invisibly,
/// server-side, the moment the friend logs a rating for this exact
/// title (see that router's own docstring for why there's no
/// "resolve" step here to wait for).
///
/// Mirrors sincerity.MIN_RECOMMENDATION_STAKE / MAX_RECOMMENDATION_STAKE
/// (1..5) as literal bounds below rather than fetching them — small and
/// stable enough that the backend clamping again on write is the real
/// safety net, same reasoning as co_view_hub_screen.dart's own
/// _spoilerUnlockCost constant.
class RecommendSheet extends StatefulWidget {
  final String source;
  final String mediaId;
  final String title;

  const RecommendSheet({
    super.key,
    required this.source,
    required this.mediaId,
    required this.title,
  });

  static Future<void> show(
    BuildContext context, {
    required String source,
    required String mediaId,
    required String title,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => RecommendSheet(source: source, mediaId: mediaId, title: title),
    );
  }

  @override
  State<RecommendSheet> createState() => _RecommendSheetState();
}

class _RecommendSheetState extends State<RecommendSheet> {
  static const _minStake = 1;
  static const _maxStake = 5;

  List<Friend>? _friends;
  String? _loadError;
  Friend? _chosen;
  int _predictedRating = 8;
  int _stake = 2;
  bool _submitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    try {
      final data = await context.read<AppState>().friends.list();
      if (!mounted) return;
      setState(() => _friends = data.friends);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = describeError(e));
    }
  }

  Future<void> _submit() async {
    final friend = _chosen;
    if (friend == null || _submitting) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await context.read<AppState>().recommendations.create(
            friendId: friend.userId,
            source: widget.source,
            mediaId: widget.mediaId,
            title: widget.title,
            predictedRating: _predictedRating,
            stake: _stake,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${'ставка сделана —'.tr} ${friend.nameForDisplay} ${'узнает об этом, когда оценит тайтл'.tr}'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitError = describeError(e);
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
        decoration: ClayBoxDecoration(
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(20),
          boxShadow: SeenlyPalette.softShadow,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: SeenlyPalette.dashedBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text('поставить на рекомендацию'.tr, style: SeenlyText.serif(size: 16, weight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                '«${widget.title}» — предскажи, на сколько оценит друг, и поставь очки на свою правоту'.tr,
                style: SeenlyText.serif(size: 13, color: SeenlyPalette.inkMuted),
              ),
              const SizedBox(height: 18),
              Text('кому'.tr, style: SeenlyText.mono(size: 11.5, weight: FontWeight.w700, color: SeenlyPalette.inkFaint)),
              const SizedBox(height: 10),
              _friends == null && _loadError == null
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: ThemedLoadingIndicator(size: 20)),
                    )
                  : _loadError != null
                      ? Text(_loadError!, style: SeenlyText.mono(size: 12, color: SeenlyPalette.coral))
                      : (_friends!.isEmpty)
                          ? Text(
                              'пока не с кем — добавь друзей, чтобы делать ставки'.tr,
                              style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkFaint),
                            )
                          : SizedBox(
                              height: 76,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _friends!.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 10),
                                itemBuilder: (context, i) {
                                  final f = _friends![i];
                                  final selected = _chosen?.userId == f.userId;
                                  return PressScale(
                                    onTap: () => setState(() => _chosen = f),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        UserAvatar(
                                          avatarUrl: f.avatarUrl,
                                          avatarPreset: f.avatarPreset,
                                          fallbackLetter: f.nameForDisplay.isNotEmpty ? f.nameForDisplay[0] : '?',
                                          size: 46,
                                          borderColor: selected ? SeenlyPalette.accent : Colors.transparent,
                                        ),
                                        const SizedBox(height: 4),
                                        SizedBox(
                                          width: 54,
                                          child: Text(
                                            f.nameForDisplay,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: SeenlyText.mono(
                                              size: 9.5,
                                              color: selected ? SeenlyPalette.accent : SeenlyPalette.inkFaint,
                                              weight: selected ? FontWeight.w700 : FontWeight.w400,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('предсказанная оценка'.tr,
                      style: SeenlyText.mono(size: 11.5, weight: FontWeight.w700, color: SeenlyPalette.inkFaint)),
                  Text('$_predictedRating',
                      style: SeenlyText.serif(size: 15, weight: FontWeight.w700, color: SeenlyPalette.accent)),
                ],
              ),
              Slider(
                value: _predictedRating.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                activeColor: SeenlyPalette.accent,
                onChanged: (v) => setState(() => _predictedRating = v.round()),
              ),
              const SizedBox(height: 6),
              Text('ставка'.tr, style: SeenlyText.mono(size: 11.5, weight: FontWeight.w700, color: SeenlyPalette.inkFaint)),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (var s = _minStake; s <= _maxStake; s++) ...[
                    _StakeChip(value: s, selected: _stake == s, onTap: () => setState(() => _stake = s)),
                    if (s != _maxStake) const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              if (_submitError != null) ...[
                Text(_submitError!, style: SeenlyText.mono(size: 12, color: SeenlyPalette.coral)),
                const SizedBox(height: 10),
              ],
              PressScale(
                onTap: _chosen == null ? null : _submit,
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: _chosen == null ? SeenlyPalette.dashedBorder : SeenlyPalette.accent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: _submitting
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: SeenlyPalette.accentOnAccent),
                        )
                      : Text(
                          '${'поставить'.tr} $_stake',
                          style: SeenlyText.mono(size: 13.5, weight: FontWeight.w700, color: SeenlyPalette.accentOnAccent),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StakeChip extends StatelessWidget {
  final int value;
  final bool selected;
  final VoidCallback onTap;
  const _StakeChip({required this.value, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? SeenlyPalette.accent : SeenlyPalette.accent.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '$value',
          style: SeenlyText.mono(
            size: 13,
            weight: FontWeight.w700,
            color: selected ? SeenlyPalette.accentOnAccent : SeenlyPalette.accent,
          ),
        ),
      ),
    );
  }
}
