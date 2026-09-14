import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../spacing.dart';

/// The shared shape behind every "approve or reject this" card in the
/// app — club creation requests, club join requests, reports, friend
/// requests. These four screens had each grown their own slightly
/// different version of the same card; this is the one version, so a
/// design change (spacing, button style, busy state) only has to happen
/// once and every admin surface stays visually and behaviorally
/// consistent.
class RequestCard extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final List<Widget> extras;
  final String secondaryLabel;
  final VoidCallback? onSecondary;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final bool busy;
  final Color? primaryColor;

  const RequestCard({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.extras = const [],
    required this.secondaryLabel,
    required this.onSecondary,
    required this.primaryLabel,
    required this.onPrimary,
    this.busy = false,
    this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.md),
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: AppSpace.md)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (extras.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            ...extras,
          ],
          const SizedBox(height: AppSpace.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onSecondary,
                  child: Text(secondaryLabel),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: ElevatedButton(
                  style: primaryColor != null
                      ? ElevatedButton.styleFrom(backgroundColor: primaryColor)
                      : null,
                  onPressed: busy ? null : onPrimary,
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(primaryLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
