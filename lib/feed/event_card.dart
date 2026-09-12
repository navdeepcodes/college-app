import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'comments_screen.dart';

class EventCard extends StatelessWidget {
  final String eventId;
  final Map<String, dynamic> data;
  final dynamic storageService;

  const EventCard({
    super.key,
    required this.eventId,
    required this.data,
    required this.storageService,
  });

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final isOwner = data['createdBy'] == uid;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ================= IMAGE =================
          if (data['bannerPath'] != null)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                storageService.getPublicEventUrl(data['bannerPath']),
                fit: BoxFit.cover,
                loadingBuilder: (c, child, p) =>
                p == null ? child : const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image, size: 40),
                ),
              ),
            ),

          // ================= CONTENT =================
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['title'] ?? '',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  data['description'] ?? '',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 14),

                Row(
                  children: [
                    _ActionButton(
                      icon: Icons.comment_outlined,
                      label: 'Comment',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                CommentsScreen(postId: eventId),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 16),
                    _ActionButton(
                      icon: Icons.share_outlined,
                      label: 'Share',
                      onTap: () => _share(context),
                    ),
                    const Spacer(),
                    if (isOwner)
                      _DangerButton(
                        icon: Icons.delete_outline,
                        onTap: () => _delete(context),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================= DELETE =================

  Future<void> _delete(BuildContext context) async {
    try {
      await FirebaseFirestore.instance
          .collection('events')
          .doc(eventId)
          .delete();

      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Event deleted')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permission denied. Cannot delete event.'),
        ),
      );
    }
  }

  // ================= SHARE =================

  void _share(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Share coming soon')),
    );
  }
}

// =====================================================

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.white70),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              )),
        ],
      ),
    );
  }
}

class _DangerButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _DangerButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: Colors.redAccent),
      ),
    );
  }
}