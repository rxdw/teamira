import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/challenge.dart';
import '../../services/api_client.dart';
import '../../services/challenges_service.dart';
import '../../services/error_text.dart';
import '../../services/locale_service.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/challenge_card.dart';
import '../../widgets/challenge_claim_celebration.dart';
import '../../widgets/section_header.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/themed_pull_to_refresh.dart';
import '../../widgets/wow_motion.dart';
import '../../theme/clay_kit.dart';

/// The full challenges screen — this week's three, then the year's six.
///
/// Sits alongside Achievements in Profile rather than replacing it,
/// because they answer different questions: achievements are "what have I
/// done, ever", challenges are "what's worth doing tonight". See
/// backend/app/challenges.py's own docstring on why both exist.
class ChallengesScreen extends StatefulWidget {
  const ChallengesScreen({super.key});

  @override
  State<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends State<ChallengesScreen> {
  late final ChallengesService _service =
      ChallengesService(ApiClient.instance);

  Challenges? _data;
  String? _error;
  bool _loading = true;
  /// Which challenge id is mid-claim, so only that card shows a spinner
  /// rather than the whole screen going blank for a 200ms round trip.
  String? _claimingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final russian = LocaleService.appIsRussian;
      final data = await _service.load(russian: russian);
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
        _loading = false;
      });
      // Opening this screen counts as having seen every pending
      // completion — Home shouldn't keep announcing something the person
      // is currently looking at. Fire-and-forget: a failed acknowledgement
      // only means the banner shows once more, which is not worth an
      // error state.
      if (data.toAnnounce.isNotEmpty) {
        _service.markSeen().catchError((_) {});
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e);
        _loading = false;
      });
    }
  }

  Future<void> _claim(Challenge c) async {
    setState(() => _claimingId = c.id);
    try {
      final russian = LocaleService.appIsRussian;
      final claim = await _service.claim(c.id, russian: russian);
      if (!mounted) return;
      setState(() => _claimingId = null);
      // Celebrate first, refresh after — same order every other claim/
      // level/achievement flow in the app follows, so the list doesn't
      // visibly update mid-animation underneath the overlay.
      await showChallengeClaimCelebration(context, claim);
      if (!mounted) return;
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _claimingId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      appBar: AppBar(
        backgroundColor: SeenlyPalette.background,
        elevation: 0,
        centerTitle: false,
        title: Text('челленджи', style: SeenlyText.screenTitle),
        iconTheme: IconThemeData(color: SeenlyPalette.ink),
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: ThemedLoadingIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : ThemedPullToRefresh(
                    onRefresh: () => _load(silent: true),
                    child: _body(),
                  ),
      ),
    );
  }

  Widget _body() {
    final data = _data;
    if (data == null || data.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 90),
          Center(
            child: Text(
              'челленджи скоро появятся',
              style: SeenlyText.emptyState(),
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        _Intro(weekEndsAt: data.weekEndsAt),
        const SizedBox(height: 18),
        SectionHeader(title: 'на этой неделе'),
        const SizedBox(height: 10),
        for (var i = 0; i < data.weekly.length; i++) ...[
          ScrollReveal(
            delay: Duration(milliseconds: i * 60),
            child: ChallengeCard(
              challenge: data.weekly[i],
              claiming: _claimingId == data.weekly[i].id,
              onClaim: () => _claim(data.weekly[i]),
              onTap: () => _showRule(data.weekly[i]),
            ),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 14),
        SectionHeader(title: 'весь год'),
        const SizedBox(height: 10),
        for (var i = 0; i < data.yearly.length; i++) ...[
          ScrollReveal(
            delay: Duration(milliseconds: i * 50),
            child: ChallengeCard(
              challenge: data.yearly[i],
              claiming: _claimingId == data.yearly[i].id,
              onClaim: () => _claim(data.yearly[i]),
              onTap: () => _showRule(data.yearly[i]),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  /// Tapping a card explains how it's counted. Worth having rather than
  /// cramming the rule onto the card: "почему это не засчиталось" is the
  /// single most likely question a challenge produces, and an answer
  /// that's one tap away is much better than a caption nobody reads.
  void _showRule(Challenge c) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 26),
        decoration: ClayBoxDecoration(
          boxShadow: SeenlyPalette.flatCardShadow,
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(challengeIcon(c.iconKey), size: 18, color: SeenlyPalette.accent),
                const SizedBox(width: 9),
                Expanded(child: Text(c.title, style: SeenlyText.sectionTitle)),
              ],
            ),
            const SizedBox(height: 10),
            Text(c.caption, style: SeenlyText.bodyText),
            if (c.rule.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'как считается',
                style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint),
              ),
              const SizedBox(height: 4),
              Text(
                c.rule,
                style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted),
              ),
            ],
            const SizedBox(height: 14),
            SoftProgressBar(value: c.progress),
            const SizedBox(height: 7),
            Text(
              '${c.current} из ${c.target} · +${c.points}',
              style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  final DateTime? weekEndsAt;
  const _Intro({this.weekEndsAt});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
      decoration: BoxDecoration(
        color: SeenlyPalette.accent.withOpacity(0.07),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          BreathingGlow(
            color: SeenlyPalette.accent,
            size: 28,
            period: const Duration(milliseconds: 5200),
            maxOpacity: 0.16,
            child: Icon(Icons.auto_awesome_outlined,
                size: 16, color: SeenlyPalette.accent),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              'маленькие цели на неделю и на год. ничего не успел — '
              'они просто сменятся новыми',
              style: SeenlyText.serif(
                size: 13,
                italic: true,
                color: SeenlyPalette.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message,
                  textAlign: TextAlign.center, style: SeenlyText.emptyState()),
              const SizedBox(height: 14),
              PressScale(
                onTap: onRetry,
                child: Text('попробовать снова',
                    style: SeenlyText.mono(
                        size: 12, color: SeenlyPalette.accent)),
              ),
            ],
          ),
        ),
      );
}
