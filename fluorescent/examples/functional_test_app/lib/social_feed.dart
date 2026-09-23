import 'package:flutter/material.dart';
import 'backend/backend_service.dart';

class SocialFeedScreen extends StatefulWidget {
  const SocialFeedScreen({super.key});

  @override
  State<SocialFeedScreen> createState() => _SocialFeedScreenState();
}

class _SocialFeedScreenState extends State<SocialFeedScreen> {
  final BackendService _backend = BackendService();

  @override
  void initState() {
    super.initState();
    if (_backend.posts.isEmpty) {
      _backend.posts = [
        {
          'user': 'Driver_X',
          'avatar': 'D',
          'time': '2 mins ago',
          'content': 'Just passed the speed trap on I-280, be careful out there!',
          'likes': '12',
        },
        {
          'user': 'SpeedRacer',
          'avatar': 'S',
          'time': '15 mins ago',
          'content': 'Rally starting at the Golden Gate Bridge in 1 hour. Who is in?',
          'likes': '45',
        },
        {
          'user': 'NightRider',
          'avatar': 'N',
          'time': '1 hr ago',
          'content': 'Beautiful sunset drive along the coast today.',
          'likes': '89',
        },
        {
          'user': 'GearHead',
          'avatar': 'G',
          'time': '3 hrs ago',
          'content': 'Looking for a mechanic recommendation in SF for a tune-up.',
          'likes': '4',
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
        title: const Text('Social Feed'),
      ),
      body: ListView.builder(
        itemCount: _backend.posts.length,
        itemBuilder: (context, index) {
          final post = _backend.posts[index];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        child: Text(post['avatar']!),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              post['user']!,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              post['time']!,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.more_vert),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    post['content']!,
                    style: const TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.thumb_up_alt_outlined, size: 20, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(post['likes']!, style: const TextStyle(color: Colors.grey)),
                      const SizedBox(width: 16),
                      const Icon(Icons.comment_outlined, size: 20, color: Colors.grey),
                      const SizedBox(width: 4),
                      const Text('Reply', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _backend.sendPost('Driver_X', 'Testing live updates!');
          setState(() {});
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
