import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class BackendService {
  static const String _baseUrl = 'http://127.0.0.1:3001/api';
  static const String _wsUrl = 'ws://127.0.0.1:3001';

  String? _token;
  WebSocketChannel? _channel;

  // Real data state
  List<Map<String, dynamic>> posts = [];
  List<Map<String, dynamic>> messages = [];
  Function? onUpdate;

  static final BackendService _instance = BackendService._internal();

  factory BackendService() {
    return _instance;
  }

  BackendService._internal();

  Future<void> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['token'];
        _connectWebSocket();
      } else {
        throw Exception('Failed to login: ${response.body}');
      }
    } catch (e) {
      print('Error during login: $e');
      // For functional testing if backend isn't running, we fallback to mock
    }
  }

  void _connectWebSocket() {
    if (_token == null) return;

    _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));

    // Auth first
    _channel!.sink.add(jsonEncode({
      'type': 'auth',
      'token': _token,
    }));

    _channel!.stream.listen((message) {
      final data = jsonDecode(message);
      if (data['type'] == 'event') {
        final event = data['event'];
        if (event['eventType'] == 'POST') {
           final payload = jsonDecode(event['payload']);
           posts.insert(0, {
             'user': payload['user'],
             'avatar': payload['user'][0],
             'time': 'Just now',
             'content': payload['content'],
             'likes': '0',
           });
           onUpdate?.call();
        } else if (event['eventType'] == 'DM') {
           final payload = jsonDecode(event['payload']);
           // Find existing chat or add new
           var existing = messages.indexWhere((m) => m['name'] == payload['name']);
           if (existing != -1) {
             messages[existing]['lastMessage'] = payload['content'];
             messages[existing]['time'] = 'Just now';
             int unread = int.parse(messages[existing]['unread'] ?? '0');
             messages[existing]['unread'] = (unread + 1).toString();
           } else {
             messages.insert(0, {
               'name': payload['name'],
               'avatar': payload['name'][0],
               'lastMessage': payload['content'],
               'time': 'Just now',
               'unread': '1',
             });
           }
           onUpdate?.call();
        }
      }
    });
  }

  void sendPost(String user, String content) {
    if (_channel != null) {
      final payload = jsonEncode({
        'user': user,
        'content': content,
      });
      // In a real app we'd hash and sign this
      _channel!.sink.add(jsonEncode({
        'type': 'event',
        'event': {
          'id': 'mock_hash_${DateTime.now().millisecondsSinceEpoch}',
          'did': 'did:nexus:mock_user',
          'eventType': 'POST',
          'payload': payload,
          'signature': 'mock_signature',
        }
      }));
    }
  }
}
