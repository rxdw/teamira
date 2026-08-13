import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/error_text.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/small_pieces.dart';

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
          'username needs 3+ characters, password needs 6+');
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
                Text('start your diary',
                    textAlign: TextAlign.center,
                    style: SeenlyText.serif(size: 24, weight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('a shelf just for you — takes a minute',
                    textAlign: TextAlign.center,
                    style: SeenlyText.serif(
                        italic: true,
                        size: 13,
                        color: SeenlyPalette.inkMuted)),
                const SizedBox(height: 28),
                TextField(
                  controller: _username,
                  decoration: const InputDecoration(hintText: 'pick a username'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(hintText: 'pick a password'),
                ),
                if (_showReferralField) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _referralCode,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(hintText: "a friend's invite code"),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setState(() => _showReferralField = true),
                      child: Text('have an invite code?',
                          style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent)),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!,
                      style: SeenlyText.mono(size: 11, color: SeenlyPalette.coral)),
                ],
                const SizedBox(height: 20),
                PrimaryButton(
                  label: 'create my diary',
                  loading: _loading,
                  onTap: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
