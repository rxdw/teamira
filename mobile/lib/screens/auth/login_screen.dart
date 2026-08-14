import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/error_text.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/wow_motion.dart' show Entrance;
import 'register_screen.dart';

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
                  child: Text('teamira',
                      textAlign: TextAlign.center,
                      style: SeenlyText.serif(size: 30, weight: FontWeight.w600)),
                ),
                const SizedBox(height: 6),
                Entrance(
                  delay: const Duration(milliseconds: 110),
                  child: Text('welcome back to your evening diary',
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
                    decoration: const InputDecoration(hintText: 'username'),
                  ),
                ),
                const SizedBox(height: 12),
                Entrance(
                  delay: const Duration(milliseconds: 200),
                  riseBy: 16,
                  child: TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(hintText: 'password'),
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
                    label: 'sign in',
                    loading: _loading,
                    onTap: _submit,
                  ),
                ),
                const SizedBox(height: 16),
                Entrance(
                  delay: const Duration(milliseconds: 290),
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
                    ),
                    child: Text('new here? start a diary',
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
