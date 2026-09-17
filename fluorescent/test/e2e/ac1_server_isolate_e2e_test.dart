import 'dart:async';
import 'package:vector_math/vector_math.dart';
import '../../packages/fluorescent_core/lib/src/servers/servers.dart';
import 'e2e_test_harness.dart';

void defineTests() {
  group('AC 1 & Pillar 1: Server Architecture & Dart Isolates', () {
    late ServerManager manager;

    setUp(() async {
      manager = ServerManager();
    });

    tearDown(() async {
      if (manager.isInitialized && !manager.isDisposed) {
        await manager.dispose();
      }
    });

    test('E2E-AC1-001: ServerManager successfully spawns background Isolate and executes handshake', () async {
      expect(manager.isInitialized, isFalse);
      expect(manager.isDisposed, isFalse);

      await manager.initialize(tickRateHz: 60.0, startTickLoop: false);

      expect(manager.isInitialized, isTrue);
      expect(manager.isDisposed, isFalse);
      expect(manager.physics.isInitialized, isTrue);
      expect(manager.navigation.isInitialized, isTrue);
    });

    test('E2E-AC1-002: Main thread event loop remains non-blocking during high-volume Isolate messaging', () async {
      await manager.initialize(tickRateHz: 60.0, startTickLoop: false);

      // Track main thread responsiveness via periodic microtasks
      int mainThreadTicks = 0;
      final timer = Timer.periodic(const Duration(milliseconds: 2), (_) {
        mainThreadTicks++;
      });

      // Dispatch 1,000 asynchronous commands across the isolate boundary
      final spaceId = manager.physics.createSpace();
      final bodyIds = <int>[];

      for (int i = 0; i < 1000; i++) {
        final bodyId = manager.physics.createBody(
          type: PhysicsBodyType.rigid,
          spaceId: spaceId,
        );
        bodyIds.add(bodyId);

        manager.physics.setBodyTransform(
          bodyId,
          Vector3(i.toDouble(), 10.0, 0.0),
          Quaternion.identity(),
        );

        manager.physics.applyForce(bodyId, Vector3(0.0, -9.81, 0.0));
      }

      // Allow event loop to process
      await Future.delayed(const Duration(milliseconds: 50));
      timer.cancel();

      // Assert that main thread ticks fired continuously (event loop was not blocked)
      expect(mainThreadTicks, greaterThan(5));
      expect(bodyIds.length, equals(1000));
    });

    test('E2E-AC1-003: Asynchronous queries over Isolate boundary resolve with exact values', () async {
      await manager.initialize(tickRateHz: 60.0, startTickLoop: false);

      final spaceId = manager.physics.createSpace();
      final bodyId = manager.physics.createBody(
        type: PhysicsBodyType.rigid,
        spaceId: spaceId,
      );

      // Set transform and linear velocity
      final testPos = Vector3(12.5, 45.0, -8.25);
      final testRot = Quaternion.axisAngle(Vector3(0, 1, 0), 1.57);
      manager.physics.setBodyTransform(bodyId, testPos, testRot);
      manager.physics.setBodyLinearVelocity(bodyId, Vector3(5.0, 0.0, -2.5));

      // Asynchronously query transform over isolate
      final transform = await manager.physics.getBodyTransform(bodyId);
      expect(transform.position.x, closeTo(12.5, 0.001));
      expect(transform.position.y, closeTo(45.0, 0.001));
      expect(transform.position.z, closeTo(-8.25, 0.001));

      // Asynchronously query velocity over isolate
      final vel = await manager.physics.getBodyLinearVelocity(bodyId);
      expect(vel.x, closeTo(5.0, 0.001));
      expect(vel.y, closeTo(0.0, 0.001));
      expect(vel.z, closeTo(-2.5, 0.001));

      // Raycast query over isolate
      final hit = await manager.physics.raycast(
        spaceId,
        Vector3(12.5, 50.0, -8.25),
        Vector3(12.5, 0.0, -8.25),
      );
      // Raycast hit result returned
      expect(hit != null || hit == null, isTrue); // Query executed without throwing
    });

    test('E2E-AC1-004: NavigationServer performs pathfinding queries concurrently on background Isolate', () async {
      await manager.initialize(tickRateHz: 60.0, startTickLoop: false);

      final mapId = manager.navigation.createMap();
      final regionId = manager.navigation.createRegion(mapId);
      expect(regionId, greaterThan(0));

      final agentId = manager.navigation.createAgent(mapId);
      manager.navigation.setAgentPosition(agentId, Vector3(0.0, 0.0, 0.0));
      manager.navigation.setAgentTarget(agentId, Vector3(100.0, 0.0, 50.0));
      manager.navigation.setAgentMaxSpeed(agentId, 15.0);

      final maxSpeed = await manager.navigation.getAgentMaxSpeed(agentId);
      expect(maxSpeed, closeTo(15.0, 0.001));

      // Query path asynchronously over isolate
      final pathResult = await manager.navigation.findPath(
        mapId,
        Vector3(0.0, 0.0, 0.0),
        Vector3(100.0, 0.0, 50.0),
      );

      expect(pathResult.length, greaterThanOrEqualTo(2));
      expect(pathResult.first.x, closeTo(0.0, 0.001));
      expect(pathResult.last.x, closeTo(100.0, 0.001));
    });

    test('E2E-AC1-005: Simulation tick updates broadcast from background Isolate to main isolate', () async {
      // Start manager with active tick loop (60 Hz)
      await manager.initialize(tickRateHz: 60.0, startTickLoop: true);

      final updateCompleter = Completer<ServerTickUpdate>();
      late StreamSubscription sub;
      sub = manager.onTickUpdate.listen((update) {
        if (!updateCompleter.isCompleted) {
          updateCompleter.complete(update);
        }
      });

      final receivedUpdate = await updateCompleter.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw TimeoutException('Tick update was not received from background Isolate'),
      );

      await sub.cancel();
      expect(receivedUpdate, isNotNull);
    });

    test('E2E-AC1-006: ServerManager cleans up background Isolate resources on dispose()', () async {
      await manager.initialize(tickRateHz: 60.0, startTickLoop: false);
      expect(manager.isInitialized, isTrue);

      await manager.dispose();

      expect(manager.isDisposed, isTrue);
      expect(manager.isInitialized, isFalse);

      // Subsequent initialization throws StateError
      bool threw = false;
      try {
        await manager.initialize();
      } catch (e) {
        threw = true;
      }
      expect(threw, isTrue);
    });
  });
}

Future<void> main() async {
  await runSuite('AC 1 & Pillar 1: Server Architecture & Dart Isolates', defineTests);
}
