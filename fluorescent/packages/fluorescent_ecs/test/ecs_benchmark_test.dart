import 'package:flutter_test/flutter_test.dart';
import 'package:fluorescent_ecs/fluorescent_ecs.dart';

void main() {
  group('ECS 10,000 Entity Benchmark', () {
    test('successfully spawns and iterates over 10,000 entities using TypedData without throwing memory errors', () {
      final world = EcsWorld(initialCapacity: 1024);

      // --- Phase 1: Entity & Contiguous Transform Spawning ---
      final spawnStopwatch = Stopwatch()..start();
      for (int i = 0; i < 10000; i++) {
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
      }
      spawnStopwatch.stop();

      // Verification: Entity count and contiguous component presence
      expect(world.entityCount, equals(10000));
      expect(world.transforms.count, equals(10000));
      // Memory footprint assertion: 10,000 entities with 16 floats/entity is ~640 KB buffer
      expect(world.transforms.data.lengthInBytes, lessThan(2 * 1024 * 1024)); // < 2MB

      // --- Phase 2: 60 Simulation Frames with TypedData forEach ---
      // 10,000 entities * 60 frames = 600,000 component updates
      final iterStopwatch = Stopwatch()..start();
      for (int frame = 0; frame < 60; frame++) {
        world.transforms.forEach((entity, data, offset) {
          data[offset + TransformOffsets.y] += 0.5; // Translate Y by 0.5 per frame
        });
      }
      iterStopwatch.stop();

      // Verification: Data integrity after 60 frames
      // Entity 0 was initialized with y = 0.0, after 60 frames y should be 30.0
      expect(world.transforms.getY(const Entity(0)), closeTo(30.0, 1e-4));
      // Entity 5000: x should still be 5000.0, y should be 30.0
      expect(world.transforms.getX(const Entity(5000)), closeTo(5000.0, 1e-4));
      expect(world.transforms.getY(const Entity(5000)), closeTo(30.0, 1e-4));
      // Entity 9999: x should still be 9999.0, y should be 30.0
      expect(world.transforms.getX(const Entity(9999)), closeTo(9999.0, 1e-4));
      expect(world.transforms.getY(const Entity(9999)), closeTo(30.0, 1e-4));

      // --- Phase 3: Direct TypedData Buffer Iteration (Zero Callbacks) ---
      final rawStopwatch = Stopwatch()..start();
      final data = world.transforms.data;
      final count = world.transforms.count;
      const stride = TransformOffsets.stride;
      for (int frame = 0; frame < 60; frame++) {
        final totalFloats = count * stride;
        for (int offset = 0; offset < totalFloats; offset += stride) {
          data[offset + TransformOffsets.z] += 0.25; // Translate Z
        }
      }
      rawStopwatch.stop();

      // Verification: Z coordinate after 60 direct raw frames
      expect(world.transforms.getZ(const Entity(0)), closeTo(15.0, 1e-4));
      expect(world.transforms.getZ(const Entity(5000)), closeTo(15.0, 1e-4));
      expect(world.transforms.getZ(const Entity(9999)), closeTo(15.0, 1e-4));

      // --- Phase 4: Destruction & ID Recycling under Load ---
      final destroyStopwatch = Stopwatch()..start();
      // Destroy 5,000 entities (every even entity)
      for (int i = 0; i < 10000; i += 2) {
        final ok = world.destroyEntity(Entity(i));
        expect(ok, isTrue);
      }
      destroyStopwatch.stop();

      expect(world.entityCount, equals(5000));
      expect(world.transforms.count, equals(5000));

      // Re-spawn 5,000 entities to verify recycling
      for (int i = 0; i < 5000; i++) {
        final recycledEntity = world.createEntity();
        expect(recycledEntity.id, lessThan(10000)); // Must be recycled from previously destroyed
        world.transforms.set(recycledEntity, x: 1.0, y: 2.0, z: 3.0);
      }

      expect(world.entityCount, equals(10000));
      expect(world.transforms.count, equals(10000));
    });
  });
}
