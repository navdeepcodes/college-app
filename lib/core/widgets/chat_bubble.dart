import 'package:flutter/material.dart';
import '../app_colors.dart';

/// The message bubble shared by 1:1 chat and club chat, so both read as
/// the same product rather than two differently-styled screens that
/// happen to both show messages. (Anonymous chat keeps its own distinct
/// bubble — see college_anon_chat_screen.dart — that's a deliberate
/// identity difference, not an oversight.)
///
/// [showTail] marks the bubble closest to the *next* message from a
/// different sender (or the newest message overall) — it gets a tightened
/// corner on the speaker's side, the standard messaging-app cue that a
/// run of consecutive bubbles belongs to one person.
class ChatBubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final bool showTail;
  final Widget? footer;

  const ChatBubble({
    super.key,
    required this.text,
    required this.isMe,
    this.showTail = true,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isMe || !showTail ? 18 : 5),
      bottomRight: Radius.circular(isMe && showTail ? 5 : 18),
    );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: showTail ? 10 : 3),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: isMe
                    ? const LinearGradient(
                        colors: [AppColors.accent, AppColors.accentDeep],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isMe ? null : AppColors.surfaceRaised,
                borderRadius: radius,
                border: isMe ? null : Border.all(color: AppColors.border),
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: isMe ? Colors.white : AppColors.textPrimary,
                  fontSize: 15,
                  height: 1.3,
                ),
              ),
            ),
            if (footer != null) ...[
              const SizedBox(height: 3),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Renders a 1:1 message's delivery state as an icon instead of raw text
/// ("sent" / "delivered" / "seen"), the standard messaging-app convention.
class MessageStatusIcon extends StatelessWidget {
  final String status;

  const MessageStatusIcon({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    switch (status) {
      case 'seen':
        icon = Icons.done_all_rounded;
        color = AppColors.accentBright;
        break;
      case 'delivered':
        icon = Icons.done_all_rounded;
        color = AppColors.textMuted;
        break;
      default:
        icon = Icons.done_rounded;
        color = AppColors.textMuted;
    }
    return Icon(icon, size: 14, color: color);
  }
}
