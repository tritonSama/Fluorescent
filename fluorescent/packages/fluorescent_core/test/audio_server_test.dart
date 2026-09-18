import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:fluorescent_core/src/servers/servers.dart';

void main() {
  group('AudioServer Tests', () {
    late AudioServer audioServer;

    setUp(() async {
      audioServer = LocalAudioServer();
      await audioServer.initialize();
    });

    tearDown(() async {
      await audioServer.dispose();
    });

    test('creates and configures audio source', () {
      final sourceId = audioServer.createSource();
      expect(sourceId, isNotNull);

      audioServer.setSourcePosition(sourceId, Vector3(10, 0, 0));
      audioServer.setSourceVolume(sourceId, 0.5);
      audioServer.setSourcePitch(sourceId, 1.2);

      // In a real test, we would query the state to verify, but since LocalAudioServer
      // doesn't expose getters for these properties directly (as per the spec),
      // we're verifying that the methods execute without error.
    });

    test('plays, pauses, and stops audio source', () {
      final sourceId = audioServer.createSource();

      audioServer.play(sourceId, 'jump_sound', loop: true);
      audioServer.pause(sourceId);
      audioServer.resume(sourceId);
      audioServer.stop(sourceId);
      audioServer.destroySource(sourceId);
    });
  });
}
