import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/error_text.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/small_pieces.dart';
import '../legal/eula_screen.dart';
import '../../widgets/wow_motion.dart' show Entrance;
import '../../services/app_translations.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _referralCode = TextEditingController();
  bool _loading = false;
  bool _showReferralField = false;
  String? _error;

  Future<void> _submit() async {
    if (_username.text.trim().length < 3 || _password.text.length < 6) {
      setState(() => _error =
          'username needs 3+ characters, password needs 6+'.tr);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AppState>().register(
            _username.text.trim(),
            _password.text,
            referralCode: _referralCode.text.trim().isEmpty ? null : _referralCode.text.trim(),
          );
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Entrance(
                  child: Text('start your diary'.tr,
                      textAlign: TextAlign.center,
                      style: SeenlyText.serif(size: 24, weight: FontWeight.w600)),
                ),
                const SizedBox(height: 6),
                Entrance(
                  delay: const Duration(milliseconds: 60),
                  child: Text('a shelf just for you — takes a minute'.tr,
                      textAlign: TextAlign.center,
                      style: SeenlyText.serif(
                          italic: true,
                          size: 13,
                          color: SeenlyPalette.inkMuted)),
                ),
                const SizedBox(height: 28),
                Entrance(
                  delay: const Duration(milliseconds: 110),
                  riseBy: 16,
                  child: TextField(
                    controller: _username,
                    decoration: InputDecoration(hintText: 'pick a username'.tr),
                  ),
                ),
                const SizedBox(height: 12),
                Entrance(
                  delay: const Duration(milliseconds: 150),
                  riseBy: 16,
                  child: TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: InputDecoration(hintText: 'pick a password'.tr),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _showReferralField
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: TextField(
                            controller: _referralCode,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(hintText: "a friend's invite code".tr),
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () => setState(() => _showReferralField = true),
                              child: Text('have an invite code?'.tr,
                                  style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent)),
                            ),
                          ),
                        ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _error == null
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(_error!,
                              style: SeenlyText.mono(size: 11, color: SeenlyPalette.coral)),
                        ),
                ),
                const SizedBox(height: 20),
                Entrance(
                  delay: const Duration(milliseconds: 200),
                  riseBy: 16,
                  child: PrimaryButton(
                    label: 'create my diary'.tr,
                    loading: _loading,
                    onTap: _submit,
                  ),
                ),
                const SizedBox(height: 14),
                // Acceptance is recorded server-side at registration (see
                // routers/auth.py::register), which App Store review
                // guideline 1.2 asks for: an agreement where the person
                // acknowledges there's no tolerance for objectionable
                // content or abusive behaviour. Stated by the button
                // rather than behind a checkbox — the tap *is* the
                // agreement, and a checkbox between someone and their
                // first diary entry is friction that changes nobody's
                // mind.
                Entrance(
                  delay: const Duration(milliseconds: 240),
                  child: Column(
                    children: [
                      Text('creating a diary means agreeing to the terms'.tr,
                          textAlign: TextAlign.center,
                          style: SeenlyText.mono(
                              size: 9.5, color: SeenlyPalette.placeholder)),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const EulaScreen()),
                        ),
                        child: Text('read the terms'.tr,
                            style: SeenlyText.mono(
                                size: 11, color: SeenlyPalette.accent)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
