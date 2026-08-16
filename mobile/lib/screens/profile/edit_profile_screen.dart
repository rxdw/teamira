import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/profile_stats.dart';
import '../../state/app_state.dart';
import '../../theme/palette.dart';
import '../../theme/text_styles.dart';
import '../../widgets/themed_loading_indicator.dart';
import '../../widgets/user_avatar.dart';
import '../../services/app_translations.dart';

/// Edits the one part of the profile that isn't derived from watch
/// history — name, avatar, status line. Reads its starting values from
/// AppState.currentUser (already fresh from /auth/me) rather than a
/// separate GET /profile/me round trip, and writes back through
/// AppState.refreshCurrentUser() on save so the header updates the
/// moment this screen closes.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _statusController;
  String? _avatarPreset;
  String? _avatarUrl;
  bool _saving = false;
  bool _uploadingPhoto = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = context.read<AppState>().currentUser;
    _nameController = TextEditingController(text: user?.displayName ?? '');
    _statusController = TextEditingController(text: user?.statusText ?? '');
    _avatarPreset = user?.avatarPreset;
    _avatarUrl = user?.avatarUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  void _pickPreset(String presetId) {
    setState(() {
      _avatarPreset = presetId;
      _avatarUrl = null; // mutually exclusive — see backend's own note on this
    });
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 85);
    if (picked == null) return;
    setState(() => _uploadingPhoto = true);
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.path.split('.').last.toLowerCase();
      final contentType = switch (ext) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
      final url = await context
          .read<AppState>()
          .profile
          .uploadAvatar(bytes, filename: picked.name, contentType: contentType);
      if (!mounted) return;
      setState(() {
        _avatarUrl = url;
        _avatarPreset = null;
        _uploadingPhoto = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не получилось загрузить фото: $e'.tr)));
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final app = context.read<AppState>();
      await app.profile.updateMe(
        displayName: _nameController.text.trim(),
        statusText: _statusController.text.trim(),
        // Only send avatarPreset here when it's the active choice — an
        // uploaded photo already saved itself via /profile/avatar the
        // moment it was picked (see _pickPhoto). Sending '' clears back
        // to no preset if neither a preset nor a fresh photo is active.
        avatarPreset: _avatarUrl == null ? (_avatarPreset ?? '') : null,
      );
      await app.refreshCurrentUser();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Не получилось сохранить: $e'.tr;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final username = context.watch<AppState>().currentUser?.username ?? '';
    final letter = username.isNotEmpty ? username.substring(0, 1).toLowerCase() : '?';

    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      appBar: AppBar(
        backgroundColor: SeenlyPalette.background,
        elevation: 0,
        title: Text('редактировать профиль'.tr, style: SeenlyText.serif(size: 17, italic: true)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: ThemedLoadingIndicator(size: 16))
                : Text('сохранить'.tr, style: SeenlyText.mono(size: 12, color: SeenlyPalette.accent)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                UserAvatar(
                  avatarUrl: _avatarUrl,
                  avatarPreset: _avatarPreset,
                  fallbackLetter: letter,
                  size: 88,
                ),
                if (_uploadingPhoto)
                  const Positioned.fill(child: Center(child: ThemedLoadingIndicator(size: 22))),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: TextButton.icon(
              onPressed: _uploadingPhoto ? null : _pickPhoto,
              icon: const Icon(Icons.photo_camera_outlined, size: 16),
              label: Text('загрузить своё фото'.tr, style: SeenlyText.mono(size: 12)),
            ),
          ),
          const SizedBox(height: 8),
          Text('или выбери готовый аватар'.tr, style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: kAvatarPresets.map((preset) {
              final selected = _avatarUrl == null && _avatarPreset == preset.id;
              return GestureDetector(
                onTap: () => _pickPreset(preset.id),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? SeenlyPalette.accent : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child: Image.asset(preset.assetPath, width: 52, height: 52, fit: BoxFit.cover),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),
          Text('имя'.tr, style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint)),
          const SizedBox(height: 6),
          TextField(
            controller: _nameController,
            maxLength: 40,
            style: SeenlyText.serif(size: 16),
            decoration: InputDecoration(
              hintText: username,
              border: const OutlineInputBorder(),
              counterText: '',
            ),
          ),
          const SizedBox(height: 20),
          Text('статус'.tr, style: SeenlyText.mono(size: 11, color: SeenlyPalette.inkFaint)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kStatusPresets.map((preset) {
              return ActionChip(
                label: Text(preset, style: SeenlyText.mono(size: 11)),
                onPressed: () => setState(() => _statusController.text = preset),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _statusController,
            maxLength: 120,
            maxLines: 2,
            style: SeenlyText.serif(size: 14),
            decoration: InputDecoration(
              hintText: 'своё, или очисти поле — статус пропадёт'.tr,
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: SeenlyText.mono(size: 12, color: Colors.red)),
          ],
        ],
      ),
    );
  }
}
