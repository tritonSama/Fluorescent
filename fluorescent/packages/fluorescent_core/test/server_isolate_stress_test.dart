import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:fluorescent_core/src/servers/servers.dart';

void main() {
  group('Adversarial ServerManager Isolate Stress Test', () {
    test('Rapid Isolate Start/Stop Cycles: 10 consecutive lifecycles without deadlocks or leaks', () async {
      const cycles = 10;
      final cycleWatch = Stopwatch()..start();

      for (int i = 0; i < cycles; i++) {
        final manager = ServerManager();
        expect(manager.isInitialized, isFalse);
        expect(manager.isDisposed, isFalse);

        await manager.initialize(startTickLoop: false);
        expect(manager.isInitialized, isTrue);
        expect(manager.isDisposed, isFalse);

        // Run mini workload on each cycle
        final physics = manager.physics;
        final spaceId = physics.createSpace();
        final bodyId = physics.createBody(type: PhysicsBodyType.rigid, spaceId: spaceId);
        physics.setBodyTransform(bodyId, Vector3(i.toDouble(), 0, 0), Quaternion.identity());

        final nav = manager.navigation;
        final mapId = nav.createMap();
        nav.setMapCellSize(mapId, 1.0);

        // Run 20 queries per cycle
        final queries = <Future<dynamic>>[];
        for (int q = 0; q < 20; q++) {
          queries.add(physics.getBodyTransform(bodyId));
          queries.add(nav.getMapCellSize(mapId));
        }
        final results = await Future.wait(queries);
        expect(results.length, equals(40));

        await manager.dispose();
        expect(manager.isDisposed, isTrue);
        expect(manager.isInitialized, isFalse);
        expect(manager.pendingQueryCount, equals(0));
      }
      cycleWatch.stop();

      // ignore: avoid_print
      print('ServerManager Lifecycle Stress: 10 full start/workload/stop cycles completed in ${cycleWatch.elapsedMilliseconds}ms');
    });

    test('Concurrent Message Flooding: 5,000 commands and queries across Isolate boundary', () async {
      final manager = ServerManager();
      await manager.initialize(startTickLoop: false);

      final physics = manager.physics;
      final nav = manager.navigation;

      final spaceId = physics.createSpace();
      physics.setGravity(spaceId, Vector3(0, -9.8, 0));

      final mapId = nav.createMap();
      nav.setMapCellSize(mapId, 0.5);

      // Create a pool of 50 bodies and 50 agents
      const entityPool = 50;
      final bodyIds = List<int>.generate(entityPool, (i) {
        final bId = physics.createBody(type: PhysicsBodyType.rigid, spaceId: spaceId);
        physics.setBodyTransform(bId, Vector3(i * 1.0, 10.0, 0.0), Quaternion.identity());
        return bId;
      });

      final agentIds = List<int>.generate(entityPool, (i) {
        final aId = nav.createAgent(mapId);
        nav.setAgentPosition(aId, Vector3(i * 1.0, 0.0, 0.0));
        nav.setAgentTarget(aId, Vector3(i * 1.0 + 10.0, 0.0, 0.0));
        return aId;
      });

      const totalCommands = 3000;
      const totalQueries = 2000;

      final floodWatch = Stopwatch()..start();

      // 1. Dispatch 3,000 asynchronous commands
      for (int i = 0; i < totalCommands; i++) {
        final targetBody = bodyIds[i % entityPool];
        final targetAgent = agentIds[i % entityPool];

        physics.setBodyLinearVelocity(targetBody, Vector3(0, (i % 10).toDouble(), 0));
        physics.applyForce(targetBody, Vector3(1.0, 0, 0));
        nav.setAgentPosition(targetAgent, Vector3(i * 0.1, 0, 0));
        if (i % 100 == 0) {
          manager.step(0.016);
        }
      }

      // 2. Interleave and fire 2,000 concurrent queries
      final queryFutures = <Future<dynamic>>[];
      for (int i = 0; i < totalQueries; i++) {
        final targetBody = bodyIds[i % entityPool];
        final targetAgent = agentIds[i % entityPool];

        switch (i % 4) {
          case 0:
            queryFutures.add(physics.getBodyTransform(targetBody));
            break;
          case 1:
            queryFutures.add(physics.getBodyLinearVelocity(targetBody));
            break;
          case 2:
            queryFutures.add(nav.getAgentPosition(targetAgent));
            break;
          case 3:
            queryFutures.add(nav.getMapCellSize(mapId));
            break;
        }
      }

      expect(manager.pendingQueryCount, greaterThan(0));

      // Await all 2,000 queries with strict timeout (zero deadlocks allowed)
      final results = await Future.wait(queryFutures).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException('Isolate query flood deadlocked or timed out after 20s!'),
      );

      floodWatch.stop();

      expect(results.length, equals(totalQueries));
      expect(manager.pendingQueryCount, equals(0));

      final totalMessages = totalCommands + totalQueries;
      final throughput = (totalMessages / (floodWatch.elapsedMicroseconds / 1000000.0)).round();

      // ignore: avoid_print
      print('ServerManager Flood Stress: Dispatched $totalCommands commands & $totalQueries queries '
          '($totalMessages total) in ${floodWatch.elapsedMilliseconds}ms ($throughput msgs/sec), '
          'Pending queries: ${manager.pendingQueryCount}');

      await manager.dispose();
      expect(manager.isDisposed, isTrue);
    });

    test('In-flight Query Cancellation on Immediate Disposal', () async {
      final manager = ServerManager();
      await manager.initialize(startTickLoop: false);

      final physics = manager.physics;
      final spaceId = physics.createSpace();
      final bodyId = physics.createBody(spaceId: spaceId);

      // Dispatch 200 queries without awaiting
      final futures = <Future<dynamic>>[];
      for (int i = 0; i < 200; i++) {
        futures.add(physics.getBodyTransform(bodyId));
      }

      // Immediately dispose ServerManager while queries are in-flight
      await manager.dispose();

      int errorCount = 0;
      int successCount = 0;
      for (final f in futures) {
        try {
          await f;
          successCount++;
        } catch (e) {
          if (e is StateError) {
            errorCount++;
          }
        }
      }

      // Every future must either have completed before dispose or cleanly errored with StateError
      expect(errorCount + successCount, equals(200));
      expect(manager.isDisposed, isTrue);
      expect(manager.pendingQueryCount, equals(0));

      // ignore: avoid_print
      print('In-flight Cancellation Stress: $successCount resolved before teardown, '
          '$errorCount cleanly aborted with StateError on immediate dispose');
    });
  });
}
