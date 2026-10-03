import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/partner/album/album_strings.dart' show at;
import '../screens/premium/premium_screen.dart';
import '../services/premium_service.dart';
import '../theme/clay_kit.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'wow_motion.dart' show PressScale;

/// A small how-to sheet for the home-screen widget.
///
/// A home-screen widget can't be added from inside an app — the OS only lets
/// the person place it themselves, from the phone's own widget picker. So
/// this sheet can't *do* it for them; it shows what they'll get (a preview
/// that cycles through the widget's three real states) and the three taps it
/// takes, worded for the platform they're on.
///
/// Opened from Settings > premium > "home-screen widget". That tile is
/// Android-only for now, same as the paywall's feature row, because the iOS
/// WidgetKit target isn't wired up yet (see premium_screen.dart) — the iOS
/// steps are written here so that dropping the platform check in those two
/// places is all it takes.
///
/// Below premium the widget itself only offers to unlock premium (see
/// HomeWidgetService's "locked" state), so the sheet says so softly and
/// leads to the paywall instead of letting someone add a widget that then
/// just asks them to pay.
Future<void> showHomeWidgetHintSheet(BuildContext context) {
  final isPremium = context.read<PremiumService>().isPremium;
  final navigator = Navigator.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        child: _HomeWidgetHintSheet(
          isPremium: isPremium,
          onUnlock: () {
            Navigator.of(sheetContext).pop();
            navigator.push(
              MaterialPageRoute(builder: (_) => const PremiumScreen()),
            );
          },
          onClose: () => Navigator.of(sheetContext).pop(),
        ),
      ),
    ),
  );
}

class _HomeWidgetHintSheet extends StatelessWidget {
  final bool isPremium;
  final VoidCallback onUnlock;
  final VoidCallback onClose;

  const _HomeWidgetHintSheet({
    required this.isPremium,
    required this.onUnlock,
    required this.onClose,
  });

