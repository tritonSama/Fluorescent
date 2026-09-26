import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flame/components.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:typed_data';

class WebRTCViewport extends PositionComponent {
  final String signalingUrl;

  RTCVideoRenderer? _renderer;
  WebSocketChannel? _channel;
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  bool _isConnected = false;

  WebRTCViewport({
    required this.signalingUrl,
    super.position,
    super.size,
  });

  @override
  Future<void> onLoad() async {
    super.onLoad();
    _renderer = RTCVideoRenderer();
    await _renderer!.initialize();

    _connectSignaling();

    // We mount the RTCVideoRenderer using Flame's WidgetComponent or equivalent.
    // For simplicity, we assume the user will wrap this inside a Widget.
  }

  void _connectSignaling() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(signalingUrl));
      _channel!.stream.listen((message) {
        _handleSignalingMessage(message);
      });
      _setupPeerConnection();
    } catch (e) {
      print('Failed to connect to signaling server: $e');
    }
  }

  Future<void> _setupPeerConnection() async {
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    };

    _peerConnection = await createPeerConnection(config);

    _peerConnection!.onTrack = (RTCTrackEvent event) {
      if (event.track.kind == 'video') {
        _renderer!.srcObject = event.streams[0];
      }
    };

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      _channel?.sink.add(jsonEncode({
        'type': 'ice',
        'ice': candidate.toMap(),
      }));
    };

    _peerConnection!.onDataChannel = (RTCDataChannel channel) {
       _dataChannel = channel;
    };

    // We create the data channel if we are the caller (for input)
    RTCDataChannelInit dataChannelDict = RTCDataChannelInit()
      ..ordered = false
      ..maxRetransmits = 0;
    _dataChannel = await _peerConnection!.createDataChannel('input_controls', dataChannelDict);

    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    _channel?.sink.add(jsonEncode({
      'type': 'offer',
      'sdp': offer.toMap(),
    }));
  }

  void _handleSignalingMessage(dynamic message) async {
    final Map<String, dynamic> data = jsonDecode(message);
    if (data['type'] == 'answer') {
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(data['sdp']['sdp'], data['sdp']['type'])
      );
      _isConnected = true;
    } else if (data['type'] == 'ice') {
      await _peerConnection!.addCandidate(
        RTCIceCandidate(
          data['ice']['candidate'],
          data['ice']['sdpMid'],
          data['ice']['sdpMLineIndex'],
        )
      );
    }
  }

  void sendInput(List<int> payload) {
    if (_isConnected && _dataChannel != null) {
      _dataChannel!.send(RTCDataChannelMessage.fromBinary(Uint8List.fromList(payload)));
    }
  }

  // Returns a Flutter Widget that actually renders the video
  Widget buildWidget() {
    if (_renderer == null) return Container();
    return RTCVideoView(_renderer!);
  }

  @override
  void onRemove() {
    _renderer?.dispose();
    _channel?.sink.close();
    _peerConnection?.close();
    super.onRemove();
  }
}
