import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_translations.dart';
import '../../services/error_text.dart';
import '../../services/locale_service.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../theme/clay_kit.dart';

/// The terms, fetched from the server so a wording change doesn't need an
/// app release — which matters because App Store review can ask for one.
///
/// Two ways in. Read-only from the sign-up screen and Settings; with
/// [requireAcceptance] set for an account that has never accepted the
/// terms or accepted an older version (see SeenlyUser.eulaCurrent), where
/// the screen ends in an accept button and offers no way past it.
class EulaScreen extends StatefulWidget {
  final bool requireAcceptance;

  /// Called after acceptance is recorded, when this screen is being used
  /// as a gate rather than pushed as a route. A gate has nothing beneath
  /// it to pop back to — the app's auth routing (see app.dart's
  /// _AuthGate) swaps this screen out for Home once AppState knows the
  /// terms are current, so acceptance has to tell AppState rather than
  /// the navigator.
  final VoidCallback? onAccepted;

  const EulaScreen({
    super.key,
    this.requireAcceptance = false,
    this.onAccepted,
  });

  @override
  State<EulaScreen> createState() => _EulaScreenState();
}

class _EulaScreenState extends State<EulaScreen> {
  String? _markdown;
  String? _version;
  String? _error;
  bool _accepting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final lang = LocaleService.appIsRussian ? 'ru' : 'en';
      final json = await context.read<AppState>().auth.eula(lang);
      if (!mounted) return;
      setState(() {
        _markdown = json['markdown'] as String?;
        _version = json['version'] as String?;
      });
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    }
  }

  Future<void> _accept() async {
    final version = _version;
    if (version == null) return;
    setState(() => _accepting = true);
    try {
      await context.read<AppState>().auth.acceptEula(version);
      if (!mounted) return;
      if (widget.onAccepted != null) {
        widget.onAccepted!();
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      appBar: AppBar(
        backgroundColor: SeenlyPalette.background,
        elevation: 0,
        // No back arrow when acceptance is required — there is nowhere to
        // go back to until the terms are agreed, and an escape hatch that
        // silently does nothing is worse than none at all.
        automaticallyImplyLeading: !widget.requireAcceptance,
        iconTheme: IconThemeData(color: SeenlyPalette.inkMuted),
        title: Text('terms of use'.tr, style: SeenlyText.serif(size: 16)),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: SeenlyText.mono(size: 11, color: SeenlyPalette.coral)),
              ),
            )
          : _markdown == null
              ? const Center(child: ThemedLoadingIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
                        children: _render(_markdown!),
                      ),
                    ),
                    if (widget.requireAcceptance)
                      Container(
                        padding: const EdgeInsets.fromLTRB(22, 14, 22, 26),
                        decoration: ClayBoxDecoration(
                          boxShadow: SeenlyPalette.flatCardShadow,
                          color: SeenlyPalette.paper,
                          borderRadius:
                              const BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        child: PrimaryButton(
                          label: 'i agree'.tr,
                          loading: _accepting,
                          onTap: _accept,
                        ),
                      ),
                  ],
                ),
    );
  }

  /// Minimal Markdown rendering — headings, bullets, bold and paragraphs
  /// are all these two documents use. A Markdown package would be a
  /// dependency added for exactly one screen.
  List<Widget> _render(String markdown) {
    final widgets = <Widget>[];
    for (final raw in markdown.split('\n')) {
      final line = raw.trimRight();
      if (line.isEmpty) {
        widgets.add(const SizedBox(height: 8));
      } else if (line.startsWith('# ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Text(line.substring(2),
              style: SeenlyText.serif(size: 21, weight: FontWeight.w600)),
        ));
      } else if (line.startsWith('## ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(line.substring(3),
              style: SeenlyText.serif(size: 14.5, weight: FontWeight.w600)),
        ));
      } else if (line.startsWith('- ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 10, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('· ',
                  style: SeenlyText.serif(size: 13, color: SeenlyPalette.inkMuted)),
              Expanded(child: _paragraph(line.substring(2))),
            ],
          ),
        ));
      } else if (line.startsWith('_') && line.endsWith('_') && line.length > 2) {
        widgets.add(Text(line.substring(1, line.length - 1),
            style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.placeholder)));
      } else {
        widgets.add(_paragraph(line));
      }
    }
    return widgets;
  }

  Widget _paragraph(String text) {
    final parts = text.split('**');
    return RichText(
      text: TextSpan(
        children: [
          for (var i = 0; i < parts.length; i++)
            TextSpan(
              text: parts[i],
              style: SeenlyText.serif(
                size: 13,
                color: SeenlyPalette.inkMuted,
                weight: i.isOdd ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }
}
