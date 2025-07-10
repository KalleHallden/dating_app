// lib/widgets/match_list_item.dart
import 'package:flutter/material.dart';

class MatchListItem extends StatelessWidget {
  final String matchId;
  final String name;
  final int age;
  final String? profilePictureUrl;
  final bool isOnline;
  final DateTime? lastMessageAt;
  final VoidCallback onTap;

  const MatchListItem({
    Key? key,
    required this.matchId,
    required this.name,
    required this.age,
    this.profilePictureUrl,
    required this.isOnline,
    this.lastMessageAt,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.grey[300],
            backgroundImage: profilePictureUrl != null && profilePictureUrl!.isNotEmpty
                ? NetworkImage(profilePictureUrl!)
                : null,
            child: profilePictureUrl == null || profilePictureUrl!.isEmpty
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  )
                : null,
          ),
          // Online status indicator
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: isOnline ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
      title: Text(
        '$name, $age',
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
      subtitle: Text(
        _getLastMessageText(),
        style: TextStyle(
          color: Colors.grey[600],
          fontSize: 14,
        ),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios,
        size: 16,
        color: Colors.grey[400],
      ),
    );
  }

  String _getLastMessageText() {
    if (lastMessageAt == null) {
      return 'Start a conversation';
    }
    
    final now = DateTime.now();
    final difference = now.difference(lastMessageAt!);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}
