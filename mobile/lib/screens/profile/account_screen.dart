import 'dart:convert';
import '../../widgets/wow_motion.dart' show PressScale;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/profile_stats.dart';
import '../../services/app_translations.dart';
import '../../services/auth_service.dart';
import '../../services/error_text.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/small_pieces.dart';
import '../../widgets/themed_loading_indicator.dart';
import 'blocked_users_screen.dart';
import '../../widgets/settings_motion.dart';
import '../../widgets/decide_motion.dart' show BouncingDots;
import '../../widgets/soft_motion.dart';
import '../../theme/clay_kit.dart';

/// Settings → Account.
///
/// Everything about the account as an account, rather than as a profile:
/// how to get back into it, which devices are in it, how to take the
/// diary out of it, and how to end it. Four of the five things on this
/// screen did not exist anywhere in the app before — recovery email,
/// password change, data export and deletion — and the absence of the
/// last one was a hard App Store rejection (guideline 5.1.1(v), in force
/// since June 2022) as well as a GDPR art. 17 / 152-ФЗ problem.
///
/// Ordering is deliberate: recovery first, because it's the one that
/// silently costs someone years of evenings if they never get to it;
/// deletion last and visually separated, because it's irreversible after
/// 30 days and nothing on the way to anything else should pass through it.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  SeenlyUser? _me;
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = await context.read<AppState>().auth.me();
      if (!mounted) return;
      setState(() {
        _me = me;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Email ---------------------------------------------------------------

  Future<void> _editEmail() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _EmailSheet(),
    );
    if (result != null) {
      _toast(result);
      _load();
    }
  }

  // --- Password ------------------------------------------------------------

  Future<void> _changePassword() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PasswordSheet(),
    );
    if (result != null) _toast(result);
  }

  // --- Export --------------------------------------------------------------

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final json = await context.read<AppState>().auth.exportData();
      // Written to a temp file and handed to the OS share sheet rather
      // than shown on screen: the point is to end up with a copy that
      // outlives the app, which means it has to leave the app. Same
      // pattern the premium "diary keepsake" PDF already uses.
      final dir = await getTemporaryDirectory();
      final name = 'tane-diary-${DateTime.now().toIso8601String().split('T').first}.json';
      final file = File('${dir.path}/$name');
      await file.writeAsString(json, encoding: utf8);
      await Share.shareXFiles([XFile(file.path)], subject: 'tanè — my diary'.tr);
    } catch (e) {
      _toast(describeError(e));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // --- Deletion ------------------------------------------------------------

  Future<void> _deleteAccount() async {
    final confirmed = await showModalBottomSheet<AccountDeletion>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _DeleteAccountSheet(),
    );
    if (confirmed == null || !mounted) return;
    // The app is already signed out by this point. One last screen,
    // because the restore window is the single most important thing the
    // person could know and it's about to stop being visible anywhere.
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SeenlyPalette.paper,
        title: Text('your account is deleted'.tr,
            style: SeenlyText.serif(size: 16, weight: FontWeight.w600)),
        content: Text(confirmed.message,
            style: SeenlyText.serif(size: 13, color: SeenlyPalette.inkMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('understood'.tr,
                style: SeenlyText.mono(size: 12, color: SeenlyPalette.accent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      appBar: AppBar(
        backgroundColor: SeenlyPalette.background,
        elevation: 0,
        iconTheme: IconThemeData(color: SeenlyPalette.inkMuted),
        title: Text('account'.tr, style: SeenlyText.serif(size: 16)),
      ),
      body: LoadSwap(
        loaded: !_loading,
        loading: const Center(child: ThemedLoadingIndicator()),
        content: ListView(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
              // The sections settle in from the top, one after another.
              children: staggerChildren([
                if (me != null && me.needsRecoveryEmail) _recoveryNudge(),
                _sectionLabel('getting back in'.tr),
                _card([
                  _row(
                    icon: Icons.mail_outline,
                    title: me?.email ?? 'add a recovery email'.tr,
                    subtitle: me?.email == null
                        ? 'without one, a forgotten password means the diary is gone'.tr
                        : (me!.emailVerified
                            ? 'confirmed — you can recover your account with it'.tr
                            : 'not confirmed yet — tap to send the link again'.tr),
                    onTap: _editEmail,
                  ),
                  _divider(),
                  _row(
                    icon: Icons.password_outlined,
                    title: 'change password'.tr,
                    subtitle: 'signs out every other device'.tr,
                    onTap: _changePassword,
                  ),
                  _divider(),
                  _row(
                    icon: Icons.devices_outlined,
                    title: 'where you\'re signed in'.tr,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const _SessionsScreen()),
                    ),
                  ),
                ]),
                const SizedBox(height: 22),
                _sectionLabel('people'.tr),
                _card([
                  _row(
                    icon: Icons.block_outlined,
                    title: 'blocked accounts'.tr,
                    subtitle: 'they can\'t see you, and you can\'t see them'.tr,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const BlockedUsersScreen()),
                    ),
                  ),
                ]),
                const SizedBox(height: 22),
                _sectionLabel('your data'.tr),
                _card([
                  _row(
                    icon: Icons.download_outlined,
                    title: 'download everything'.tr,
                    subtitle:
                        'every evening, list and rating, as one file you keep'.tr,
                    trailing: _exporting
                        ? BouncingDots(color: SeenlyPalette.accent, dotSize: 4)
                        : null,
                    onTap: _export,
                  ),
                ]),
                const SizedBox(height: 30),
                // Set apart from everything above, in the coral the rest
                // of the app reserves for leaving.
                PressScale(
                  onTap: _deleteAccount,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: ClayBoxDecoration(
                      boxShadow: SeenlyPalette.flatCardShadow,
                      color: SeenlyPalette.paper,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: SeenlyPalette.coral.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 17, color: SeenlyPalette.coral),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('delete account'.tr,
                                  style: SeenlyText.serif(
                                      italic: true, color: SeenlyPalette.coral)),
                              const SizedBox(height: 2),
                              Text(
                                'you have 30 days to change your mind'.tr,
                                style: SeenlyText.mono(
                                    size: 9, color: SeenlyPalette.placeholder),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
      ),
    );
  }

  Widget _recoveryNudge() => Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SeenlyPalette.accent.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, size: 17, color: SeenlyPalette.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'your diary has no way back in. add an email and a forgotten password stops being the end of it'
                    .tr,
                style: SeenlyText.serif(size: 12.5, color: SeenlyPalette.inkMuted),
              ),
            ),
          ],
        ),
      );

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text,
            style: SeenlyText.mono(
                size: 9.5,
                weight: FontWeight.w700,
                color: SeenlyPalette.placeholder)),
      );

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.all(14),
        decoration: ClayBoxDecoration(
          boxShadow: SeenlyPalette.flatCardShadow,
          color: SeenlyPalette.paper,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _divider() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Container(height: 1, color: SeenlyPalette.border),
      );

  Widget _row({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) =>
      PressScale(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 16, color: SeenlyPalette.inkMuted),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: SeenlyText.serif(size: 13)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: SeenlyText.mono(
                            size: 9, color: SeenlyPalette.placeholder)),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// Sheets