  List<_StepData> _steps() {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return [
        _StepData(
          icon: Icons.add_circle_outline_rounded,
          title: at('нажми «+» в левом верхнем углу', 'tap “+” in the top-left corner'),
          body: at(
            'сначала удерживай пустое место на главном экране, пока иконки не задрожат',
            'first press and hold an empty spot on the home screen until the icons wiggle',
          ),
        ),
        _StepData(
          icon: Icons.search_rounded,
          title: at('найди tanè', 'search for tanè'),
          body: at('в поиске виджетов', 'in the widget search'),
        ),
        _StepData(
          icon: Icons.check_circle_outline_rounded,
          title: at('добавь виджет', 'add the widget'),
          body: at(
            'выбери размер и нажми «добавить виджет»',
            'pick a size and tap “add widget”',
          ),
        ),
      ];
    }
    return [
      _StepData(
        icon: Icons.touch_app_outlined,
        title: at('удерживай пустое место', 'press and hold an empty spot'),
        body: at(
          'на главном экране телефона — там, где нет иконок',
          'on your phone’s home screen, where there are no icons',
        ),
      ),
      _StepData(
        icon: Icons.widgets_outlined,
        title: at('открой «виджеты»', 'open “widgets”'),
        body: at('и найди в списке tanè', 'and find tanè in the list'),
      ),
      _StepData(
        icon: Icons.open_with_rounded,
        title: at('перетащи tanè на экран', 'drag tanè onto the screen'),
        body: at(
          'поставь, куда удобно — его можно растянуть или уменьшить',
          'put it wherever you like — you can stretch or shrink it',
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
      decoration: ClayBoxDecoration(
        boxShadow: SeenlyPalette.flatCardShadow,
        color: SeenlyPalette.paper,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            at('виджет на главном экране', 'home-screen widget'),
            textAlign: TextAlign.center,
            style: SeenlyText.serif(italic: true, size: 16),
          ),
          const SizedBox(height: 6),
          Text(
            at(
              'добавляется один раз, прямо из меню телефона — вот как',
              'added once, from your phone’s own menu — here’s how',
            ),
            textAlign: TextAlign.center,
            style: SeenlyText.serif(size: 12, color: SeenlyPalette.inkMuted),
          ),
          const SizedBox(height: 18),
          const _WidgetPreview(),
          const SizedBox(height: 20),
          for (var i = 0; i < steps.length; i++)
            _StepRow(
              number: i + 1,
              data: steps[i],
              isLast: i == steps.length - 1,
              delay: Duration(milliseconds: 120 + 110 * i),
            ),
          const SizedBox(height: 14),
          _Note(
            icon: isPremium
                ? Icons.lightbulb_outline_rounded
                : Icons.auto_awesome_outlined,
            text: isPremium
                ? at(
                    'открой tanè один раз после добавления — так он заполнится',
                    'open tanè once after adding it — that’s what fills it in',
                  )
                : at(
                    'виджет входит в премиум — без него он лишь предложит его открыть',
                    'the widget is part of premium — without it, it only offers to unlock it',
                  ),
          ),
          const SizedBox(height: 14),
          PressScale(
            onTap: isPremium ? onClose : onUnlock,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: SeenlyPalette.accent,
                borderRadius: BorderRadius.circular(24),
              ),
              alignment: Alignment.center,
              child: Text(
                isPremium
                    ? at('понятно', 'got it')
                    : at('оформить премиум', 'get premium'),
                style: SeenlyText.serif(
                    italic: true, color: SeenlyPalette.accentOnAccent),
              ),
            ),
          ),
          if (!isPremium) ...[
            const SizedBox(height: 10),
            PressScale(
              onTap: onClose,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                alignment: Alignment.center,
                child: Text(
                  at('позже', 'maybe later'),
                  style: SeenlyText.mono(
                      size: 12, color: SeenlyPalette.inkMuted),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One frame of the preview — mirrors a state HomeWidgetService really
/// sends: a "countdown" (big word + title + subtitle), a "pick" (poster +
/// title + progress) and a "streak" (big number + label).
class _PreviewState {
  final String? number; // big text slot; null when [poster] is shown instead
  final bool poster;
  final String title;
  final String subtitle;
  const _PreviewState({
    this.number,
    this.poster = false,
    required this.title,
    required this.subtitle,
  });
}

/// A miniature of the real widget, drawn with the same fixed "diary paper"
/// colours as the native one (android/.../seenly_widget_background.xml and
/// seenly_widget.xml). The widget always renders its light set whatever skin
/// the app is in, so the preview does too — a dark preview of a light widget
/// would be a small lie.
///
/// Every ~3 s it cross-fades to the next of the widget's three states, so
/// someone sees the range of what it can hold without the sheet needing
/// three cards. The caption underneath says it's an example. With the
/// system's "reduce motion" on, it stays on the first state.
class _WidgetPreview extends StatefulWidget {
  const _WidgetPreview();

  @override
  State<_WidgetPreview> createState() => _WidgetPreviewState();
}

class _WidgetPreviewState extends State<_WidgetPreview> {
  static const _cycle = Duration(seconds: 3);
  static const _count = 3;

  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_cycle, (_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) return;
      setState(() => _index = (_index + 1) % _count);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<_PreviewState> _states() => [
        _PreviewState(
          number: at('завтра', 'tomorrow'),
          title: at('пятничный киновечер', 'friday movie night'),
          subtitle: at('совместный вечер', 'evening together'),
        ),
        _PreviewState(
          poster: true,
          title: at('трилогия', 'the trilogy'),
          subtitle: at('2 из 3 просмотрено', '2 of 3 watched'),
        ),
        _PreviewState(
          number: '12',
          title: at('твой стрик', 'your streak'),
          subtitle: at('дней подряд', 'days in a row'),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final states = _states();
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, 8 * (1 - t)),
              child: child,
            ),
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 280),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFDF8),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE4D9C4)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4A3F38).withOpacity(0.10),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'tanè',
                  style: SeenlyText.mono(
                    size: 10,
                    color: const Color(0xFFA8967F),
                    enforceFloor: false,
                  ).copyWith(letterSpacing: 0.8),
                ),
                const SizedBox(height: 8),
                // Fixed height so the card never jumps between states.
                SizedBox(
                  height: 56,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 450),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.08),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.centerLeft,
                      children: [...previous, if (current != null) current],
                    ),
                    child: _PreviewFrame(
                      key: ValueKey<int>(_index),
                      state: states[_index],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _count; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                width: i == _index ? 14 : 5,
                height: 5,
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: i == _index
                      ? SeenlyPalette.accent
                      : SeenlyPalette.inkFaint.withOpacity(0.4),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          at(
            'пример — у тебя он покажет твоё',
            'just an example — yours shows your own things',
          ),
          textAlign: TextAlign.center,
          style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint),
        ),
      ],
    );
  }
}

