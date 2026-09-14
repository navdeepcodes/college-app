import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/haptics.dart';
import '../core/spacing.dart';
import '../services/moderation_service.dart';

const _reasons = [
  'Spam',
  'Harassment or bullying',
  'Inappropriate content',
  'Impersonation',
  'Other',
];

/// Shows the report reason picker and files the report. Returns true if a
/// report was actually filed (so the caller can show its own confirmation),
/// false if the user cancelled.
Future<bool> showReportDialog(
  BuildContext context, {
  required String targetType,
  required String targetId,
}) async {
  String? selectedReason;
  final detailsController = TextEditingController();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Report'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final reason in _reasons)
              _ReasonRow(
                label: reason,
                selected: selectedReason == reason,
                onTap: () => setState(() => selectedReason = reason),
              ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: detailsController,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Additional details (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: selectedReason == null
                ? null
                : () => Navigator.pop(context, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    ),
  );

  if (confirmed != true || selectedReason == null) return false;
  if (!context.mounted) return false;

  AppHaptics.confirm();
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ModerationService.report(
      targetType: targetType,
      targetId: targetId,
      reason: selectedReason!,
      details: detailsController.text,
    );
    messenger.showSnackBar(
      const SnackBar(content: Text('Report submitted. Thanks for flagging it.')),
    );
    return true;
  } catch (e) {
    debugPrint('Report submit failed: $e');
    // 23505 is the reports table's unique(reporter_uid, target_type,
    // target_id) constraint -- reporting the same thing twice, which is a
    // normal double-tap/repeat-visit case, not a real failure.
    final alreadyReported = e.toString().contains('23505');
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          alreadyReported
              ? 'You already reported this.'
              : 'Could not submit report. Try again.',
        ),
      ),
    );
    return false;
  }
}

class _ReasonRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ReasonRow({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.accent : Colors.transparent,
                border: Border.all(
                  color: selected ? AppColors.accent : AppColors.borderStrong,
                  width: 1.6,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: AppSpace.md),
            Text(label, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}