// ---------------------------------------------------------------------------

/// The shared paper-card sheet shape the rest of the app uses for
/// anything that asks for a password.
class _SheetShell extends StatelessWidget {
  final String title;
  final String? blurb;
  final List<Widget> children;
  const _SheetShell({required this.title, this.blurb, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 26),
        decoration: ClayBoxDecoration(
          boxShadow: SeenlyPalette.flatCardShadow,
          color: SeenlyPalette.paper,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 34,
                height: 3,
                decoration: BoxDecoration(
                  color: SeenlyPalette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(title, style: SeenlyText.serif(size: 17, weight: FontWeight.w600)),
            if (blurb != null) ...[
              const SizedBox(height: 6),
              Text(blurb!,
                  style: SeenlyText.serif(size: 12.5, color: SeenlyPalette.inkMuted)),
            ],
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _EmailSheet extends StatefulWidget {
  const _EmailSheet();

  @override
  State<_EmailSheet> createState() => _EmailSheetState();
}

class _EmailSheetState extends State<_EmailSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final message = await context
          .read<AppState>()
          .auth
          .setEmail(_email.text, _password.text);
      if (mounted) Navigator.of(context).pop(message);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'recovery email'.tr,
      // The password requirement is explained rather than just imposed —
      // an address can be traded for the account itself through reset, so
      // being able to set one from an unlocked phone would make the
      // password beside the point.
      blurb: 'we\'ll send a link to confirm it. your password is needed because this address can be used to get into your account'
          .tr,
      children: [
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(hintText: 'email'.tr),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: InputDecoration(hintText: 'your password'.tr),
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: SeenlyText.mono(size: 11, color: SeenlyPalette.coral)),
        ],
        const SizedBox(height: 18),
        PrimaryButton(label: 'send the link'.tr, loading: _loading, onTap: _submit),
      ],
    );
  }
}

class _PasswordSheet extends StatefulWidget {
  const _PasswordSheet();

  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_next.text.length < 6) {
      setState(() => _error = 'password needs at least 6 characters'.tr);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AppState>().auth.changePassword(_current.text, _next.text);
      if (mounted) Navigator.of(context).pop('password changed'.tr);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'change password'.tr,
      blurb: 'every other device is signed out. this one stays signed in'.tr,
      children: [
        TextField(
          controller: _current,
          obscureText: true,
          decoration: InputDecoration(hintText: 'current password'.tr),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _next,
          obscureText: true,
          decoration: InputDecoration(hintText: 'new password'.tr),
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: SeenlyText.mono(size: 11, color: SeenlyPalette.coral)),
        ],
        const SizedBox(height: 18),
        PrimaryButton(label: 'save'.tr, loading: _loading, onTap: _submit),
      ],
    );
  }
}

