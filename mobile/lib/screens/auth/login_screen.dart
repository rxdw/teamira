import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/error_text.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/wow_motion.dart' show Entrance;
import 'forgot_password_screen.dart';
import 'reset_password_screen.dart';
import 'register_screen.dart';
import '../../services/app_translations.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Picked up once, on the build that follows a session ending
    // server-side (revoked token, password changed elsewhere, account
    // suspended). Without it the person lands on a login form with no
    // idea why they're back here — which is exactly what happened before,
    // every time the old seven-day token quietly expired.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final appState = context.read<AppState>();

      // A reset link tapped while signed out lands the person here.
      // Opened as a route rather than replacing this screen, so backing
      // out returns to sign-in rather than to nothing.
      final resetToken = appState.consumePendingPasswordResetToken();
      if (resetToken != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ResetPasswordScreen(token: resetToken),
          ),
        );
        return;
      }

      final notice = appState.consumeSessionEndedNotice();
      if (notice != null) setState(() => _error = notice.tr);
    });
  }

  Future<void> _submit() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AppState>().login(_username.text.trim(), _password.text);
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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Entrance(
                  child: Icon(Icons.nights_stay_outlined,
                      size: 30, color: SeenlyPalette.accent),
                ),
                const SizedBox(height: 10),
                Entrance(
                  delay: const Duration(milliseconds: 60),
                  child: Text('tanè'.tr,
                      textAlign: TextAlign.center,
                      style: SeenlyText.serif(size: 30, weight: FontWeight.w600)),
                ),
                const SizedBox(height: 6),
                Entrance(
                  delay: const Duration(milliseconds: 110),
                  child: Text('welcome back to your evening diary'.tr,
                      textAlign: TextAlign.center,
                      style: SeenlyText.serif(
                          italic: true,
                          size: 13,
                          color: SeenlyPalette.inkMuted)),
                ),
                const SizedBox(height: 32),
                Entrance(
                  delay: const Duration(milliseconds: 160),
                  riseBy: 16,
                  child: TextField(
                    controller: _username,
                    decoration: InputDecoration(hintText: 'username'.tr),
                  ),
                ),
                const SizedBox(height: 12),
                Entrance(
                  delay: const Duration(milliseconds: 200),
                  riseBy: 16,
                  child: TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: InputDecoration(hintText: 'password'.tr),
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
                  delay: const Duration(milliseconds: 250),
                  riseBy: 16,
                  child: PrimaryButton(
                    label: 'sign in'.tr,
                    loading: _loading,
                    onTap: _submit,
                  ),
                ),
                const SizedBox(height: 4),
                Entrance(
                  delay: const Duration(milliseconds: 280),
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                    ),
                    child: Text('forgot your password?'.tr,
                        style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted)),
                  ),
                ),
                Entrance(
                  delay: const Duration(milliseconds: 310),
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
                    ),
                    child: Text('new here? start a diary'.tr,
                        style: SeenlyText.mono(size: 12, color: SeenlyPalette.accent)),
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
