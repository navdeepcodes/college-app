/// A short "2h ago" / "Just now" label. Used by notifications, which
/// previously showed no timestamp at all despite having created_at
/// available on every row.
String relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 45) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
  return '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')}/${time.year}';
}