class _DeleteAccountSheet extends StatefulWidget {
  const _DeleteAccountSheet();

  @override
  State<_DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<_DeleteAccountSheet> {
  final _password = TextEditingController();
  final _reason = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await context
          .read<AppState>()
          .deleteAccount(_password.text, reason: _reason.text);
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'delete account'.tr,
      blurb:
          'everything goes: every evening you logged, every list, every rating. you have 30 days to change your mind — signing in before then brings it all back'
              .tr,
      children: [
        // Offered here rather than on the confirmation screen, because
        // this is the moment someone is still thinking about it — and
        // because someone who leaves and then can't get their archive
        // back has a much worse day than one who exported first.
        TextButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.download_outlined, size: 15, color: SeenlyPalette.accent),
          label: Text('download it first'.tr,
              style: SeenlyText.mono(size: 11, color: SeenlyPalette.accent)),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: InputDecoration(hintText: 'confirm with your password'.tr),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _reason,
          maxLines: 2,
          decoration: InputDecoration(hintText: 'anything you\'d like us to know? (optional)'.tr),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: SeenlyText.mono(size: 11, color: SeenlyPalette.coral)),
        ],
        const SizedBox(height: 18),
        PressScale(
          onTap: _loading ? null : _submit,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: SeenlyPalette.coral.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SeenlyPalette.coral.withOpacity(0.5)),
            ),
            child: SoftSwap(
              alignment: Alignment.center,
              duration: const Duration(milliseconds: 220),
              child: _loading
                  ? SizedBox(
                      key: const ValueKey<String>('busy'),
                      height: 20,
                      child: Center(child: BouncingDots(color: SeenlyPalette.coral)),
                    )
                  : Text('delete my account'.tr,
                      key: const ValueKey<String>('label'),
                      style: SeenlyText.serif(
                          italic: true, size: 14, color: SeenlyPalette.coral)),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sessions
// ---------------------------------------------------------------------------

/// "Where you're signed in". Exists because the old setup had no notion
/// of a session at all: a token was good for a week and nothing — not a
/// password change, not a lost phone — could take it back.
class _SessionsScreen extends StatefulWidget {
  const _SessionsScreen();

  @override
  State<_SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<_SessionsScreen> {
  List<AuthSession>? _sessions;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sessions = await context.read<AppState>().auth.sessions();
      if (mounted) setState(() => _sessions = sessions);
    } catch (_) {
      if (mounted) setState(() => _sessions = const []);
    }
  }

  Future<void> _signOutOthers() async {
    setState(() => _working = true);
    try {
      final message = await context.read<AppState>().auth.signOutOtherDevices();
      if (mounted && message.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      appBar: AppBar(
        backgroundColor: SeenlyPalette.background,
        elevation: 0,
        iconTheme: IconThemeData(color: SeenlyPalette.inkMuted),
        title: Text('where you\'re signed in'.tr, style: SeenlyText.serif(size: 16)),
      ),
      body: sessions == null
          ? const Center(child: ThemedLoadingIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
              children: [
                for (final session in sessions)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: ClayBoxDecoration(
                      boxShadow: SeenlyPalette.flatCardShadow,
                      color: SeenlyPalette.paper,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          session.revoked
                              ? Icons.phonelink_erase_outlined
                              : Icons.smartphone_outlined,
                          size: 17,
                          color: session.revoked
                              ? SeenlyPalette.placeholder
                              : SeenlyPalette.accent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(session.deviceLabel ?? 'unknown device'.tr,
                                  style: SeenlyText.serif(
                                      size: 13,
                                      color: session.revoked
                                          ? SeenlyPalette.placeholder
                                          : null)),
                              const SizedBox(height: 2),
                              Text(
                                session.revoked
                                    ? 'signed out'.tr
                                    : (session.lastUsedAt != null
                                        ? '${'last used'.tr} ${session.lastUsedAt!.toLocal().toString().split('.').first}'
                                        : 'active'.tr),
                                style: SeenlyText.mono(
                                    size: 9, color: SeenlyPalette.placeholder),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                PrimaryButton(
                  label: 'sign out everywhere else'.tr,
                  loading: _working,
                  onTap: _signOutOthers,
                ),
                const SizedBox(height: 10),
                Text(
                  'this device stays signed in. every other one has to sign in again'.tr,
                  textAlign: TextAlign.center,
                  style: SeenlyText.mono(size: 9, color: SeenlyPalette.placeholder),
                ),
              ],
            ),
    );
  }
}
