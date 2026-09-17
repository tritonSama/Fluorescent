import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluorescent_ecs/fluorescent_ecs.dart';

void main() {
  group('Adversarial ECS Stress Test: Scale, Churn & Memory Invariants', () {
    test('Scale Stress: 25,000+ entities with contiguous 16-float transform storage', () {
      const entityCount = 25000;
      final world = EcsWorld(initialCapacity: 1024, initialSparseCapacity: 1024);

      final spawnWatch = Stopwatch()..start();
      for (int i = 0; i < entityCount; i++) {
        final entity = world.createEntity();
        world.transforms.set(
          entity,
          x: i * 2.0,
          y: i * 3.0,
          z: i * 4.0,
          qx: 0.0,
          qy: 0.0,
          qz: 0.0,
          qw: 1.0,
          sx: 1.0,
          sy: 1.0,
          sz: 1.0,
        );
      }
      spawnWatch.stop();

      // Assert scale invariants
      expect(world.entityCount, equals(entityCount));
      expect(world.transforms.count, equals(entityCount));

      // Memory footprint assertion: 25,000 entities * 16 floats * 4 bytes = 1.6 MB data buffer
      final bufferBytes = world.transforms.data.lengthInBytes;
      expect(bufferBytes, lessThan(4 * 1024 * 1024)); // Less than 4 MB
      expect(world.transforms.capacity, greaterThanOrEqualTo(entityCount));

      // Assert data accuracy at scale
      expect(world.transforms.getX(const Entity(0)), equals(0.0));
      expect(world.transforms.getY(const Entity(0)), equals(0.0));
      expect(world.transforms.getZ(const Entity(0)), equals(0.0));

      final mid = entityCount ~/ 2;
      expect(world.transforms.getX(Entity(mid)), equals(mid * 2.0));
      expect(world.transforms.getY(Entity(mid)), equals(mid * 3.0));
      expect(world.transforms.getZ(Entity(mid)), equals(mid * 4.0));

      final last = entityCount - 1;
      expect(world.transforms.getX(Entity(last)), equals(last * 2.0));
      expect(world.transforms.getY(Entity(last)), equals(last * 3.0));
      expect(world.transforms.getZ(Entity(last)), equals(last * 4.0));

      // Throughput verification: 60 frames of simulation updates
      final frameWatch = Stopwatch()..start();
      const frames = 60;
      final rawData = world.transforms.data;
      final stride = world.transforms.stride;
      final totalFloats = world.transforms.count * stride;

      for (int f = 0; f < frames; f++) {
        for (int offset = 0; offset < totalFloats; offset += stride) {
          rawData[offset + TransformOffsets.y] += 1.0;
        }
      }
      frameWatch.stop();

      // Verify that after 60 frames, y has increased by 60.0 exactly
      expect(world.transforms.getY(const Entity(0)), equals(60.0));
      expect(world.transforms.getY(Entity(mid)), equals(mid * 3.0 + 60.0));
      expect(world.transforms.getY(Entity(last)), equals(last * 3.0 + 60.0));

      final totalUpdates = entityCount * frames;
      final updatesPerSec = (totalUpdates / (frameWatch.elapsedMicroseconds / 1000000.0)).round();

      // Output throughput diagnostic
      // ignore: avoid_print
      print('ECS 25k Benchmark: Spawn 25k in ${spawnWatch.elapsedMilliseconds}ms, '
          '60 frames (1.5M updates) in ${frameWatch.elapsedMilliseconds}ms ($updatesPerSec updates/sec), '
          'Memory: ${(bufferBytes / 1024).toStringAsFixed(1)} KB');
    });

    test('Massive Churn Stress: 30,000 entities with interleaved kills, swaps & ID recycling', () {
      const initialCount = 30000;
      final world = EcsWorld(initialCapacity: 512, initialSparseCapacity: 512);

      // 1. Initial burst spawn
      final entities = <Entity>[];
      for (int i = 0; i < initialCount; i++) {
        final e = world.createEntity();
        world.transforms.set(e, x: i.toDouble(), y: (i * 10).toDouble(), z: 0.0);
        entities.add(e);
      }
      expect(world.entityCount, equals(initialCount));

      // 2. Churn Phase A: Kill half the entities (all even indices)
      final killWatch = Stopwatch()..start();
      for (int i = 0; i < initialCount; i += 2) {
        final killed = world.destroyEntity(entities[i]);
        expect(killed, isTrue);
      }
      killWatch.stop();

      expect(world.entityCount, equals(initialCount ~/ 2));
      expect(world.transforms.count, equals(initialCount ~/ 2));

      // Assert surviving odd entities retained correct coordinates despite thousands of swap-and-pop ops!
      for (int i = 1; i < initialCount; i += 200) {
        expect(world.isAlive(entities[i]), isTrue);
        expect(world.transforms.has(entities[i]), isTrue);
        expect(world.transforms.getX(entities[i]), equals(i.toDouble()));
        expect(world.transforms.getY(entities[i]), equals((i * 10).toDouble()));
      }

      // Assert killed even entities are dead and removed from transforms
      for (int i = 0; i < initialCount; i += 200) {
        expect(world.isAlive(entities[i]), isFalse);
        expect(world.transforms.has(entities[i]), isFalse);
        expect(world.transforms.getOffset(entities[i]), equals(-1));
      }

      // 3. Churn Phase B: Re-spawn 10,000 entities from recycled pool
      final recycleWatch = Stopwatch()..start();
      final recycled = <Entity>[];
      for (int i = 0; i < 10000; i++) {
        final re = world.createEntity();
        expect(re.id, lessThan(initialCount)); // Must be recycled
        world.transforms.set(re, x: 999.0, y: 888.0, z: 777.0);
        recycled.add(re);
      }
      recycleWatch.stop();

      expect(world.entityCount, equals(25000));
      expect(world.transforms.count, equals(25000));

      // 4. Churn Phase C: Multi-generation churning loop (10 waves of 2,000 kills & respawns)
      final churnLoopWatch = Stopwatch()..start();
      for (int wave = 0; wave < 10; wave++) {
        // Kill 2,000 recycled entities
        for (int k = 0; k < 2000; k++) {
          final ok = world.destroyEntity(recycled[k]);
          expect(ok, isTrue);
        }
        expect(world.entityCount, equals(23000));

        // Re-spawn 2,000 entities
        for (int s = 0; s < 2000; s++) {
          final ne = world.createEntity();
          world.transforms.set(ne, x: wave.toDouble(), y: s.toDouble(), z: 1.0);
          recycled[s] = ne;
        }
        expect(world.entityCount, equals(25000));
      }
      churnLoopWatch.stop();

      // ignore: avoid_print
      print('ECS Churn Stress: 15k kills in ${killWatch.elapsedMilliseconds}ms, '
          '10k recycled in ${recycleWatch.elapsedMilliseconds}ms, '
          '10 churn waves (40k ops) in ${churnLoopWatch.elapsedMilliseconds}ms');
    });

    test('Boundary Stress: SparseSet expansion to 50,000 with zero RangeError or OutOfMemoryError', () {
      final storage = TransformStorage(initialCapacity: 16, initialSparseCapacity: 16);

      // Adversarially allocate at sparse non-contiguous extreme IDs: 0, 10, 100, 1000, 10000, 49999
      const extremeIds = [0, 1, 15, 16, 63, 64, 255, 256, 1024, 8192, 20000, 35000, 49999];
      for (final id in extremeIds) {
        final e = Entity(id);
        final offset = storage.set(e, x: id * 1.0, y: id * 2.0, z: id * 3.0);
        expect(offset, greaterThanOrEqualTo(0));
        expect(storage.has(e), isTrue);
        expect(storage.getX(e), equals(id * 1.0));
      }

      expect(storage.count, equals(extremeIds.length));
      expect(storage.sparse.length, greaterThanOrEqualTo(50000));

      // Remove in reverse order
      for (final id in extremeIds.reversed) {
        final ok = storage.remove(Entity(id));
        expect(ok, isTrue);
        expect(storage.has(Entity(id)), isFalse);
      }
      expect(storage.count, equals(0));
      expect(storage.isEmpty, isTrue);

      // Verify clear completely resets state
      storage.clear();
      expect(storage.count, equals(0));
    });

    test('World Clear & Full Lifecycle Reset under Heavy Load', () {
      final world = EcsWorld(initialCapacity: 100, initialSparseCapacity: 100);

      // Populate 10,000 entities
      for (int i = 0; i < 10000; i++) {
        final e = world.createEntity();
        world.transforms.set(e, x: 1.0, y: 2.0, z: 3.0);
      }
      expect(world.entityCount, equals(10000));
      expect(world.transforms.count, equals(10000));

      // Clear world
      world.clear();
      expect(world.entityCount, equals(0));
      expect(world.isEmpty, isTrue);
      expect(world.transforms.count, equals(0));
      expect(world.transforms.isEmpty, isTrue);

      // Re-populate from scratch - entity IDs must restart from 0
      final e0 = world.createEntity();
      expect(e0.id, equals(0));
      world.transforms.set(e0, x: 100.0, y: 200.0, z: 300.0);
      expect(world.transforms.getX(e0), equals(100.0));
      expect(world.entityCount, equals(1));
    });
  });
}
