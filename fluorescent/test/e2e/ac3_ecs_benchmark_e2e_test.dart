import '../../packages/fluorescent_ecs/lib/fluorescent_ecs.dart';
import 'e2e_test_harness.dart';

void defineTests() {
  group('AC 3 & Pillar 5: Contiguous TypedData ECS & 10,000 Entity Benchmark', () {
    test('E2E-AC3-001: Spawns and iterates over 10,000 entities using TypedData without memory errors', () {
      final world = EcsWorld(initialCapacity: 1024, initialSparseCapacity: 1024);

      // --- Phase 1: Spawn 10,000 Entities with 16-float Transforms ---
      final spawnWatch = Stopwatch()..start();
      final List<Entity> entities = List<Entity>.generate(10000, (i) {
        final entity = world.createEntity();
        world.transforms.set(
          entity,
          x: i * 1.0,
          y: 0.0,
          z: 0.0,
          sx: 1.0,
          sy: 1.0,
          sz: 1.0,
        );
        return entity;
      }, growable: false);
      spawnWatch.stop();

      // Verify entity counts and contiguous storage capacity
      expect(world.entityCount, equals(10000));
      expect(world.transforms.count, equals(10000));

      // Memory footprint assertion: 10,000 entities x 16 floats x 4 bytes = ~640 KB buffer.
      // Asserts contiguous memory is strictly bounded (< 2 MB).
      expect(world.transforms.data.lengthInBytes, lessThan(2 * 1024 * 1024));

      // --- Phase 2: 60 Simulation Frames Iteration (600,000 component updates) ---
      final simWatch = Stopwatch()..start();
      for (int frame = 0; frame < 60; frame++) {
        world.transforms.forEach((entity, data, offset) {
          data[offset + TransformOffsets.y] += 0.5; // Translate Y by 0.5 per frame
        });
      }
      simWatch.stop();

      // Numerical accuracy assertions after 60 frames (expected Y = 60 * 0.5 = 30.0)
      final sampleIndices = [0, 100, 2500, 5000, 7500, 9999];
      for (final idx in sampleIndices) {
        final entity = entities[idx];
        final x = world.transforms.getX(entity);
        final y = world.transforms.getY(entity);
        final z = world.transforms.getZ(entity);
        final sx = world.transforms.getSx(entity);

        expect(x, closeTo(idx * 1.0, 0.001));
        expect(y, closeTo(30.0, 0.001));
        expect(z, closeTo(0.0, 0.001));
        expect(sx, closeTo(1.0, 0.001));
      }

      // Performance assertion: 600,000 iterations complete in under 500 ms
      expect(simWatch.elapsedMilliseconds, lessThan(500));
    });

    test('E2E-AC3-002: Entity destruction and ID recycling maintain memory safety and array packing', () {
      final world = EcsWorld(initialCapacity: 1024, initialSparseCapacity: 1024);
      final entities = <Entity>[];

      for (int i = 0; i < 5000; i++) {
        final entity = world.createEntity();
        world.transforms.set(entity, x: i * 2.0, y: 1.0, z: 0.0);
        entities.add(entity);
      }

      expect(world.entityCount, equals(5000));
      expect(world.transforms.count, equals(5000));

      // Destroy 2,000 entities (even indices)
      for (int i = 0; i < 2000; i++) {
        final destroyed = world.destroyEntity(entities[i * 2]);
        expect(destroyed, isTrue);
      }

      expect(world.entityCount, equals(3000));
      expect(world.transforms.count, equals(3000));

      // Spawn 1,000 new entities to trigger ID recycling
      final recycledEntities = <Entity>[];
      for (int i = 0; i < 1000; i++) {
        final entity = world.createEntity();
        world.transforms.set(entity, x: 999.0, y: 999.0, z: 999.0);
        recycledEntities.add(entity);
      }

      expect(world.entityCount, equals(4000));
      expect(world.transforms.count, equals(4000));

      // Iterate over packed arrays without OutOfMemory or RangeError
      int count = 0;
      world.transforms.forEach((entity, data, offset) {
        count++;
        expect(data[offset + TransformOffsets.x], isNotNull);
      });
      expect(count, equals(4000));
    });

    test('E2E-AC3-003: Contiguous TransformStorage 16-float stride layout and direct buffer access', () {
      final storage = TransformStorage(initialCapacity: 16);
      final e1 = Entity(10);
      final e2 = Entity(20);

      storage.set(
        e1,
        x: 10.0, y: 20.0, z: 30.0,
        flags: TransformFlags.dirty,
        qx: 0.0, qy: 0.0, qz: 0.707, qw: 0.707,
        sx: 2.0, sy: 2.0, sz: 2.0,
        boundsRadius: 5.0,
      );

      storage.set(
        e2,
        x: -5.0, y: -10.0, z: -15.0,
        sx: 1.0, sy: 1.0, sz: 1.0,
      );

      expect(storage.count, equals(2));

      // Verify raw Float32List buffer directly
      final buffer = storage.data;
      final dense0 = storage.dense[0];
      final dense1 = storage.dense[1];

      expect(dense0, equals(10));
      expect(dense1, equals(20));

      // Entity 1 at offset 0 * 16 = 0
      expect(buffer[0 + TransformOffsets.x], equals(10.0));
      expect(buffer[0 + TransformOffsets.y], equals(20.0));
      expect(buffer[0 + TransformOffsets.z], equals(30.0));
      expect(buffer[0 + TransformOffsets.flags], equals(TransformFlags.dirty.toDouble()));
      expect(buffer[0 + TransformOffsets.sx], equals(2.0));
      expect(buffer[0 + TransformOffsets.boundsRadius], equals(5.0));

      // Entity 2 at offset 1 * 16 = 16
      expect(buffer[16 + TransformOffsets.x], equals(-5.0));
      expect(buffer[16 + TransformOffsets.y], equals(-10.0));
      expect(buffer[16 + TransformOffsets.z], equals(-15.0));
      expect(buffer[16 + TransformOffsets.sx], equals(1.0));
    });
  });
}

Future<void> main() async {
  await runSuite('AC 3 & Pillar 5: Contiguous TypedData ECS & 10,000 Entity Benchmark', defineTests);
}
