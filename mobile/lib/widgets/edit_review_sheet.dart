import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/diary_entry.dart';
import '../models/media_item.dart' show CastMember;
import '../state/app_state.dart';
import '../state/diary_store.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'heart_rating.dart';
import 'mood_tag_picker.dart';
import 'review_composer.dart';
import 'sincerity_toast.dart';
import 'tear_ticket_confirm.dart';
import 'themed_loading_indicator.dart';
import 'wow_motion.dart' show PressScale;
import '../services/app_translations.dart';
import '../theme/clay_kit.dart';

/// What [showEditReviewSheet] resolved with. `deleted` means the person
/// removed the evening entirely rather than saving changes to it — see
/// [_EditReviewSheetState._confirmDelete]. `entry` carries the saved
/// [DiaryEntry] on a normal save, and is null both when nothing was
/// deleted (no reason to look at it) and when the sheet was dismissed
/// without saving (see the top-level `null` case below, which callers
/// tell apart from this by the result itself being null).
class EditReviewResult {
  final DiaryEntry? entry;
  final bool deleted;
  const EditReviewResult.saved(DiaryEntry this.entry) : deleted = false;
  const EditReviewResult.deleted()
      : entry = null,
        deleted = true;
}

/// Opens the "edit this evening" sheet for an already-logged [DiaryEntry]
/// — the rating, the review text, and the mood tags. This is the one
/// place editing happens for a logged evening; it's reached from
/// [WatchedPreviewCard] (see widgets/watched_preview_sheet.dart), which is
/// itself the single spot every screen that shows a past entry — the
/// diary tab, home, the title screen's rewatch timeline, the profile's
/// watched grid, the garden bed, the ticket jar, the evening road —
/// funnels a tap into. Resolves with an [EditReviewResult] on save or
/// delete, or null if the sheet was dismissed without either.
Future<EditReviewResult?> showEditReviewSheet(BuildContext context, DiaryEntry entry) {
  return Navigator.of(context).push<EditReviewResult?>(
    MaterialPageRoute(builder: (context) => _EditReviewSheet(entry: entry)),
  );
}

class _EditReviewSheet extends StatefulWidget {
  final DiaryEntry entry;
  const _EditReviewSheet({required this.entry});

  @override
  State<_EditReviewSheet> createState() => _EditReviewSheetState();
}

