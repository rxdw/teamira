import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_translations.dart';
import '../../services/error_text.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/wow_motion.dart' show Entrance;

/// Sets a new password from a reset link.
///
/// [token] is filled in automatically when the app is opened by the link
/// itself (see ReferralLinkService's deep-link listener, which the reset
/// scheme rides on). It stays a plain, editable field for everyone else:
/// the link opens in a browser on plenty of setups, and "copy the code
/// from the page and paste it here" has to work or the whole recovery
/// path has a hole in it on exactly the devices most likely to need it.
class ResetPasswordScreen extends StatefulWidget {
  final String? token;
  const ResetPasswordScreen({super.key, this.token});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  late final TextEditingController _token =
      TextEditingController(text: widget.token ?? '');
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _done;

  @override
  void dispose() {
    _token.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final token = _token.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'paste the code from your email first'.tr);
      return;
    }
    if (_password.text.length < 6) {
      setState(() => _error = 'password needs at least 6 characters'.tr);
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'the two passwords don\'t match'.tr);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final message = await context
          .read<AppState>()
          .auth
          .resetPassword(token, _password.text);
      if (mounted) setState(() => _done = message);
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _done != null ? _doneChildren() : _formChildren(),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _formChildren() => [
        Entrance(
          child: Icon(Icons.lock_reset_outlined, size: 28, color: SeenlyPalette.accent),
        ),
        const SizedBox(height: 12),
        Entrance(
          delay: const Duration(milliseconds: 60),
          child: Text('set a new password'.tr,
              textAlign: TextAlign.center,
              style: SeenlyText.serif(size: 24, weight: FontWeight.w600)),
        ),
        const SizedBox(height: 24),
        if (widget.token == null) ...[
          Entrance(
            delay: const Duration(milliseconds: 110),
            riseBy: 16,
            child: TextField(
              controller: _token,
              autocorrect: false,
              decoration: InputDecoration(hintText: 'code from the email'.tr),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Entrance(
          delay: const Duration(milliseconds: 150),
          riseBy: 16,
          child: TextField(
            controller: _password,
            obscureText: true,
            decoration: InputDecoration(hintText: 'new password'.tr),
          ),
        ),
        const SizedBox(height: 12),
        Entrance(
          delay: const Duration(milliseconds: 190),
          riseBy: 16,
          child: TextField(
            controller: _confirm,
            obscureText: true,
            decoration: InputDecoration(hintText: 'repeat the new password'.tr),
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
          delay: const Duration(milliseconds: 230),
          riseBy: 16,
          child: PrimaryButton(
            label: 'save the new password'.tr,
            loading: _loading,
            onTap: _submit,
          ),
        ),
        const SizedBox(height: 14),
        // Said out loud because it's about to happen and is otherwise
        // alarming: a reset is the answer to "someone may have my
        // password", so every signed-in device has to be signed out,
        // including whichever one prompted the reset.
        Text(
          'this signs you out on every device — sign in again with the new password'.tr,
          textAlign: TextAlign.center,
          style: SeenlyText.mono(size: 9.5, color: SeenlyPalette.placeholder),
        ),
      ];

  List<Widget> _doneChildren() => [
        Entrance(
          child: Icon(Icons.check_circle_outline, size: 30, color: SeenlyPalette.accent),
        ),
        const SizedBox(height: 14),
        Entrance(
          delay: const Duration(milliseconds: 60),
          child: Text(_done!,
              textAlign: TextAlign.center,
              style: SeenlyText.serif(size: 16, weight: FontWeight.w600)),
        ),
        const SizedBox(height: 26),
        Entrance(
          delay: const Duration(milliseconds: 110),
          child: PrimaryButton(
            label: 'back to sign in'.tr,
            onTap: () => Navigator.of(context)
                .popUntil((route) => route.isFirst),
          ),
        ),
      ];
}
