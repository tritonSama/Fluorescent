import 'package:flutter/material.dart';
import 'backend/backend_service.dart';

class DMsScreen extends StatefulWidget {
  const DMsScreen({super.key});

  @override
  State<DMsScreen> createState() => _DMsScreenState();
}

class _DMsScreenState extends State<DMsScreen> {
  final BackendService _backend = BackendService();

  @override
  void initState() {
    super.initState();
    if (_backend.messages.isEmpty) {
      _backend.messages = [
        {
          'name': 'SF Rally Club (Group)',
          'avatar': 'SF',
          'lastMessage': 'Are we still meeting at 8?',
          'time': '10:45 AM',
          'unread': '3',
        },
        {
          'name': 'Driver_X',
          'avatar': 'D',
          'lastMessage': 'Thanks for the heads up on the speed trap.',
          'time': '9:30 AM',
          'unread': '0',
        },
        {
          'name': 'NightRider',
          'avatar': 'N',
          'lastMessage': 'See you at the coast!',
          'time': 'Yesterday',
          'unread': '0',
        },
        {
          'name': 'Mechanics Group',
          'avatar': 'M',
          'lastMessage': 'GearHead: Looking for a mechanic...',
          'time': 'Yesterday',
          'unread': '1',
        },
      ];
    }
    _backend.onUpdate = () {
      if (mounted) setState(() {});
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
      ),
      body: ListView.separated(
        itemCount: _backend.messages.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final chat = _backend.messages[index];
          final hasUnread = int.parse(chat['unread']!) > 0;
          return ListTile(
            leading: CircleAvatar(
              child: Text(chat['avatar']!),
            ),
            title: Text(
              chat['name']!,
              style: TextStyle(
                fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: Text(
              chat['lastMessage']!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
                color: hasUnread ? Colors.black87 : Colors.grey[600],
              ),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  chat['time']!,
                  style: TextStyle(
                    color: hasUnread ? Theme.of(context).colorScheme.primary : Colors.grey,
                    fontSize: 12,
                  ),
                ),
                if (hasUnread)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      chat['unread']!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            onTap: () {
              // Navigate to specific chat
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Action for creating a new message
        },
        child: const Icon(Icons.message),
      ),
    );
  }
}