class _EditReviewSheetState extends State<_EditReviewSheet> {
  late int _rating;
  late final TextEditingController _noteController;
  late List<String> _moodTags;
  // Up to 3 cast members picked as this evening's standouts — starts
  // from whatever was already saved (see the themed log flows' own
  // castPick step for where this first gets set). The full cast list
  // to pick from isn't on DiaryEntry itself (only the up-to-3 already
  // chosen are), so it's fetched below once we know the title —
  // null while that's in flight or if it never resolves, in which
  // case the section just stays quietly absent rather than blocking
  // the rest of the sheet.
  late List<CastMember> _favoriteCast;
  List<CastMember>? _availableCast;
  bool _saving = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _rating = widget.entry.rating ?? 0;
    _noteController = TextEditingController(text: widget.entry.note ?? '');
    _moodTags = List<String>.from(widget.entry.moodTags);
    _favoriteCast = List<CastMember>.from(widget.entry.favoriteCast);
    _loadCast();
  }

  Future<void> _loadCast() async {
    try {
      final detail = await context.read<AppState>().media.detail(
            mediaId: widget.entry.mediaId,
            mediaType: widget.entry.mediaType,
            source: widget.entry.source,
          );
      if (!mounted) return;
      setState(() => _availableCast = detail?.item.cast ?? []);
    } catch (_) {
      // Best-effort, same "quietly absent" degrade as everywhere else
      // optional supplementary data is fetched in this app.
      if (mounted) setState(() => _availableCast = []);
    }
  }

  void _toggleCastPick(CastMember member) {
    final already = _favoriteCast.any((m) => m.personId == member.personId && m.name == member.name);
    if (!already && _favoriteCast.length >= 3) return;
    setState(() {
      _favoriteCast = already
          ? _favoriteCast.where((m) => !(m.personId == member.personId && m.name == member.name)).toList()
          : [..._favoriteCast, member];
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  // The review box's "write more, full page" link — same roomier-view-
  // onto-the-same-text reasoning as review_composer.dart's own docstring.
  Future<void> _expandReview() async {
    final result = await showReviewComposer(
      context,
      initialText: _noteController.text,
      forTitle: widget.entry.displayTitle,
    );
    if (result != null) setState(() => _noteController.text = result);
  }

  Future<void> _save() async {
    if (_saving || _deleting) return;
    setState(() => _saving = true);
    try {
      // Optimistic — see Фаза 2.15.3 in the launch plan: the store
      // reflects this change instantly (before the request below even
      // resolves), so anywhere else this entry is shown — the diary
      // list behind this sheet, the profile grid — updates right away
      // too, not just this sheet. Same await/pop-on-success/
      // snackbar-on-failure flow as before either way.
      final updated = await context.read<DiaryStore>().updateEntry(
            widget.entry.id,
            rating: _rating > 0 ? _rating : null,
            note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
            moodTags: _moodTags.isEmpty ? null : _moodTags,
            favoriteCast: _favoriteCast.isEmpty ? null : _favoriteCast,
          );
      if (mounted) {
        showSincerityToasts(context, updated.sincerityAwarded);
        Navigator.of(context).pop(EditReviewResult.saved(updated));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("couldn't save those changes — try again".tr)),
      );
    }
  }

  /// Confirms — by tearing, same physical "undo" gesture the route-
  /// cancel flow uses (see journey_progress_screen's own
  /// `_confirmCancelRoute`) — then deletes this evening outright. See
  /// `DELETE /diary/{entry_id}` on the backend for what that cascades
  /// into (the watchlist shelf re-syncing to whatever evening's now the
  /// most recent, or dropping back to plan-to-watch if none are left).
  /// Pops the whole sheet with a `deleted` result so the preview card
  /// underneath (see WatchedPreviewCard._edit) knows to close itself
  /// too, rather than sitting on data that no longer exists.
  Future<void> _confirmDelete() async {
    if (_saving || _deleting) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: Container(
          decoration: ClayBoxDecoration(
            boxShadow: SeenlyPalette.flatCardShadow,
            color: SeenlyPalette.paper,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: SeenlyPalette.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 18),
              Text('delete this evening?'.tr, style: SeenlyText.serif(italic: true, size: 18)),
              const SizedBox(height: 6),
              Text(
                widget.entry.season != null
                    ? "this removes your rating, review, and episode progress for this show — it'll drop back to plan to watch."
                    : "this removes your rating and review for this evening. if it's the only time you logged this title, it'll drop back to plan to watch.",
                maxLines: 3,
                style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkFaint),
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: 124,
                child: TearTicketConfirm(
                  label: 'pull apart to tear it up'.tr,
                  confirmedLabel: 'torn'.tr,
                  accent: SeenlyPalette.coral,
                  onConfirmed: () => Navigator.of(sheetContext).pop(true),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                  child: Text('keep it'.tr, style: SeenlyText.mono(size: 10.5, color: SeenlyPalette.inkMuted)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      // Optimistic removal, same store, same reasoning as _save above.
      await context.read<DiaryStore>().delete(widget.entry.id);
      if (mounted) Navigator.of(context).pop(const EditReviewResult.deleted());
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("couldn't delete this entry — try again".tr)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeenlyPalette.background,
      appBar: AppBar(
        backgroundColor: SeenlyPalette.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: (_saving || _deleting) ? null : () => Navigator.of(context).pop(),
        ),
        title: Text('edit this evening'.tr, style: SeenlyText.serif(italic: true, size: 16)),
        centerTitle: false,
        actions: [
          TextButton(
            onPressed: (_saving || _deleting) ? null : _save,
            child: _saving
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.accent),
                  )
                : Text('save'.tr,
                    style: SeenlyText.serif(size: 13, weight: FontWeight.w600, color: SeenlyPalette.accent)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.entry.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
              const SizedBox(height: 18),
              Text('rating'.tr, style: SeenlyText.metaLabel),
              const SizedBox(height: 8),
              Row(
                children: [
                  HeartRating(
                    value: _rating,
                    size: 20,
                    onChanged: (v) => setState(() => _rating = v == _rating ? 0 : v),
                  ),
                  if (_rating > 0) ...[
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => setState(() => _rating = 0),
                      child: Text('clear'.tr,
                          style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 18),
              Text('review'.tr, style: SeenlyText.metaLabel),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: ClayBoxDecoration(
                  boxShadow: SeenlyPalette.flatCardShadow,
                  color: SeenlyPalette.paper,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TextField(
                  controller: _noteController,
                  maxLines: 5,
                  minLines: 3,
                  style: SeenlyText.serif(italic: true, size: 13),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'what did you think?'.tr,
                    hintStyle: SeenlyText.serif(
                        italic: true, size: 13, color: SeenlyPalette.placeholder),
                  ),
                ),
              ),
              ExpandReviewLink(onTap: _expandReview),
              const SizedBox(height: 18),
              Text(vibePromptTitle(_rating), style: SeenlyText.metaLabel),
              const SizedBox(height: 8),
              MoodTagPicker(
                selected: _moodTags,
                onChanged: (next) => setState(() => _moodTags = next),
                rating: _rating,
              ),
              if ((_availableCast ?? const []).isNotEmpty) ...[
                const SizedBox(height: 22),
                Text('cast'.tr, style: SeenlyText.metaLabel),
                const SizedBox(height: 4),
                Text(
                  _favoriteCast.isEmpty ? 'who stood out? pick up to 3' : '${_favoriteCast.length}/3 picked',
                  style: SeenlyText.mono(size: 10, color: SeenlyPalette.inkFaint),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    const spacing = 14.0;
                    final tileWidth = (constraints.maxWidth - spacing * 2) / 3;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: 20,
                      children: [
                        for (final member in _availableCast!)
                          _EditCastPickTile(
                            member: member,
                            width: tileWidth,
                            selected: _favoriteCast.any((m) => m.personId == member.personId && m.name == member.name),
                            atCap: _favoriteCast.length >= 3,
                            onTap: () => _toggleCastPick(member),
                          ),
                      ],
                    );
                  },
                ),
              ],
              const SizedBox(height: 34),
              // Sits alone at the bottom, well clear of everything above
              // it — a destructive action shouldn't be reachable by the
              // same absent-minded tap as "save".
              Center(
                child: TextButton.icon(
                  onPressed: (_saving || _deleting) ? null : _confirmDelete,
                  icon: _deleting
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: ThemedLoadingIndicator(strokeWidth: 2, color: SeenlyPalette.coral),
                        )
                      : Icon(Icons.delete_outline, size: 15, color: SeenlyPalette.coral),
                  label: Text('delete this evening'.tr,
                      style: SeenlyText.mono(size: 11, color: SeenlyPalette.coral)),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// One selectable face on the edit sheet's cast section — same
/// fixed-height tile as the themed log flows' own cast-pick step (see
/// e.g. cinema_log_screen.dart's _CastPickTile): full name allowed to
/// wrap onto 2 lines rather than being clipped, character name shown
/// underneath when TMDB has one, and a reserved height for both so the
/// grid stays even regardless of how many lines any one name wraps to.
class _EditCastPickTile extends StatelessWidget {
  final CastMember member;
  final double width;
  final bool selected;
  final bool atCap;
  final VoidCallback onTap;

  const _EditCastPickTile({
    required this.member,
    required this.width,
    required this.selected,
    required this.atCap,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dimmed = atCap && !selected;
    // Avatar fills most of the tile's own width — leaves just enough
    // margin on each side for the selection ring and its glow to not
    // touch the neighbouring tile.
    final avatarSize = (width - 12).clamp(56.0, 120.0);
    return PressScale(
      onTap: onTap,
      scaleTo: 0.93,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: dimmed ? 0.4 : 1.0,
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? SeenlyPalette.accent : Colors.transparent,
                    width: 2.5,
                  ),
                  boxShadow: selected
                      ? [BoxShadow(color: SeenlyPalette.accent.withOpacity(0.35), blurRadius: 10, spreadRadius: 1)]
                      : null,
                ),
                padding: const EdgeInsets.all(2),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: (member.photoUrl != null)
                          ? Image.network(
                              member.photoUrl!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              errorBuilder: (_, __, ___) => Container(color: SeenlyPalette.accent),
                            )
                          : Container(color: SeenlyPalette.accent),
                    ),
                    if (selected)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: SeenlyPalette.accent,
                            border: Border.all(color: SeenlyPalette.paper, width: 2),
                          ),
                          child: Icon(Icons.favorite, size: 11, color: SeenlyPalette.accentOnAccent),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // Fixed-height reserved for the name (2 lines) and the
              // character line (1 line) regardless of how many lines
              // this particular name wraps to, so the grid reads as
              // even rows. Sized for the real rendered size — small
              // serif/mono text gets floored up to 13px/12px (see
              // text_styles' enforceFloor), and at that size with the
              // 1.3/1.35 line-height these fonts render at, 2 lines of
              // serif needs ~34px and 1 line of mono needs ~17px, not
              // the requested 10.5/9 — undersizing this box clips
              // letters rather than showing the "..." it looks like it
              // should.
              SizedBox(
                height: 36,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Text(member.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SeenlyText.serif(size: 10.5)),
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: 18,
                child: (member.character?.display != null && member.character!.display != '—')
                    ? Align(
                        alignment: Alignment.topCenter,
                        child: Text(member.character!.display,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SeenlyText.mono(size: 9, color: SeenlyPalette.inkFaint)),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
