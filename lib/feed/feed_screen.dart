import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/storage_service.dart';
import '../services/presence_service.dart';
import '../notifications/notifications_screen.dart';
import '../chat/chats_list_screen.dart';
import '../moments/moments_screen.dart';
import '../profile/profile_screen.dart';
import '../feed/comments_screen.dart';
import 'post_user_header.dart';
import 'add_create_selector_sheet.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  int _selectedTab = 0;
  late final String _uid;
  String? _collegeId;

  late final StorageService _storage;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser!.uid;

    // ✅ CORRECT: no Supabase.instance here
    _storage = StorageService();

    _loadCollege();
  }

  Future<void> _loadCollege() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .get();

    if (!mounted) return;
    setState(() => _collegeId = doc.data()?['collegeId']);
  }

  @override
  Widget build(BuildContext context) {
    final onlineText = _collegeId == null
        ? null
        : PresenceService.format(
      PresenceService.estimateOnline(
        collegeBase: 5000,
        growthFactor: 1.0,
      ),
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            const Text(
              'Campus',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            if (onlineText != null) ...[
              const SizedBox(width: 8),
              _OnlineBadge(text: onlineText),
            ],
          ],
        ),
        actions: [
          if (_selectedTab == 0)
            _TopPillIcon(
              icon: Icons.add,
              onTap: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const AddCreateSelectorSheet(),
              ),
            ),
          _TopPillIcon(
            icon: Icons.chat_bubble_outline,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChatsListScreen()),
            ),
          ),
          _TopPillIcon(
            icon: Icons.notifications_none,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const NotificationsScreen(),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          _FeedToggle(
            selectedIndex: _selectedTab,
            onChanged: (i) => setState(() => _selectedTab = i),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _selectedTab == 0
                ? _MergedFeed(
              uid: _uid,
              storage: _storage,
            )
                : const MomentsScreen(),
          ),
        ],
      ),
    );
  }
}

/* =========================================================
   MERGED FEED
   ========================================================= */

class _MergedFeed extends StatelessWidget {
  final String uid;
  final StorageService storage;

  const _MergedFeed({
    required this.uid,
    required this.storage,
  });

  Future<void> _toggleLike(String postId) async {
    final postRef =
    FirebaseFirestore.instance.collection('posts').doc(postId);
    final likeRef = postRef.collection('likes').doc(uid);

    await FirebaseFirestore.instance.runTransaction((txn) async {
      final snap = await txn.get(likeRef);

      if (snap.exists) {
        txn.delete(likeRef);
        txn.update(postRef, {
          'likesCount': FieldValue.increment(-1),
        });
      } else {
        txn.set(likeRef, {
          'userId': uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        txn.update(postRef, {
          'likesCount': FieldValue.increment(1),
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('posts')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'No posts yet',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 140),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final postDoc = docs[i];
            final data = postDoc.data() as Map<String, dynamic>;

            final mediaPath = data['mediaPath'];
            final userId = data['userId'];
            if (mediaPath == null || userId == null) {
              return const SizedBox.shrink();
            }

            final imageUrl = storage.getPublicPostUrl(mediaPath);
            final likesCount = (data['likesCount'] ?? 0) as int;
            final commentsCount =
            (data['commentsCount'] ?? 0) as int;

            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('posts')
                  .doc(postDoc.id)
                  .collection('likes')
                  .doc(uid)
                  .snapshots(),
              builder: (context, likeSnap) {
                final isLiked =
                    likeSnap.hasData && likeSnap.data!.exists;

                return Card(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PostUserHeader(
                        userId: userId,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ProfileScreen(userId: userId),
                          ),
                        ),
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            14, 10, 14, 14),
                        child: Row(
                          children: [
                            _ActionButton(
                              icon: isLiked
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: isLiked
                                  ? Colors.redAccent
                                  : Colors.white70,
                              count: likesCount,
                              onTap: () =>
                                  _toggleLike(postDoc.id),
                            ),
                            const SizedBox(width: 18),
                            _ActionButton(
                              icon: Icons.chat_bubble_outline,
                              color: Colors.white70,
                              count: commentsCount,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CommentsScreen(
                                    postId: postDoc.id,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

/* =========================================================
   UI COMPONENTS (UNCHANGED)
   ========================================================= */

class _TopPillIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _TopPillIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, size: 20),
        ),
      ),
    );
  }
}

class _FeedToggle extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _FeedToggle({
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          _ToggleButton(
            label: 'Feed',
            selected: selectedIndex == 0,
            onTap: () => onChanged(0),
          ),
          _ToggleButton(
            label: 'Moments',
            selected: selectedIndex == 1,
            onTap: () => onChanged(1),
          ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.deepPurple : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.count,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Row(
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: 6),
          Text(count.toString()),
        ],
      ),
    );
  }
}

class _OnlineBadge extends StatelessWidget {
  final String text;
  const _OnlineBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withOpacity(0.2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '🔥 $text online',
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}