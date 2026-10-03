import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_translations.dart';
import '../../services/error_text.dart';
import '../../services/locale_service.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/themed_loading_indicator.dart';

/// Read-only cousin of [EulaScreen] — same server-fetched-markdown shape
/// (see backend/app/routers/legal.py::get_privacy_policy), minus the
/// acceptance flow, since nothing gates on having read the privacy
/// policy the way EULA acceptance does. Reached from the paywall's
/// legal footer and (eventually) anywhere else Settings links to the
/// EULA.
class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  String? _markdown;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final lang = LocaleService.appIsRussian ? 'ru' : 'en';
      final json = await context.read<AppState>().auth.privacyPolicy(lang);
      if (!mounted) return;
      setState(() => _markdown = json['markdown'] as String?);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      appBar: AppBar(
        backgroundColor: SeenlyPalette.background,
        elevation: 0,
        iconTheme: IconThemeData(color: SeenlyPalette.inkMuted),
        title: Text('privacy policy'.tr, style: SeenlyText.serif(size: 16)),
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
              : ListView(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
                  children: _render(_markdown!),
                ),
    );
  }

  /// Same minimal Markdown handling as EulaScreen._render — kept as an
  /// intentional duplicate of a dozen-odd lines rather than a shared
  /// helper two screens would otherwise import from one another for;
  /// see that method's own comment on why a Markdown package isn't
  /// worth adding for this.
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
