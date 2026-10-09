import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_translations.dart';
import '../services/error_text.dart';
import '../services/moderation_service.dart';
import '../state/app_state.dart';
import '../theme/palette.dart';
import '../theme/text_styles.dart';
import 'small_pieces.dart';
import '../theme/clay_kit.dart';

/// "Report this" — the sheet behind every report entry point in the app.
///
/// One widget rather than one per surface, because a profile, a diary
/// note, an activity card and a list all need the same three things: pick
/// a reason, optionally say more, optionally block them at the same time.
///
/// Two decisions worth naming:
///
///   - **Blocking is offered here but is its own action.** The checkbox
///     defaults to on, because someone reporting harassment almost always
///     also wants it to stop right now, and a report only promises a look
///     within 24 hours. But it stays separable: reporting spam you don't
///     personally care about shouldn't force a block, and blocking someone
///     you simply don't get on with shouldn't file a complaint about them.
///   - **The confirmation states the 24-hour commitment.** It's what the
///     backend actually does (models.Report.due_at, and the queue is
///     sorted by it), so saying it is honest rather than aspirational —
///     and it's what makes people willing to use the flow a second time.
Future<bool> showReportSheet(
  BuildContext context, {
  required String reportedUserId,
  required String reportedName,
  ReportTarget target = ReportTarget.user,
  String? targetId,
  bool offerBlock = true,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReportSheet(
      reportedUserId: reportedUserId,
      reportedName: reportedName,
      target: target,
      targetId: targetId,
      offerBlock: offerBlock,
    ),
  );
  return result ?? false;
}

class _ReportSheet extends StatefulWidget {
  final String reportedUserId;
  final String reportedName;
  final ReportTarget target;
  final String? targetId;
  final bool offerBlock;

  const _ReportSheet({
    required this.reportedUserId,
    required this.reportedName,
    required this.target,
    required this.targetId,
    required this.offerBlock,
  });

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  ReportReason? _reason;
  final _details = TextEditingController();
  late bool _alsoBlock = widget.offerBlock;
  bool _loading = false;
  String? _error;
  bool _sent = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null) {
      setState(() => _error = 'pick a reason first'.tr);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final moderation = context.read<AppState>().moderation;
    try {
      await moderation.report(
        target: widget.target,
        reportedUserId: widget.reportedUserId,
        targetId: widget.targetId,
        reason: reason,
        details: _details.text,
      );
      if (_alsoBlock) {
        // Blocked after the report, not before: a block tears down the
        // friendship and pending requests server-side, and if that half
        // failed we'd rather still have the complaint on file than lose
        // both.
        try {
          await moderation.block(widget.reportedUserId);
        } catch (_) {
          // The report went through, which is the part a human acts on.
          // The block can be repeated from the profile screen.
        }
      }
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 26),
        decoration: ClayBoxDecoration(
          boxShadow: SeenlyPalette.flatCardShadow,
          color: SeenlyPalette.paper,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: _sent ? _sentView() : _formView(),
      ),
    );
  }

  Widget _formView() => Column(
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
          Text('${'report'.tr} ${widget.reportedName}',
              style: SeenlyText.serif(size: 17, weight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('a person reads every report, within 24 hours'.tr,
              style: SeenlyText.serif(size: 12.5, color: SeenlyPalette.inkMuted)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final reason in ReportReason.values)
                GestureDetector(
                  onTap: () => setState(() => _reason = reason),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    decoration: BoxDecoration(
                      color: _reason == reason
                          ? SeenlyPalette.accent
                          : SeenlyPalette.background,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      reason.label.tr,
                      style: SeenlyText.mono(
                        size: 9.5,
                        weight: FontWeight.w700,
                        color: _reason == reason
                            ? SeenlyPalette.accentOnAccent
                            : SeenlyPalette.inkMuted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _details,
            maxLines: 3,
            maxLength: 1000,
            decoration: InputDecoration(
              hintText: 'anything else we should know? (optional)'.tr,
              counterText: '',
            ),
          ),
          if (widget.offerBlock) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => setState(() => _alsoBlock = !_alsoBlock),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Icon(
                    _alsoBlock
                        ? Icons.check_box_outlined
                        : Icons.check_box_outline_blank,
                    size: 18,
                    color: _alsoBlock
                        ? SeenlyPalette.accent
                        : SeenlyPalette.placeholder,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('also block them, straight away'.tr,
                        style: SeenlyText.serif(size: 12.5)),
                  ),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: SeenlyText.mono(size: 11, color: SeenlyPalette.coral)),
          ],
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'send the report'.tr,
            loading: _loading,
            onTap: _submit,
          ),
        ],
      );

  Widget _sentView() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Icon(Icons.check_circle_outline, size: 28, color: SeenlyPalette.accent),
          const SizedBox(height: 12),
          Text('thank you — we\'re on it'.tr,
              textAlign: TextAlign.center,
              style: SeenlyText.serif(size: 16, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            _alsoBlock
                ? 'someone reads this within 24 hours. in the meantime they can\'t reach you'.tr
                : 'someone reads this within 24 hours'.tr,
            textAlign: TextAlign.center,
            style: SeenlyText.serif(size: 12.5, color: SeenlyPalette.inkMuted),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'done'.tr,
            onTap: () => Navigator.of(context).pop(_alsoBlock),
          ),
        ],
      );
}
