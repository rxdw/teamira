import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../analytics/analytics.dart';
import '../../models/partner_status.dart';
import '../../services/api_client.dart';
import '../../services/locale_service.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/pairing_qr.dart' show showPairingScanner;
import '../../widgets/small_pieces.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/wow_motion.dart';

String _t(String ru, String en) => LocaleService.appIsRussian ? ru : en;

/// The onboarding screen paints a fixed "evening" world, whatever theme the
/// device is in (see the long note at the top of onboarding_screen.dart), so
/// everything here uses the fixed light-on-dark tones rather than the
/// theme-ambient ones.
const Color _paper = SeenlyPalette.paperOnDark;

/// A QR must be dark modules on a light ground to scan reliably. The app's own
/// PairingQrCode takes both colours from the ambient theme — in a dark theme
/// that would print light-on-dark, which many scanners refuse — so the
/// onboarding card fixes them.
const Color _qrInk = Color(0xFF241A22);

/// "С кем вы смотрите?" — connecting a partner, right at the start.
///
/// Everything this app does best is done for two (a shared list, "what are we
/// watching tonight", a room for the evening: films, books, manga, games), so
/// the offer to connect comes up front instead of being something to find on
/// Home later. Same pairing the Home card uses (PartnerService.pair / join —
/// a 6-character code, shown as a QR too), just laid out for this canvas:
///
///  * **choose** — invite someone, or I already have a code; or "later";
///  * **invite** — my code and its QR, a button to send it, and a quiet
///    waiting line that turns into the celebration on its own the moment the
///    other person enters the code (the status is polled);
///  * **join** — type or scan a code;
///  * **linked** — the two of you, and what that opens.
///
/// It reads the truth from the server every time it opens, so going back to it
/// shows the code still waiting (or the couple, if it happened meanwhile)
/// rather than starting over. Nothing here is required: "later" moves on, and
/// a code left waiting stays on Home for whenever the other person gets to it.
class OnboardingPartnerStep extends StatefulWidget {
  final VoidCallback onNext;

  /// Called once, the moment the two of you become linked while this step is
  /// open — the screen's confetti.
  final VoidCallback onLinked;
  const OnboardingPartnerStep({super.key, required this.onNext, required this.onLinked});

  @override
  State<OnboardingPartnerStep> createState() => _OnboardingPartnerStepState();
}

enum _Mode { loading, choose, invite, join, linked }

class _OnboardingPartnerStepState extends State<OnboardingPartnerStep> {
  static const _pollEvery = Duration(seconds: 3);