class _PreviewFrame extends StatelessWidget {
  final _PreviewState state;
  const _PreviewFrame({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (state.poster)
          Container(
            width: 56,
            height: 56,
            margin: const EdgeInsets.only(right: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFEBDCD3), Color(0xFFD9BFC6)],
              ),
            ),
            child: const Icon(
              Icons.local_movies_outlined,
              size: 22,
              color: Color(0xFF7D5A6B),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(
              state.number ?? '',
              style: SeenlyText.serif(
                size: 28,
                weight: FontWeight.w700,
                color: const Color(0xFF7D5A6B),
                enforceFloor: false,
              ),
            ),
          ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SeenlyText.serif(
                  size: 14,
                  weight: FontWeight.w700,
                  color: const Color(0xFF4A3F38),
                  enforceFloor: false,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                state.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SeenlyText.serif(
                  size: 11,
                  color: const Color(0xFF8A7A68),
                  enforceFloor: false,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepData {
  final IconData icon;
  final String title;
  final String body;
  const _StepData({
    required this.icon,
    required this.title,
    required this.body,
  });
}

/// One numbered step with a thin rail down to the next one, so the three
/// read as a single short path rather than three separate cards.
class _StepRow extends StatelessWidget {
  final int number;
  final _StepData data;
  final bool isLast;
  final Duration delay;

  const _StepRow({
    required this.number,
    required this.data,
    required this.isLast,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    final total = delay + const Duration(milliseconds: 380);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: _DelayedCurve(
        delayFraction: delay.inMilliseconds / total.inMilliseconds,
      ),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - t)),
          child: child,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 30,
              child: Column(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: SeenlyPalette.accent.withOpacity(0.12),
                      border: Border.all(
                        color: SeenlyPalette.accent.withOpacity(0.45),
                      ),
                    ),
                    child: Text(
                      '$number',
                      style: SeenlyText.mono(
                        size: 12,
                        weight: FontWeight.w700,
                        color: SeenlyPalette.accent,
                      ),
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 1.5,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        color: SeenlyPalette.dashedBorder,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 2, bottom: isLast ? 0 : 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data.title, style: SeenlyText.serif(size: 14)),
                          const SizedBox(height: 2),
                          Text(
                            data.body,
                            style: SeenlyText.serif(
                                size: 12, color: SeenlyPalette.inkMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(data.icon, size: 18, color: SeenlyPalette.inkFaint),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Holds at 0 for the first [delayFraction] of the animation, then eases
/// out over the rest — lets each step share one duration-based tween
/// builder while still arriving one after another.
class _DelayedCurve extends Curve {
  final double delayFraction;
  const _DelayedCurve({required this.delayFraction});

  @override
  double transformInternal(double t) {
    if (t <= delayFraction) return 0;
    final local = (t - delayFraction) / (1 - delayFraction);
    return Curves.easeOutCubic.transform(local.clamp(0.0, 1.0));
  }
}

/// The soft plaque under the steps — a one-line "one more thing" for
/// premium, or the gentle premium note for everyone else.
class _Note extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Note({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SeenlyPalette.accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: SeenlyPalette.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: SeenlyText.serif(size: 12, color: SeenlyPalette.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}
