import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/widgets/avatar.dart';

class PostUserHeader extends StatelessWidget {
  final String userId;
  final VoidCallback? onTap;
  final Widget? trailing;

  const PostUserHeader({
    super.key,
    required this.userId,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('profiles')
          .stream(primaryKey: ['id'])
          .eq('id', userId)
          .limit(1),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isEmpty) {
          return const SizedBox(height: 48);
        }

        final user = snap.data!.first;
        final name = user['name'] ?? 'User';
        final photoUrl = user['photo_url'];

        return InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                AppAvatar(
                  photoUrl: photoUrl,
                  name: name,
                  radius: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        );
      },
    );
  }
}
