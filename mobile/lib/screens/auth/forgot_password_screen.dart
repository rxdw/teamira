import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_translations.dart';
import '../../services/error_text.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/wow_motion.dart' show Entrance;
import 'reset_password_screen.dart';

/// "I forgot my password."
///
/// The screen that had nowhere to exist before: `User` had no email
/// column at all, so a forgotten password meant an archive of years of
/// evenings was gone for good. That was the single most costly thing
/// missing from this app, given that the whole proposition is an archive
/// worth keeping.
///
/// The one interface decision worth explaining: the confirmation is
/// identical whether or not the address belongs to an account, and the
/// copy says so out loud ("if that address is on a tanè account"). The
/// backend answers the same way for the same reason — this endpoint is
/// unauthenticated and takes an email address, so a response that
/// distinguished the two would be a free "is this person on tanè" lookup
/// for any address anyone cared to try. Saying it plainly is better than
/// letting someone wonder whether they typo'd.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _sentMessage;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'that doesn\'t look like an email address'.tr);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final message = await context.read<AppState>().auth.forgotPassword(email);
      if (mounted) setState(() => _sentMessage = message);
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
      appBar: AppBar(
        backgroundColor: SeenlyPalette.background,
        elevation: 0,
        iconTheme: IconThemeData(color: SeenlyPalette.inkMuted),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: _sentMessage != null ? _sentView() : _formView(),
          ),
        ),
      ),
    );
  }

  Widget _formView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Entrance(
          child: Icon(Icons.mail_outline, size: 28, color: SeenlyPalette.accent),
        ),
        const SizedBox(height: 12),
        Entrance(
          delay: const Duration(milliseconds: 60),
          child: Text('forgot your password?'.tr,
              textAlign: TextAlign.center,
              style: SeenlyText.serif(size: 24, weight: FontWeight.w600)),
        ),
        const SizedBox(height: 8),
        Entrance(
          delay: const Duration(milliseconds: 110),
          child: Text(
            'enter the email you added to your diary and we\'ll send a link to set a new one'.tr,
            textAlign: TextAlign.center,
            style: SeenlyText.serif(
                italic: true, size: 13, color: SeenlyPalette.inkMuted),
          ),
        ),
        const SizedBox(height: 28),
        Entrance(
          delay: const Duration(milliseconds: 160),
          riseBy: 16,
          child: TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: InputDecoration(hintText: 'email'.tr),
            onSubmitted: (_) => _submit(),
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
          delay: const Duration(milliseconds: 210),
          riseBy: 16,
          child: PrimaryButton(
            label: 'send the link'.tr,
            loading: _loading,
            onTap: _submit,
          ),
        ),
        const SizedBox(height: 14),
        Entrance(
          delay: const Duration(milliseconds: 250),
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
            ),
            child: Text('i already have a link'.tr,
                style: SeenlyText.mono(size: 12, color: SeenlyPalette.accent)),
          ),
        ),
      ],
    );
  }

  Widget _sentView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Entrance(
          child: Icon(Icons.mark_email_read_outlined,
              size: 30, color: SeenlyPalette.accent),
        ),
        const SizedBox(height: 14),
        Entrance(
          delay: const Duration(milliseconds: 60),
          child: Text('check your inbox'.tr,
              textAlign: TextAlign.center,
              style: SeenlyText.serif(size: 22, weight: FontWeight.w600)),
        ),
        const SizedBox(height: 10),
        Entrance(
          delay: const Duration(milliseconds: 110),
          child: Text(
            _sentMessage!,
            textAlign: TextAlign.center,
            style: SeenlyText.serif(size: 13, color: SeenlyPalette.inkMuted),
          ),
        ),
        const SizedBox(height: 8),
        Entrance(
          delay: const Duration(milliseconds: 150),
          child: Text(
            'the link works for one hour. nothing has changed until you use it'.tr,
            textAlign: TextAlign.center,
            style: SeenlyText.mono(size: 10, color: SeenlyPalette.placeholder),
          ),
        ),
        const SizedBox(height: 26),
        Entrance(
          delay: const Duration(milliseconds: 190),
          child: PrimaryButton(
            label: 'i have the link'.tr,
            onTap: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Entrance(
          delay: const Duration(milliseconds: 230),
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('back to sign in'.tr,
                style: SeenlyText.mono(size: 12, color: SeenlyPalette.inkMuted)),
          ),
        ),
      ],
    );
  }
}
