import 'dart:async';
import 'package:vector_math/vector_math.dart';
import '../servers/server.dart';

abstract class AudioServer extends Server {
  int createSource({int? id});
  void destroySource(int sourceId);

  void setSourcePosition(int sourceId, Vector3 position);
  void setSourceVolume(int sourceId, double volume);
  void setSourcePitch(int sourceId, double pitch);
  void setSourceMinMaxDistance(int sourceId, double minDistance, double maxDistance);

  void play(int sourceId, String resourceId, {bool loop = false});
  void stop(int sourceId);
  void pause(int sourceId);
  void resume(int sourceId);

  void setListenerPosition(Vector3 position);
  void setListenerOrientation(Vector3 forward, Vector3 up);
}

class LocalAudioServer extends AudioServer {
  bool _isInitialized = false;
  int _nextHandleId = 0;

  final Map<int, _AudioSourceData> _sources = {};

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize() async {
    _isInitialized = true;
  }

  @override
  void step(double dt) {
    // Advanced audio mixing and spatialization would happen here.
  }

  @override
  Future<void> dispose() async {
    _isInitialized = false;
    _sources.clear();
  }

  int _reserveId(int? id) {
    final actualId = id ?? _nextHandleId++;
    if (actualId >= _nextHandleId) {
      _nextHandleId = actualId + 1;
    }
    return actualId;
  }

  @override
  int createSource({int? id}) {
    final actualId = _reserveId(id);
    _sources[actualId] = _AudioSourceData(actualId);
    return actualId;
  }

  @override
  void destroySource(int sourceId) {
    _sources.remove(sourceId);
  }

  @override
  void setSourcePosition(int sourceId, Vector3 position) {
    final source = _sources[sourceId];
    if (source != null) {
      source.position = position.clone();
    }
  }

  @override
  void setSourceVolume(int sourceId, double volume) {
    final source = _sources[sourceId];
    if (source != null) {
      source.volume = volume;
    }
  }

  @override
  void setSourcePitch(int sourceId, double pitch) {
    final source = _sources[sourceId];
    if (source != null) {
      source.pitch = pitch;
    }
  }

  @override
  void setSourceMinMaxDistance(int sourceId, double minDistance, double maxDistance) {
    final source = _sources[sourceId];
    if (source != null) {
      source.minDistance = minDistance;
      source.maxDistance = maxDistance;
    }
  }

  @override
  void play(int sourceId, String resourceId, {bool loop = false}) {
     final source = _sources[sourceId];
    if (source != null) {
      source.isPlaying = true;
      source.isPaused = false;
      source.resourceId = resourceId;
      source.isLooping = loop;
    }
  }

  @override
  void stop(int sourceId) {
    final source = _sources[sourceId];
    if (source != null) {
      source.isPlaying = false;
      source.isPaused = false;
    }
  }

  @override
  void pause(int sourceId) {
    final source = _sources[sourceId];
    if (source != null && source.isPlaying) {
      source.isPaused = true;
    }
  }

  @override
  void resume(int sourceId) {
     final source = _sources[sourceId];
    if (source != null && source.isPlaying && source.isPaused) {
      source.isPaused = false;
    }
  }

  @override
  void setListenerPosition(Vector3 position) {
  }

  @override
  void setListenerOrientation(Vector3 forward, Vector3 up) {
  }
}

class _AudioSourceData {
  final int id;
  Vector3 position = Vector3.zero();
  double volume = 1.0;
  double pitch = 1.0;
  double minDistance = 1.0;
  double maxDistance = 100.0;

  bool isPlaying = false;
  bool isPaused = false;
  bool isLooping = false;
  String? resourceId;

  _AudioSourceData(this.id);
}
