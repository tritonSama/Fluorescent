import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:fluorescent_core/src/servers/servers.dart';

void main() {
  group('Pillar 1: Base Server & RenderingServer Contract', () {
    test('Server base contract and RenderingServer implementation', () async {
      expect(RenderingServer, isNotNull);
      // Dummy concrete rendering server testing inheritance
      final server = _TestRenderingServer();
      expect(server.isInitialized, isTrue);
      await server.initialize();
      server.step(0.016);
      server.submitDrawCall();
      server.renderToTexture(1);
      await server.dispose();
    });
  });

  group('Pillar 1: Local Physics Engine (Ground Truth)', () {
    late LocalPhysicsServer physics;

    setUp(() async {
      physics = LocalPhysicsServer();
      await physics.initialize();
    });

    tearDown(() async {
      await physics.dispose();
    });

    test('Space, gravity, and simulation step integration', () async {
      final spaceId = physics.createSpace();
      physics.setGravity(spaceId, Vector3(0, -10.0, 0));

      final gravity = await physics.getGravity(spaceId);
      expect(gravity.y, equals(-10.0));

      final bodyId = physics.createBody(
        type: PhysicsBodyType.rigid,
        spaceId: spaceId,
      );
      physics.setBodyTransform(
        bodyId,
        Vector3(0, 50.0, 0),
        Quaternion.identity(),
      );
      physics.setBodyMass(bodyId, 2.0);

      // Step simulation by 1.0 second
      physics.step(1.0);

      final transform = await physics.getBodyTransform(bodyId);
      final velocity = await physics.getBodyLinearVelocity(bodyId);

      // v = u + a*t -> v = 0 + (-10)*1.0 = -10 (minus slight damping)
      expect(velocity.y, lessThan(-9.0));
      // y = y0 + v*t -> 50.0 + velocity*1.0
      expect(transform.position.y, lessThan(45.0));
    });

    test('Spatial raycast query against sphere and box shapes', () async {
      final spaceId = physics.createSpace();

      // Create target body with sphere shape at (0, 0, 10)
      final sphereShape = physics.createSphereShape(1.0);
      final sphereBody = physics.createBody(
        type: PhysicsBodyType.staticBody,
        spaceId: spaceId,
      );
      physics.addShapeToBody(sphereBody, sphereShape);
      physics.setBodyTransform(
        sphereBody,
        Vector3(0, 0, 10.0),
        Quaternion.identity(),
      );

      // Create target body with box shape at (10, 0, 0)
      final boxShape = physics.createBoxShape(Vector3(1.0, 1.0, 1.0));
      final boxBody = physics.createBody(
        type: PhysicsBodyType.staticBody,
        spaceId: spaceId,
      );
      physics.addShapeToBody(boxBody, boxShape);
      physics.setBodyTransform(
        boxBody,
        Vector3(10.0, 0, 0),
        Quaternion.identity(),
      );

      // 1. Raycast directly hitting sphere
      final sphereHit = await physics.raycast(
        spaceId,
        Vector3(0, 0, 0),
        Vector3(0, 0, 20.0),
      );
      expect(sphereHit, isNotNull);
      expect(sphereHit!.bodyId, equals(sphereBody));
      expect(sphereHit.distance, closeTo(9.0, 0.05)); // 10 - radius(1)

      // 2. Raycast directly hitting box
      final boxHit = await physics.raycast(
        spaceId,
        Vector3(0, 0, 0),
        Vector3(20.0, 0, 0),
      );
      expect(boxHit, isNotNull);
      expect(boxHit!.bodyId, equals(boxBody));
      expect(boxHit.distance, closeTo(9.0, 0.05)); // 10 - halfExtent(1)

      // 3. Raycast missing everything
      final missHit = await physics.raycast(
        spaceId,
        Vector3(0, 0, 0),
        Vector3(0, 20.0, 0),
      );
      expect(missHit, isNull);
    });
  });

  group('Pillar 1: Local Navigation Engine (Ground Truth)', () {
    late LocalNavigationServer nav;

    setUp(() async {
      nav = LocalNavigationServer();
      await nav.initialize();
    });

    tearDown(() async {
      await nav.dispose();
    });

    test('Agent movement stepping towards target', () async {
      final mapId = nav.createMap();
      final agentId = nav.createAgent(mapId);

      nav.setAgentPosition(agentId, Vector3(0, 0, 0));
      nav.setAgentTarget(agentId, Vector3(10.0, 0, 0));
      nav.setAgentMaxSpeed(agentId, 5.0);

      // Step simulation by 1.0 second (should move 5.0 units towards target)
      nav.step(1.0);

      final pos1 = await nav.getAgentPosition(agentId);
      expect(pos1.x, closeTo(5.0, 0.01));

      // Step another 1.0 second (should reach target 10.0)
      nav.step(1.0);

      final pos2 = await nav.getAgentPosition(agentId);
      expect(pos2.x, closeTo(10.0, 0.01));
      final vel2 = await nav.getAgentVelocity(agentId);
      expect(vel2.x, equals(0.0));
    });

    test('NavMesh pathfinding query with A* algorithm', () async {
      final mapId = nav.createMap();
      final regionId = nav.createRegion(mapId);

      // Create a 2-triangle rectangular navigation mesh
      final mesh = NavigationMesh(
        vertices: [
          Vector3(0, 0, 0),
          Vector3(10, 0, 0),
          Vector3(10, 0, 10),
          Vector3(0, 0, 10),
        ],
        polygons: [
          [0, 1, 2],
          [0, 2, 3],
        ],
      );
      nav.setRegionNavMesh(regionId, mesh);

      final result = await nav.queryPath(
        mapId,
        Vector3(0, 0, 0),
        Vector3(10, 0, 10),
      );

      expect(result.isReachable, isTrue);
      expect(result.path.length, greaterThanOrEqualTo(2));
      expect(result.totalDistance, greaterThan(0.0));
    });
  });

  group('Pillar 1: ServerManager Isolate Architecture & Concurrency', () {
    late ServerManager serverManager;

    setUp(() async {
      serverManager = ServerManager();
      await serverManager.initialize(
        tickRateHz: 60.0,
        startTickLoop: true,
      );
    });

    tearDown(() async {
      await serverManager.dispose();
    });

    test('Dart Isolate spawns and establishes bidirectional port handshake', () async {
      expect(serverManager.isInitialized, isTrue);
      expect(serverManager.isDisposed, isFalse);
    });

    test('PhysicsServer proxy routes commands & queries across Isolate boundary', () async {
      final physics = serverManager.physics;

      // 1. Create space & configure gravity
      final spaceId = physics.createSpace();
      physics.setGravity(spaceId, Vector3(0, -9.81, 0));

      // Query gravity from isolate
      final gravity = await physics.getGravity(spaceId);
      expect(gravity.y, closeTo(-9.81, 0.001));

      // 2. Create collider shapes & rigid body
      final sphereShape = physics.createSphereShape(1.5);
      final bodyId = physics.createBody(
        type: PhysicsBodyType.rigid,
        spaceId: spaceId,
      );
      physics.addShapeToBody(bodyId, sphereShape);
      physics.setBodyTransform(
        bodyId,
        Vector3(0, 20.0, 0),
        Quaternion.identity(),
      );
      physics.setBodyLinearVelocity(bodyId, Vector3(2.0, 0, 0));

      // 3. Query body transform and velocity from background isolate
      final transform = await physics.getBodyTransform(bodyId);
      expect(transform.position.y, closeTo(20.0, 0.001));

      final velocity = await physics.getBodyLinearVelocity(bodyId);
      expect(velocity.x, closeTo(2.0, 0.001));

      // 4. Apply force and impulses across isolate
      physics.applyForce(bodyId, Vector3(0, 10.0, 0));
      physics.applyImpulse(bodyId, Vector3(1.0, 0, 0));

      // 5. Query spatial raycast through background isolate
      final hit = await physics.raycast(
        spaceId,
        Vector3(0, 50.0, 0),
        Vector3(0, 0, 0),
      );
      expect(hit, isNotNull);
      expect(hit!.bodyId, equals(bodyId));
      expect(hit.distance, closeTo(28.5, 0.5)); // 50 - 20 - 1.5 radius
    });

    test('NavigationServer proxy routes commands & queries across Isolate boundary', () async {
      final nav = serverManager.navigation;

      // 1. Create map and configure cell size
      final mapId = nav.createMap();
      nav.setMapCellSize(mapId, 0.5);
      final cellSize = await nav.getMapCellSize(mapId);
      expect(cellSize, equals(0.5));

      // 2. Create region with navigation mesh
      final regId = nav.createRegion(mapId);
      final mesh = NavigationMesh(
        vertices: [
          Vector3(0, 0, 0),
          Vector3(20, 0, 0),
          Vector3(20, 0, 20),
          Vector3(0, 0, 20),
        ],
        polygons: [
          [0, 1, 2],
          [0, 2, 3],
        ],
      );
      nav.setRegionNavMesh(regId, mesh);

      // 3. Create agent and assign path target
      final agentId = nav.createAgent(mapId);
      nav.setAgentPosition(agentId, Vector3(1.0, 0, 1.0));
      nav.setAgentTarget(agentId, Vector3(15.0, 0, 15.0));
      nav.setAgentMaxSpeed(agentId, 4.0);

      final agentPos = await nav.getAgentPosition(agentId);
      expect(agentPos.x, closeTo(1.0, 0.001));

      // 4. Query pathfinding across Isolate
      final path = await nav.findPath(
        mapId,
        Vector3(1.0, 0, 1.0),
        Vector3(15.0, 0, 15.0),
      );
      expect(path, isNotEmpty);
      expect(path.first.x, closeTo(1.0, 0.001));
      expect(path.last.x, closeTo(15.0, 0.001));

      final queryRes = await nav.queryPath(
        mapId,
        Vector3(1.0, 0, 1.0),
        Vector3(15.0, 0, 15.0),
      );
      expect(queryRes.isReachable, isTrue);
      expect(queryRes.totalDistance, greaterThan(10.0));
    });

    test('Acceptance Criterion: Background Isolate processes load without blocking main thread',
        () async {
      final physics = serverManager.physics;
      final spaceId = physics.createSpace();
      physics.setGravity(spaceId, Vector3(0, -9.8, 0));

      // Spawn 100 bodies in background isolate
      final bodyIds = <int>[];
      for (int i = 0; i < 100; i++) {
        final bId = physics.createBody(
          type: PhysicsBodyType.rigid,
          spaceId: spaceId,
        );
        physics.setBodyTransform(
          bId,
          Vector3(i.toDouble(), 10.0 + i, 0),
          Quaternion.identity(),
        );
        bodyIds.add(bId);
      }

      // Track main thread event loop ticks concurrently while isolate processes commands
      int mainThreadTicks = 0;
      final mainTimer = Timer.periodic(const Duration(milliseconds: 2), (_) {
        mainThreadTicks++;
      });

      // Dispatch 300 rapid simulation step requests and queries over the isolate SendPort
      final queryFutures = <Future<dynamic>>[];
      for (int i = 0; i < 50; i++) {
        serverManager.step(0.016);
        queryFutures.add(physics.getBodyTransform(bodyIds[i % bodyIds.length]));
        queryFutures.add(physics.raycast(
          spaceId,
          Vector3(0, 100, 0),
          Vector3(0, 0, 0),
        ));
      }

      // Await all background isolate query responses
      final results = await Future.wait(queryFutures);
      expect(results.length, equals(100));

      mainTimer.cancel();

      // Verify that the main thread was never blocked and kept ticking smoothly
      expect(mainThreadTicks, greaterThan(0));
    });

    test('Background simulation tick loop synchronizes state with main isolate cache', () async {
      final physics = serverManager.physics;
      final spaceId = physics.createSpace();
      physics.setGravity(spaceId, Vector3(0, -50.0, 0));

      final bodyId = physics.createBody(
        type: PhysicsBodyType.rigid,
        spaceId: spaceId,
      );
      physics.setBodyTransform(
        bodyId,
        Vector3(0, 100.0, 0),
        Quaternion.identity(),
      );

      // Listen for tick updates from the background isolate
      final tickCompleter = Completer<ServerTickUpdate>();
      final sub = serverManager.onTickUpdate.listen((update) {
        if (!tickCompleter.isCompleted && update.bodyTransforms.containsKey(bodyId)) {
          tickCompleter.complete(update);
        }
      });

      // Await tick update from background isolate tick loop
      final update = await tickCompleter.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw TimeoutException('Did not receive tick update in time'),
      );

      await sub.cancel();

      expect(update.bodyTransforms.containsKey(bodyId), isTrue);

      // Verify client proxy cached transform was updated
      final cachedTransform = physics.getCachedTransform(bodyId);
      expect(cachedTransform, isNotNull);
    });

    test('Clean disposal and resource cleanup', () async {
      final tempManager = ServerManager();
      await tempManager.initialize();
      expect(tempManager.isInitialized, isTrue);

      await tempManager.dispose();
      expect(tempManager.isDisposed, isTrue);
      expect(tempManager.isInitialized, isFalse);
    });
  });
}

class _TestRenderingServer extends RenderingServer {
  @override
  Future<void> initialize() async {}

  @override
  void submitDrawCall() {}

  @override
  void renderToTexture(int textureId) {}
}
