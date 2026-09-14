import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../spacing.dart';

/// A consistent "nothing here yet" / "something went wrong" treatment,
/// replacing the app's many one-off `Center(child: Text('No X yet'))`
/// calls. Always answers: what's happening, why, and (when there's
/// something the user can do) what next.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isError;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.isError = false,
  });

  const EmptyState.error({
    super.key,
    this.title = "Something went wrong",
    this.message = "Check your connection and try again.",
    this.actionLabel = "Retry",
    required VoidCallback this.onAction,
  })  : icon = Icons.wifi_off_rounded,
        isError = true;

  @override
  Widget build(BuildContext context) {
    final tint = isError ? AppColors.danger : AppColors.textMuted;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxxl, vertical: AppSpace.huge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (isError ? AppColors.dangerBg : AppColors.surfaceSunken),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, size: 28, color: tint),
            ),
            const SizedBox(height: AppSpace.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpace.xl),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