  _Mode _mode = _Mode.loading;
  PartnerStatus? _status;
  bool _busy = false;
  String? _error;
  bool _copied = false;
  Timer? _poll;
  Timer? _copiedTimer;
  final _code = TextEditingController();
  // Where "back" goes from the join screen: to the choice, or to my own code
  // if I had one showing.
  _Mode _joinFrom = _Mode.choose;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _copiedTimer?.cancel();
    _code.dispose();
    super.dispose();
  }

  AppState get _app => context.read<AppState>();

  Future<void> _load() async {
    try {
      final status = await _app.partner.status();
      if (!mounted) return;
      setState(() {
        _status = status;
        _mode = status.linked
            ? _Mode.linked
            : (status.pendingCode != null ? _Mode.invite : _Mode.choose);
      });
      _syncPolling();
    } catch (_) {
      // Offline or a hiccup: the choice still works, and every action below
      // reports its own failure.
      if (mounted) setState(() => _mode = _Mode.choose);
    }
  }

  /// Polling runs only while my code is on screen and nobody has used it yet.
  void _syncPolling() {
    _poll?.cancel();
    _poll = null;
    if (_mode != _Mode.invite) return;
    _poll = Timer.periodic(_pollEvery, (_) => _check());
  }

  Future<void> _check() async {
    try {
      final status = await _app.partner.status();
      if (!mounted || _mode != _Mode.invite) return;
      if (status.linked) _becameLinked(status);
    } catch (_) {
      // A missed tick just tries again.
    }
  }

  void _becameLinked(PartnerStatus status) {
    _poll?.cancel();
    _poll = null;
    HapticFeedback.mediumImpact();
    setState(() {
      _status = status;
      _mode = _Mode.linked;
      _busy = false;
      _error = null;
    });
    Analytics.instance.track('onboarding_partner_linked');
    widget.onLinked();
  }

  // --- actions -----------------------------------------------------------------

  Future<void> _createCode() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await _app.partner.pair();
      if (!mounted) return;
      if (status.linked) return _becameLinked(status);
      setState(() {
        _status = status;
        _mode = _Mode.invite;
        _busy = false;
      });
      _syncPolling();
    } on ApiException catch (e) {
      if (mounted) setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (mounted) setState(() {
        _busy = false;
        _error = _t('не получилось получить код — попробуйте ещё раз', 'couldn’t get a code — try again');
      });
    }
  }

  Future<void> _scan() async {
    final scanned = await showPairingScanner(context);
    if (scanned == null || !mounted) return;
    _code.text = scanned;
    await _submit();
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = _t('код — это 6 символов', 'a code is 6 characters'));
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await _app.partner.join(code);
      if (!mounted) return;
      // Deliberately NOT AppState.notePartnerJustLinked(): that queues the
      // "you've just become a couple" paywall, and onboarding already queues
      // its own for the very end of the flow — two offers stacked on the first
      // Home would be one too many.
      _becameLinked(status);
    } on ApiException catch (e) {
      if (mounted) setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (mounted) setState(() {
        _busy = false;
        _error = _t('проверьте соединение и попробуйте ещё раз', 'check the connection and try again');
      });
    }
  }

  void _openJoin(_Mode from) {
    _poll?.cancel();
    _poll = null;
    setState(() {
      _joinFrom = from;
      _mode = _Mode.join;
      _error = null;
    });
  }

  void _backFromJoin() {
    setState(() {
      _mode = _joinFrom == _Mode.invite && _status?.pendingCode != null ? _Mode.invite : _Mode.choose;
      _error = null;
    });
    _syncPolling();
  }

  void _skip() {
    Analytics.instance.track('onboarding_partner_skipped', {'had_code': _status?.pendingCode != null});
    widget.onNext();
  }

  Future<void> _share(String code) async {
    HapticFeedback.selectionClick();
    await Share.share(_t(
      'давай смотреть, читать и играть вместе в teamira! мой код для пары: $code — введи его в приложении, на главном экране в карточке «вместе».',
      'let’s watch, read and play together in teamira! my pairing code: $code — enter it in the app, on the home screen in the “together” card.',
    ));
  }

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    HapticFeedback.selectionClick();
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  // --- build -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
      child: AnimatedSwitcher(
        duration: Duration(milliseconds: reduce ? 1 : 340),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(animation),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey(_mode), child: _body()),
      ),
    );
  }

  Widget _body() {
    switch (_mode) {
      case _Mode.loading:
        return const Center(child: ThemedLoadingIndicator(size: 34));
      case _Mode.choose:
        return _choose();
      case _Mode.invite:
        return _invite();
      case _Mode.join:
        return _join();
      case _Mode.linked:
        return _linked();
    }
  }

  /// Centres its children in the space when there is room, and scrolls when
  /// there isn't — a small phone, or the keyboard open over the code field.
  /// (No IntrinsicHeight/Spacer: a plain minimum height plus centring does the
  /// same without asking every child to measure itself twice.)
  Widget _fit(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }

  // --- choose ------------------------------------------------------------------

  Widget _choose() {
    final me = _app.currentUser;
    return _fit([
      Entrance(
        child: Center(
          child: _CouplePair(
            left: me == null
                ? null
                : UserAvatar(
                    avatarUrl: me.avatarUrl,
                    avatarPreset: me.avatarPreset,
                    fallbackLetter: me.username.isNotEmpty ? me.username[0].toUpperCase() : '?',
                    size: 64,
                  ),
            right: null,
          ),
        ),
      ),
      const SizedBox(height: 22),
      Entrance(
        delay: const Duration(milliseconds: 90),
        child: Text(
          _t('с кем вы смотрите?', 'who do you watch with?'),
          textAlign: TextAlign.center,
          style: SeenlyText.serif(size: 22, color: _paper),
        ),
      ),
      const SizedBox(height: 8),
      Entrance(
        delay: const Duration(milliseconds: 150),
        child: Text(
          _t(
            'добавьте партнёра — появятся общий список, вечерний выбор «что смотрим» и комната на двоих: кино, книги, манга и игры.',
            'add a partner — you get a shared list, a “what are we watching tonight” pick and a room for two: films, books, manga and games.',
          ),
          textAlign: TextAlign.center,
          style: SeenlyText.serif(size: 13, color: Colors.white.withOpacity(0.62)),
        ),
      ),
      const SizedBox(height: 22),
      Entrance(
        delay: const Duration(milliseconds: 220),
        child: _ChoiceTile(
          icon: Icons.favorite_rounded,
          title: _t('позвать партнёра', 'invite your partner'),
          subtitle: _t('получите код и QR — отправьте или покажите', 'get a code and a QR — send it or show it'),
          busy: _busy,
          onTap: _createCode,
        ),
      ),
      const SizedBox(height: 10),
      Entrance(
        delay: const Duration(milliseconds: 280),
        child: _ChoiceTile(
          icon: Icons.qr_code_scanner_rounded,
          title: _t('у меня есть код', 'I have a code'),
          subtitle: _t('введите его или отсканируйте QR', 'type it in or scan the QR'),
          onTap: () => _openJoin(_Mode.choose),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!,
            textAlign: TextAlign.center,
            style: SeenlyText.serif(size: 12.5, italic: true, color: SeenlyPalette.coral)),
      ],
      const SizedBox(height: 18),
      Entrance(
        delay: const Duration(milliseconds: 340),
        child: _QuietLink(
          label: _t('позже — это можно сделать на главном экране', 'later — you can do this on the home screen'),
          onTap: _skip,
        ),
      ),
    ]);
  }

  // --- invite ------------------------------------------------------------------

  Widget _invite() {
    final code = _status?.pendingCode ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _t('ваш код для партнёра', 'your code for your partner'),
          textAlign: TextAlign.center,
          style: SeenlyText.serif(size: 20, color: _paper),
        ),
        const SizedBox(height: 6),
        Text(
          _t('пусть отсканирует QR или введёт код — и вы вместе', 'let them scan the QR or type the code — and you’re together'),
          textAlign: TextAlign.center,
          style: SeenlyText.serif(size: 12.5, color: Colors.white.withOpacity(0.6)),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                Entrance(child: _QrCard(code: code)),
                const SizedBox(height: 16),
                Entrance(
                  delay: const Duration(milliseconds: 100),
                  child: GestureDetector(
                    onTap: () => _copy(code),
                    behavior: HitTestBehavior.opaque,
                    child: Column(children: [
                      Text(
                        code,
                        style: SeenlyText.mono(size: 28, color: _paper, weight: FontWeight.w700).copyWith(letterSpacing: 8),
                      ),
                      const SizedBox(height: 4),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          _copied ? _t('скопировано ✓', 'copied ✓') : _t('нажмите, чтобы скопировать', 'tap to copy'),
                          key: ValueKey(_copied),
                          style: SeenlyText.mono(size: 10, color: Colors.white.withOpacity(_copied ? 0.85 : 0.4)),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 18),
                const _WaitingLine(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        PrimaryButton(label: _t('отправить код', 'send the code'), onTap: () => _share(code)),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _QuietLink(label: _t('у меня есть код', 'I have a code'), onTap: () => _openJoin(_Mode.invite)),
          _QuietLink(label: _t('продолжить', 'continue'), onTap: _skip),
        ]),
      ],
    );
  }

  // --- join --------------------------------------------------------------------

  Widget _join() {
    return _fit([
      Text(
        _t('введите код партнёра', 'enter your partner’s code'),
        textAlign: TextAlign.center,
        style: SeenlyText.serif(size: 20, color: _paper),
      ),
      const SizedBox(height: 6),
      Text(
        _t('6 символов — он появляется у партнёра на таком же экране', '6 characters — it shows on the same screen on their phone'),
        textAlign: TextAlign.center,
        style: SeenlyText.serif(size: 12.5, color: Colors.white.withOpacity(0.6)),
      ),
      const SizedBox(height: 22),
      Center(
        child: PressScale(
          haptics: true,
          onTap: _busy ? null : _scan,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(0.22)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.qr_code_scanner_rounded, size: 18, color: _paper.withOpacity(0.9)),
              const SizedBox(width: 8),
              Text(_t('отсканировать QR', 'scan their QR'), style: SeenlyText.serif(size: 14.5, color: _paper)),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _code,
        textCapitalization: TextCapitalization.characters,
        textAlign: TextAlign.center,
        maxLength: 6,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
        style: SeenlyText.mono(size: 24, color: _paper, weight: FontWeight.w700).copyWith(letterSpacing: 7),
        cursorColor: _paper,
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: Colors.white.withOpacity(0.08),
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
          hintText: '······',
          hintStyle: SeenlyText.mono(size: 24, color: Colors.white.withOpacity(0.25)).copyWith(letterSpacing: 7),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: _paper.withOpacity(0.7), width: 1.4),
          ),
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 220),
        child: _error == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: SeenlyText.serif(size: 12.5, italic: true, color: SeenlyPalette.coral)),
              ),
      ),
      const SizedBox(height: 18),
      PrimaryButton(label: _t('присоединиться', 'join'), onTap: _submit, loading: _busy),
      const SizedBox(height: 6),
      Center(child: _QuietLink(label: _t('назад', 'back'), onTap: _backFromJoin)),
    ]);
  }

  // --- linked ------------------------------------------------------------------

  Widget _linked() {
    final status = _status;
    final members = status?.members ?? const <PartnerMember>[];
    final me = members.where((m) => m.isYou).firstOrNull;
    final other = members.where((m) => !m.isYou).firstOrNull;
    final name = other?.nameForDisplay ?? status?.partnerUsername ?? '';
    final company = (status?.isCompany ?? false) || members.length > 2;
    Widget avatar(PartnerMember? m, double size) => m == null
        ? SizedBox(width: size, height: size)
        : UserAvatar(
            avatarUrl: m.avatarUrl,
            avatarPreset: m.avatarPreset,
            fallbackLetter: m.username.isNotEmpty ? m.username[0].toUpperCase() : '?',
            size: size,
          );
    return _fit([
      Entrance(child: Center(child: _CouplePair(left: avatar(me, 64), right: avatar(other, 64), joined: true))),
      const SizedBox(height: 22),
      Entrance(
        delay: const Duration(milliseconds: 90),
        child: Text(
          company
              ? _t('вы в одной компании', 'you’re in a circle together')
              : (name.isEmpty ? _t('вы вместе!', 'you’re together!') : _t('вы вместе с $name', 'you’re together with $name')),
          textAlign: TextAlign.center,
          style: SeenlyText.serif(size: 22, color: _paper),
        ),
      ),
      const SizedBox(height: 8),
      Entrance(
        delay: const Duration(milliseconds: 150),
        child: Text(
          _t('теперь у вас общий список, и можно вместе выбирать, что смотреть, читать и во что играть.',
              'now you share a list, and can pick together what to watch, read and play.'),
          textAlign: TextAlign.center,
          style: SeenlyText.serif(size: 13, color: Colors.white.withOpacity(0.62)),
        ),
      ),
      const SizedBox(height: 20),
      Entrance(
        delay: const Duration(milliseconds: 220),
        child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          _Perk(icon: Icons.bookmarks_rounded, label: _t('общий список', 'shared list')),
          _Perk(icon: Icons.how_to_vote_rounded, label: _t('что смотрим сегодня', 'tonight’s pick')),
          _Perk(icon: Icons.meeting_room_rounded, label: _t('комната на двоих', 'a room for two')),
        ]),
      ),
      const SizedBox(height: 28),
      Entrance(
        delay: const Duration(milliseconds: 300),
        child: PrimaryButton(label: _t('дальше', 'continue'), onTap: widget.onNext),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

/// Two circles side by side with a heart between them. Before the link the
/// right one is an empty dashed place waiting for somebody; after it, both are
/// faces and the heart beats once, softly.
class _CouplePair extends StatelessWidget {
  final Widget? left;
  final Widget? right;
  final bool joined;
  const _CouplePair({required this.left, required this.right, this.joined = false});

  @override
  Widget build(BuildContext context) {
    const size = 64.0;
    Widget circle(Widget? child, {required bool empty}) => Container(
          width: size + 8,
          height: size + 8,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(empty ? 0.04 : 0.1),
            border: Border.all(
              color: Colors.white.withOpacity(empty ? 0.3 : 0.45),
              width: empty ? 1.2 : 1.6,
            ),
          ),
          child: child ??
              Icon(empty ? Icons.person_add_alt_1_rounded : Icons.person_rounded,
                  size: 28, color: Colors.white.withOpacity(0.55)),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        circle(left, empty: left == null),
        Breathe(
          period: const Duration(milliseconds: 1800),
          minScale: joined ? 0.88 : 0.94,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Icon(
              Icons.favorite_rounded,
              size: joined ? 28 : 22,
              color: SeenlyPalette.accent.withOpacity(joined ? 1 : 0.8),
            ),
          ),
        ),
        circle(right, empty: right == null && !joined),
      ],
    );
  }
}

