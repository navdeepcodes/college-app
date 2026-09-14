import 'package:flutter/material.dart';

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
        backgroundColor: const Color(0xFF1E1E22),
        title: const Text('Report'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final reason in _reasons)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  selectedReason == reason
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(reason),
                onTap: () => setState(() => selectedReason = reason),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: detailsController,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Additional details (optional)',
                border: OutlineInputBorder(),
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