/// One of the two big choices on the first screen.
class _ChoiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool busy;
  const _ChoiceTile({required this.icon, required this.title, required this.subtitle, required this.onTap, this.busy = false});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      scaleTo: 0.98,
      haptics: true,
      onTap: busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.18)),
        ),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(shape: BoxShape.circle, color: SeenlyPalette.accent.withOpacity(0.2)),
            child: busy
                ? const Padding(padding: EdgeInsets.all(13), child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(icon, size: 22, color: _paper),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: SeenlyText.serif(size: 16, weight: FontWeight.w600, color: _paper)),
              const SizedBox(height: 2),
              Text(subtitle, style: SeenlyText.serif(size: 12, italic: true, color: Colors.white.withOpacity(0.55))),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.4)),
        ]),
      ),
    );
  }
}

/// The QR on a light card, dark modules on light ground at any theme.
class _QrCard extends StatelessWidget {
  final String code;
  const _QrCard({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: QrImageView(
        data: code,
        version: QrVersions.auto,
        size: 156,
        gapless: false,
        backgroundColor: _paper,
        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: _qrInk),
        dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: _qrInk),
      ),
    );
  }
}

/// "Waiting for them…" with a soft pulsing dot — the screen turns into the
/// celebration on its own, so it should look alive, not stuck.
class _WaitingLine extends StatelessWidget {
  const _WaitingLine();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Breathe(
          period: const Duration(milliseconds: 1500),
          minScale: 0.6,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: SeenlyPalette.accent.withOpacity(0.9)),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            _t('ждём, когда партнёр введёт код…', 'waiting for them to enter the code…'),
            style: SeenlyText.serif(size: 13, italic: true, color: Colors.white.withOpacity(0.6)),
          ),
        ),
      ],
    );
  }
}

class _Perk extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Perk({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: _paper.withOpacity(0.85)),
        const SizedBox(width: 6),
        Text(label, style: SeenlyText.serif(size: 12.5, italic: true, color: _paper.withOpacity(0.85))),
      ]),
    );
  }
}

/// A quiet text action — "later", "back" — that never competes with the
/// primary button.
class _QuietLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuietLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      child: Text(label,
          textAlign: TextAlign.center,
          style: SeenlyText.serif(size: 12.5, italic: true, color: Colors.white.withOpacity(0.55))),
    );
  }
}
